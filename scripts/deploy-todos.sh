#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

# pull in code
git clone https://gitlab.com/azwickey/todos.git temp/todos

# update templates
kubectl config use-context $SHARED_SERVICES_NS
# cluster1
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[1].value" $(yq r $VARS_YAML todos.cluster1.baseDomain)
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[2].value" $(yq r $VARS_YAML shared-services.harbor.ingress)/library
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[3].value" $(yq r $VARS_YAML todos.cluster1.backendUrl)
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[4].value" \
   $(kubectl get images.kpack.io todos-api -o json | jq '.status.latestImage' | cut -d '@' -f 2 | tr -d '"')
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[5].value" \
   $(kubectl get images.kpack.io todos-edge -o json | jq '.status.latestImage' | cut -d '@' -f 2 | tr -d '"')
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[6].value" \
   $(kubectl get images.kpack.io todos-redis -o json | jq '.status.latestImage' | cut -d '@' -f 2 | tr -d '"')
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[7].value" \
   $(kubectl get images.kpack.io todos-webui -o json | jq '.status.latestImage' | cut -d '@' -f 2 | tr -d '"')
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[8].value" $(yq r $VARS_YAML todos.wavefront.application.name | base64 )
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[9].value" $(yq r $VARS_YAML todos.wavefront.uri | base64 )
yq write temp/todos/argo/cluster1.yaml -i "spec.source.helm.parameters[10].value" $(yq r $VARS_YAML todos.wavefront.apiToken | base64 )
argocd login $(yq r $VARS_YAML shared-services.argo.ingress) \
  --username admin \
  --password $(yq r $VARS_YAML shared-services.argo.password)
export WORKLOAD1_NAME=$(yq r $VARS_YAML workload1.name)
export WORKLOAD1_SERVER=$(argocd cluster list | grep $WORKLOAD1_NAME-argocd-token-user@$WORKLOAD1_NAME | awk '{print $1}')
yq write temp/todos/argo/cluster1.yaml -i "spec.destination.server" $WORKLOAD1_SERVER
kubectl apply -f temp/todos/argo/cluster1.yaml

# cluster2
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[1].value" $(yq r $VARS_YAML todos.cluster2.baseDomain)
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[2].value" $(yq r $VARS_YAML shared-services.harbor.ingress)/library
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[3].value" \
   $(kubectl get images.kpack.io todos-postgres -o json | jq '.status.latestImage' | cut -d '@' -f 2 | tr -d '"')
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[4].value" $(yq r $VARS_YAML todos.wavefront.application.name | base64 )
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[5].value" $(yq r $VARS_YAML todos.wavefront.uri | base64 )
yq write temp/todos/argo/cluster2.yaml -i "spec.source.helm.parameters[6].value" $(yq r $VARS_YAML todos.wavefront.apiToken | base64 )
export WORKLOAD2_NAME=$(yq r $VARS_YAML workload2.name)
export WORKLOAD2_SERVER=$(argocd cluster list | grep $WORKLOAD2_NAME-argocd-token-user@$WORKLOAD2_NAME | awk '{print $1}')
yq write temp/todos/argo/cluster2.yaml -i "spec.destination.server" $WORKLOAD2_SERVER
kubectl apply -f temp/todos/argo/cluster2.yaml