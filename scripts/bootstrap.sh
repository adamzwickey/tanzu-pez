#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

# Login
# curl -vvv -k \
#    -H "vmware-use-header-authn: application/json" \
#    https://vcsa-01.haas-439.pez.vmware.com/rest/com/vmware/cis/session
#curl -vvv -k c  https://vcsa-01.haas-439.pez.vmware.com/api/vcenter/namespaces/instances 
export SUPERVISOR_VIP=$(yq r $VARS_YAML vsphere.supervisor-vip)
export SUPERVISOR_USERNAME=$(yq r $VARS_YAML vsphere.username)
export SUPERVISOR_PWD=$(yq r $VARS_YAML vsphere.password)
kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME

# Namespaces

# Create Shared Services Cluster
mkdir -p generated/shared 
export SHARED_SERVICES_NS=$(yq r $VARS_YAML shared-services.namespace)
kubectl config use-context $SUPERVISOR_VIP
cp manifests/shared-services.yaml generated/shared/
yq write generated/shared/shared-services.yaml -i "metadata.namespace" $SHARED_SERVICES_NS
kubectl apply -f generated/shared/shared-services.yaml
while kubectl get tanzukubernetesclusters shared-services -n $SHARED_SERVICES_NS | grep running ; [ $? -ne 0 ]; do
	echo Shared Services Cluster is not Running...
	sleep 5s
done

kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP \
   --tanzu-kubernetes-cluster-name shared-services \
   --tanzu-kubernetes-cluster-namespace $SHARED_SERVICES_NS \
   --insecure-skip-tls-verify \
   -u $SUPERVISOR_USERNAME

# Deploy pre-reqs for ArgoCD
kubectl config use-context $SHARED_SERVICES_NS
kubectl create clusterrolebinding psp:authenticated --clusterrole=psp:vmware-system-privileged --group=system:authenticated
# Cert Manager and ClusterIssuer
kubectl apply -f cd/apps/extensions-cert-manager
cp manifests/shared-cluster-issuer-dns.yaml generated/shared/
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.region" $(yq r $VARS_YAML aws.region)
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.hostedZoneID" $(yq r $VARS_YAML aws.hostedZoneId)
yq write generated/shared/shared-cluster-issuer-dns.yaml -i "spec.acme.solvers[0].dns01.route53.accessKeyID" $(yq r $VARS_YAML aws.accessKey)
kubectl create secret generic route53-credentials --from-literal=secret-access-key=$(yq r $VARS_YAML aws.secretKey) -n cert-manager
kubectl apply -f generated/shared/shared-cluster-issuer-dns.yaml
#ExternalDNS
helm repo add bitnami https://charts.bitnami.com/bitnami
cp manifests/values-external-dns.yaml generated/shared/
yq write generated/shared/values-external-dns.yaml -i "aws.credentials.secretKey" $(yq r $VARS_YAML aws.secretKey)
yq write generated/shared/values-external-dns.yaml -i "aws.credentials.accessKey" $(yq r $VARS_YAML aws.accessKey)
yq write generated/shared/values-external-dns.yaml -i "aws.region" $(yq r $VARS_YAML aws.region)
yq write generated/shared/values-external-dns.yaml -i "txtOwnerId" $(yq r $VARS_YAML aws.hostedZoneId)
helm install external-dns-aws bitnami/external-dns -f generated/shared/values-external-dns.yaml
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
kubectl config set-credentials $SHARED_SERVICES_NS-argocd-token-user --token $TOKEN
kubectl config set-context $SHARED_SERVICES_NS-argocd-token-user@$SHARED_SERVICES_NS \
  --user $SHARED_SERVICES_NS-argocd-token-user \
  --cluster $(kubectl config get-contexts shared-services --no-headers | awk '{print $3}')
argocd cluster add #Dump configs
argocd cluster add $SHARED_SERVICES_NS-argocd-token-user@$SHARED_SERVICES_NS
argocd cluster add $SUPERVISOR_VIP  #Add Supervisor Cluster
argocd cluster list 

# Bootstrap Shared-Services App-of-Apps
export SERVER=$(argocd cluster list | grep $SHARED_SERVICES_NS-argocd-token-user@$SHARED_SERVICES_NS | awk '{print $1}')
argocd app create shared-services-app-of-apps \
  --repo $(yq r $VARS_YAML repo) \
  --dest-server $SERVER \
  --dest-namespace default \
  --sync-policy automated \
  --path cd/clusters/shared-services \
  --helm-set server=$SERVER

# Deploy workload clusters

# Bootstrap workload App-of-Apps