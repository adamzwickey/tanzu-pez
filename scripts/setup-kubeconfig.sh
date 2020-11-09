#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
export SUPERVISOR_VIP=$(yq r $VARS_YAML vsphere.supervisor-vip)
export SUPERVISOR_USERNAME=$(yq r $VARS_YAML vsphere.username)
export SUPERVISOR_PWD=$(yq r $VARS_YAML vsphere.password)
export SHARED_SERVICES_NS=$(yq r $VARS_YAML shared-services.namespace)
export SHARED_SERVICES_NAME=$(yq r $VARS_YAML shared-services.name)
export WORKLOAD1_NAME=$(yq r $VARS_YAML workload1.name)
export WORKLOAD2_NAME=$(yq r $VARS_YAML workload2.name)
export WORKLOAD1_NAMESPACE=$(yq r $VARS_YAML workload1.namespace)
export WORKLOAD2_NAMESPACE=$(yq r $VARS_YAML workload2.namespace)

echo "Logging into supervisor cluster..."
expect <<EOD
spawn kubectl vsphere login --server=$SUPERVISOR_VIP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME
expect "Password: "
send "$SUPERVISOR_PWD\n"
expect
EOD

echo "Logging into shared services cluster..."
expect <<EOD
spawn kubectl vsphere login --server=$SUPERVISOR_VIP --tanzu-kubernetes-cluster-name $SHARED_SERVICES_NAME --tanzu-kubernetes-cluster-namespace $SHARED_SERVICES_NS --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME
expect "Password: "
send "$SUPERVISOR_PWD\n"
expect
EOD

echo "Logging into workload cluster1..."
expect <<EOD
spawn kubectl vsphere login --server=$SUPERVISOR_VIP --tanzu-kubernetes-cluster-name $WORKLOAD1_NAME --tanzu-kubernetes-cluster-namespace $WORKLOAD1_NAMESPACE --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME
expect "Password: "
send "$SUPERVISOR_PWD\n"
expect
EOD

echo "Logging into workload cluster2..."
expect <<EOD
spawn kubectl vsphere login --server=$SUPERVISOR_VIP --tanzu-kubernetes-cluster-name $WORKLOAD2_NAME --tanzu-kubernetes-cluster-namespace $WORKLOAD2_NAMESPACE --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME
expect "Password: "
send "$SUPERVISOR_PWD\n"
expect
EOD