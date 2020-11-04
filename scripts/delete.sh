#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

export SUPERVISOR_VIP=$(yq r $VARS_YAML vsphere.supervisor-vip)
export SUPERVISOR_USERNAME=$(yq r $VARS_YAML vsphere.username)
export SUPERVISOR_PWD=$(yq r $VARS_YAML vsphere.password)
kubectl vsphere login -v 8 --server=$SUPERVISOR_VIP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME
kubectl config use-context $SUPERVISOR_VIP

# Delete workloads
helm uninstall $(yq r $VARS_YAML workload1.name) --namespace $(yq r $VARS_YAML workload1.namespace)
helm uninstall $(yq r $VARS_YAML workload2.name) --namespace $(yq r $VARS_YAML workload2.namespace)

# Delete Shared-services
helm uninstall $(yq r $VARS_YAML shared-services.name) --namespace $(yq r $VARS_YAML shared-services.namespace)