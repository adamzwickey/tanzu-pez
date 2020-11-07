#!/usr/bin/env bash
echo "******************************"
echo "Installing bootstrapping tools"
echo "******************************"

echo "-- Installing kubectl and plugin --"
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
export SUPERVISOR_VIP=$(yq r $VARS_YAML vsphere.supervisor-vip)
sudo apt-get install -y unzip
curl -k https://$SUPERVISOR_VIP/wcp/plugin/linux-amd64/vsphere-plugin.zip --output vsphere-plugin.zip
unzip vsphere-plugin.zip
sudo mv bin/kubectl /usr/local/bin/
sudo mv bin/kubectl-vsphere /usr/local/bin/

echo "-- Installing jq --"
sudo apt-get install -y jq

echo "-- Installing yq --"
sudo snap install yq

echo "-- Installing helm --"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "-- Installing argocd cli --"
wget https://github.com/argoproj/argo-cd/releases/download/v1.7.7/argocd-linux-amd64
chmod u+x argocd-linux-amd64
chmod o+x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd 
argocd version

echo "-- Installing httpdpasswd --"
sudo apt install -y apache2-utils

echo "-- Installing expect --"
sudo apt-get install -y expect

echo "-- Installing git --"
sudo apt-get install git -y