#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

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