#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML
export SUPERVISOR_VIP=$(yq r $VARS_YAML vsphere.supervisor-vip)
export SUPERVISOR_USERNAME=$(yq r $VARS_YAML vsphere.username)
export SUPERVISOR_PWD=$(yq r $VARS_YAML vsphere.password)
export VCSA=$(yq r $VARS_YAML vsphere.host)
kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME

# Create Namespaces
python ./scripts/create-namespace.py -s $VCSA -u $SUPERVISOR_USERNAME -p $SUPERVISOR_PWD \
       -cl $(yq r $VARS_YAML vsphere.clusterName) -role EDIT -st USER -subject $SUPERVISOR_USERNAME \
       -domain $(echo $SUPERVISOR_USERNAME | cut -d "@" -f 2) -sp $(yq r $VARS_YAML shared-services.storage) \
       -ns $(yq r $VARS_YAML shared-services.namespace)
python ./scripts/create-namespace.py -s $VCSA -u $SUPERVISOR_USERNAME -p $SUPERVISOR_PWD \
       -cl $(yq r $VARS_YAML vsphere.clusterName) -role EDIT -st USER -subject $SUPERVISOR_USERNAME \
       -domain $(echo $SUPERVISOR_USERNAME | cut -d "@" -f 2) -sp $(yq r $VARS_YAML workload1.storage) \
       -ns $(yq r $VARS_YAML workload1.namespace)
python ./scripts/create-namespace.py -s $VCSA -u $SUPERVISOR_USERNAME -p $SUPERVISOR_PWD \
       -cl $(yq r $VARS_YAML vsphere.clusterName) -role EDIT -st USER -subject $SUPERVISOR_USERNAME \
       -domain $(echo $SUPERVISOR_USERNAME | cut -d "@" -f 2) -sp $(yq r $VARS_YAML workload2.storage) \
       -ns $(yq r $VARS_YAML workload2.namespace)

# Create Shared Services Cluster
kubectl config use-context $SUPERVISOR_VIP
mkdir -p generated/shared 
cp cd/apps/workload-cluster/values.yaml generated/shared/values-shared-services.yaml
yq write generated/shared/values-shared-services.yaml -i "name" $(yq r $VARS_YAML shared-services.name)
yq write generated/shared/values-shared-services.yaml -i "namespace" $(yq r $VARS_YAML shared-services.namespace)
yq write generated/shared/values-shared-services.yaml -i "kubernetesVersion" $(yq r $VARS_YAML shared-services.kubernetesVersion)
yq write generated/shared/values-shared-services.yaml -i "storage" $(yq r $VARS_YAML shared-services.storage)
yq write generated/shared/values-shared-services.yaml -i "controlPlaneCount" $(yq r $VARS_YAML shared-services.controlPlaneCount)
yq write generated/shared/values-shared-services.yaml -i "controlPlaneClass" $(yq r $VARS_YAML shared-services.controlPlaneClass)
yq write generated/shared/values-shared-services.yaml -i "workerCount" $(yq r $VARS_YAML shared-services.workerCount)
yq write generated/shared/values-shared-services.yaml -i "workerClass" $(yq r $VARS_YAML shared-services.workerClass)
helm install $(yq r $VARS_YAML shared-services.name) cd/apps/workload-cluster/ --namespace $(yq r $VARS_YAML shared-services.namespace) -f generated/shared/values-shared-services.yaml
export SHARED_SERVICES_NS=$(yq r $VARS_YAML shared-services.namespace)
export SHARED_SERVICES_NAME=$(yq r $VARS_YAML shared-services.name)
while kubectl get tanzukubernetesclusters $SHARED_SERVICES_NAME -n $SHARED_SERVICES_NS | grep running ; [ $? -ne 0 ]; do
	echo Shared Services Cluster is not Running...
	sleep 5s
done

kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP \
   --tanzu-kubernetes-cluster-name $SHARED_SERVICES_NAME \
   --tanzu-kubernetes-cluster-namespace $SHARED_SERVICES_NS \
   --insecure-skip-tls-verify \
   -u $SUPERVISOR_USERNAME

# Deploy pre-reqs for ArgoCD
kubectl config use-context $SHARED_SERVICES_NS
kubectl create clusterrolebinding psp:authenticated --clusterrole=psp:vmware-system-privileged --group=system:authenticated
# Cert Manager and ClusterIssuer
kubectl apply -f cd/apps/extensions-cert-manager
while kubectl get po -n cert-manager | grep Running | wc -l | grep 3 ; [ $? -ne 0 ]; do
    echo Cert Manager is not yet ready
    sleep 5s
done
sleep 10 # seems to be needed to allow cert manager pods to startup
cp manifests/shared-cluster-issuer-dns.yaml generated/shared/
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.region" $(yq r $VARS_YAML aws.region)
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.hostedZoneID" $(yq r $VARS_YAML aws.hostedZoneId)
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.accessKeyID" $(yq r $VARS_YAML aws.accessKey)
kubectl create secret generic route53-credentials --from-literal=secret-access-key=$(yq r $VARS_YAML aws.secretKey) -n cert-manager
kubectl apply -f generated/shared/shared-cluster-issuer-dns.yaml
#ExternalDNS
#helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add tac https://charts.trials.tac.bitnami.com/demo
cp manifests/values-external-dns.yaml generated/shared/
yq write generated/shared/values-external-dns.yaml -i "aws.credentials.secretKey" $(yq r $VARS_YAML aws.secretKey)
yq write generated/shared/values-external-dns.yaml -i "aws.credentials.accessKey" $(yq r $VARS_YAML aws.accessKey)
yq write generated/shared/values-external-dns.yaml -i "aws.region" $(yq r $VARS_YAML aws.region)
yq write generated/shared/values-external-dns.yaml -i "txtOwnerId" $(yq r $VARS_YAML aws.hostedZoneId)
helm install external-dns-aws tac/external-dns --version 3.5.0 -f generated/shared/values-external-dns.yaml
#Wait for pod to be ready
while kubectl get po -l app.kubernetes.io/name=external-dns -n default | grep Running ; [ $? -ne 0 ]; do
	echo external-dns is not yet ready
	sleep 5s
done

# Deploy ArgoCD
kubectl create ns argocd
helm repo add argo https://argoproj.github.io/argo-helm
export ARGOCD_PWD=$(yq r $VARS_YAML shared-services.argo.password)
echo "argopwd: $ARGOCD_PWD"
export ARGOCD_PWD_ENCODE=$(htpasswd -nbBC 10 "" $ARGOCD_PWD | tr -d ':\n' | sed 's/$2y/$2a/')
echo "Encoded argopwd: $ARGOCD_PWD_ENCODE"
cp manifests/values-argocd.yaml generated/shared/
yq write generated/shared/values-argocd.yaml -i "configs.secret.argocdServerAdminPassword" $ARGOCD_PWD_ENCODE
yq write generated/shared/values-argocd.yaml -i "server.certificate.domain" $(yq r $VARS_YAML shared-services.argo.ingress)
yq write generated/shared/values-argocd.yaml -i 'server.service.annotations."external-dns.alpha.kubernetes.io/hostname"' $(yq r $VARS_YAML shared-services.argo.ingress) 
helm install argocd argo/argo-cd -f generated/shared/values-argocd.yaml  -n argocd
echo "waiting for ArgoCD VIP"
sleep 10  # Need to wait for VIP to assign
export ARGO_VIP=$(kubectl get svc -n argocd argocd-server -o json | jq -r '.status.loadBalancer.ingress | .[].ip')
echo "ArgoCD VIP: $ARGO_VIP"
#Wait for argo and ingress to be ready
while nslookup $(yq r $VARS_YAML shared-services.argo.ingress) | grep $ARGO_VIP ; [ $? -ne 0 ]; do
	echo Argo Server and DNS is not yet ready
	sleep 5s
done

# Login and config clusters
argocd login $(yq r $VARS_YAML shared-services.argo.ingress) \
  --username admin \
  --password $ARGOCD_PWD
kubectl create serviceaccount argocd -n argocd
kubectl create clusterrolebinding argocd --clusterrole=cluster-admin --serviceaccount=argocd:argocd
export TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
export TOKEN=$(kubectl get secret -n argocd $TOKEN_SECRET -o jsonpath='{.data.token}' | base64 --decode)
kubectl config set-credentials $SHARED_SERVICES_NAME-argocd-token-user --token $TOKEN
kubectl config set-context $SHARED_SERVICES_NAME-argocd-token-user@$SHARED_SERVICES_NAME \
  --user $SHARED_SERVICES_NS-argocd-token-user \
  --cluster $(kubectl config get-contexts $SHARED_SERVICES_NAME --no-headers | awk '{print $3}')
argocd cluster add #Dump configs
argocd cluster add $SHARED_SERVICES_NAME-argocd-token-user@$SHARED_SERVICES_NAME
#argocd cluster add $SUPERVISOR_VIP  #Add Supervisor Cluster
argocd cluster list 

# Bootstrap Shared-Services App-of-Apps
export SERVER=$(argocd cluster list | grep $SHARED_SERVICES_NS-argocd-token-user@$SHARED_SERVICES_NS | awk '{print $1}')
argocd app create shared-services-app-of-apps \
  --repo $(yq r $VARS_YAML repo) \
  --dest-server $SERVER \
  --dest-namespace default \
  --sync-policy automated \
  --path cd/clusters/shared-services \
  --helm-set server=$SERVER \
  --helm-set dex.clientSecret=$(yq r $VARS_YAML dex.clientSecret)
  

# Deploy workload clusters  TODO -- this needs to go into argoCD
kubectl config use-context $SUPERVISOR_VIP
mkdir -p generated/supervisor
cp cd/apps/workload-cluster/values.yaml generated/supervisor/workload1.yaml
cp cd/apps/workload-cluster/values.yaml generated/supervisor/workload2.yaml
# Workload 1
yq write generated/supervisor/workload1.yaml -i "name" $(yq r $VARS_YAML workload1.name)
yq write generated/supervisor/workload1.yaml -i "namespace" $(yq r $VARS_YAML workload1.namespace)
yq write generated/supervisor/workload1.yaml -i "kubernetesVersion" $(yq r $VARS_YAML workload1.kubernetesVersion)
yq write generated/supervisor/workload1.yaml -i "storage" $(yq r $VARS_YAML workload1.storage)
yq write generated/supervisor/workload1.yaml -i "controlPlaneCount" $(yq r $VARS_YAML workload1.controlPlaneCount)
yq write generated/supervisor/workload1.yaml -i "controlPlaneClass" $(yq r $VARS_YAML workload1.controlPlaneClass)
yq write generated/supervisor/workload1.yaml -i "workerCount" $(yq r $VARS_YAML workload1.workerCount)
yq write generated/supervisor/workload1.yaml -i "workerClass" $(yq r $VARS_YAML workload1.workerClass)
helm install $(yq r $VARS_YAML workload1.name) cd/apps/workload-cluster/ --namespace $(yq r $VARS_YAML workload1.namespace) -f generated/supervisor/workload1.yaml
# Workload 2
yq write generated/supervisor/workload2.yaml -i "name" $(yq r $VARS_YAML workload2.name)
yq write generated/supervisor/workload2.yaml -i "namespace" $(yq r $VARS_YAML workload2.namespace)
yq write generated/supervisor/workload2.yaml -i "kubernetesVersion" $(yq r $VARS_YAML workload2.kubernetesVersion)
yq write generated/supervisor/workload2.yaml -i "storage" $(yq r $VARS_YAML workload2.storage)
yq write generated/supervisor/workload2.yaml -i "controlPlaneCount" $(yq r $VARS_YAML workload2.controlPlaneCount)
yq write generated/supervisor/workload2.yaml -i "controlPlaneClass" $(yq r $VARS_YAML workload2.controlPlaneClass)
yq write generated/supervisor/workload2.yaml -i "workerCount" $(yq r $VARS_YAML workload2.workerCount)
yq write generated/supervisor/workload2.yaml -i "workerClass" $(yq r $VARS_YAML workload2.workerClass)
helm install $(yq r $VARS_YAML workload2.name) cd/apps/workload-cluster/ --namespace $(yq r $VARS_YAML workload2.namespace) -f generated/supervisor/workload2.yaml
sleep 10

while kubectl get tanzukubernetesclusters $(yq r $VARS_YAML workload1.name) -n $(yq r $VARS_YAML workload1.namespace) | grep running ; [ $? -ne 0 ]; do
	echo $(yq r $VARS_YAML workload1.name) Cluster is not Running...
	sleep 5s
done

while kubectl get tanzukubernetesclusters $(yq r $VARS_YAML workload2.name) -n $(yq r $VARS_YAML workload2.namespace) | grep running ; [ $? -ne 0 ]; do
	echo $(yq r $VARS_YAML workload2.name) Cluster is not Running...
	sleep 5s
done

#Add Workloads to ArgoCD
export WORKLOAD1_NAME=$(yq r $VARS_YAML workload1.name)
export WORKLOAD1_NAMESPACE=$(yq r $VARS_YAML workload1.namespace)
kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP \
   --tanzu-kubernetes-cluster-name $WORKLOAD1_NAME \
   --tanzu-kubernetes-cluster-namespace $WORKLOAD1_NAMESPACE \
   --insecure-skip-tls-verify \
   -u $SUPERVISOR_USERNAME
kubectl config use-context $WORKLOAD1_NAME
kubectl create ns argocd
kubectl create serviceaccount argocd -n argocd
kubectl create clusterrolebinding argocd --clusterrole=cluster-admin --serviceaccount=argocd:argocd
export TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
export TOKEN=$(kubectl get secret -n argocd $TOKEN_SECRET -o jsonpath='{.data.token}' | base64 --decode)
kubectl config set-credentials $WORKLOAD1_NAME-argocd-token-user --token $TOKEN
kubectl config set-context $WORKLOAD1_NAME-argocd-token-user@$WORKLOAD1_NAME \
  --user $WORKLOAD1_NAME-argocd-token-user \
  --cluster $(kubectl config get-contexts $WORKLOAD1_NAME --no-headers | awk '{print $3}')
argocd cluster add #Dump configs
argocd cluster add $WORKLOAD1_NAME-argocd-token-user@$WORKLOAD1_NAME
argocd cluster list

export WORKLOAD2_NAME=$(yq r $VARS_YAML workload2.name)
export WORKLOAD2_NAMESPACE=$(yq r $VARS_YAML workload2.namespace)
kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP \
   --tanzu-kubernetes-cluster-name $WORKLOAD2_NAME \
   --tanzu-kubernetes-cluster-namespace $WORKLOAD2_NAMESPACE \
   --insecure-skip-tls-verify \
   -u $SUPERVISOR_USERNAME
kubectl config use-context $WORKLOAD2_NAME
kubectl create ns argocd
kubectl create serviceaccount argocd -n argocd
kubectl create clusterrolebinding argocd --clusterrole=cluster-admin --serviceaccount=argocd:argocd
export TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
export TOKEN=$(kubectl get secret -n argocd $TOKEN_SECRET -o jsonpath='{.data.token}' | base64 --decode)
kubectl config set-credentials $WORKLOAD2_NAME-argocd-token-user --token $TOKEN
kubectl config set-context $WORKLOAD2_NAME-argocd-token-user@$WORKLOAD2_NAME \
  --user $WORKLOAD2_NAME-argocd-token-user \
  --cluster $(kubectl config get-contexts $WORKLOAD2_NAME --no-headers | awk '{print $3}')
argocd cluster add #Dump configs
argocd cluster add $WORKLOAD2_NAME-argocd-token-user@$WORKLOAD2_NAME
argocd cluster list

# Bootstrap workloads App-of-Apps
export WORKLOAD1_SERVER=$(argocd cluster list | grep $WORKLOAD1_NAME-argocd-token-user@$WORKLOAD1_NAME | awk '{print $1}')
argocd app create $WORKLOAD1_NAME-app-of-apps \
  --repo $(yq r $VARS_YAML repo) \
  --dest-server $WORKLOAD1_SERVER \
  --dest-namespace default \
  --sync-policy automated \
  --path cd/clusters/workload1 \
  --helm-set server=$WORKLOAD1_SERVER \
  --helm-set aws.credentials.secretKey=$(yq r $VARS_YAML aws.secretKey)

export WORKLOAD2_SERVER=$(argocd cluster list | grep $WORKLOAD2_NAME-argocd-token-user@$WORKLOAD2_NAME | awk '{print $1}')
argocd app create $WORKLOAD2_NAME-app-of-apps \
  --repo $(yq r $VARS_YAML repo) \
  --dest-server $WORKLOAD2_SERVER \
  --dest-namespace default \
  --sync-policy automated \
  --path cd/clusters/workload2 \
  --helm-set server=$WORKLOAD2_SERVER \
  --helm-set aws.credentials.secretKey=$(yq r $VARS_YAML aws.secretKey)

# Add to TMC
export TMC_API_TOKEN=$(yq r $VARS_YAML tmc.token)
export TMC_GROUP=$(yq r $VARS_YAML tmc.group)
kubectl config use-context $SHARED_SERVICES_NAME
echo TMC_API_TOKEN=$TMC_API_TOKEN
echo TMC_GROUP=$TMC_GROUP
tmc login --no-configure --name temp
tmc cluster attach -g $TMC_GROUP -n $SHARED_SERVICES_NAME -o generated/shared/tmc.yaml --management-cluster-name attached --provisioner-name attached
kubectl apply -f generated/shared/tmc.yaml
kubectl config use-context $WORKLOAD1_NAME
echo TMC_API_TOKEN=$TMC_API_TOKEN
echo TMC_GROUP=$TMC_GROUP
tmc login --no-configure --name temp
tmc cluster attach -g $TMC_GROUP -n $WORKLOAD1_NAME -o generated/workload1/tmc.yaml --management-cluster-name attached --provisioner-name attached
kubectl apply -f generated/workload1/tmc.yaml
kubectl config use-context $WORKLOAD2_NAME
tmc login --no-configure --name temp
tmc cluster attach -g $TMC_GROUP -n $WORKLOAD2_NAME -o generated/workload2/tmc.yaml --management-cluster-name attached --provisioner-name attached
kubectl apply -f generated/workload2/tmc.yaml

