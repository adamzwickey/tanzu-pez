#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

# Delete workloads
helm uninstall $(yq r $VARS_YAML workload1.name) --namespace $(yq r $VARS_YAML workload1.namespace)
helm uninstall $(yq r $VARS_YAML workload2.name) --namespace $(yq r $VARS_YAML workload2.namespace)

# Delete Shared-services
kubectl delete -f generated/shared/shared-services.yaml