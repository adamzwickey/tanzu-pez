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

echo "-- Installing tmc cli --"
curl https://akamai.bintray.com/ca/ca3724bd7acd1cc156d71a44c4d2d73f2eb42972a814f179022bd36f1649da07\?__gda__\=exp\=1604704022\~hmac\=1d93273b7cc1c8c3b492975783e9ba7bf987974adab93f6c4f5a4bacaefa1d53\&response-content-disposition\=attachment%3Bfilename%3D%22tmc%22\&response-content-type\=application%2Fx-executable\&requestInfo\=U2FsdGVkX1_dmraKUe7uQ8KoGO-jh_2sOTsrWdrbPU-ZuDTVuA189QKZ0BZcm622Pm4iL9mK0a2XXhGRv2jzXD2l4ZCGvpb1QQQjnmp7GmunWRi0M8ky4BDrA8I7hU1k\&response-X-Checksum-Sha1\=b6e97938f4432db67e4ba00514c9fd607f19d283\&response-X-Checksum-Sha2\=ca3724bd7acd1cc156d71a44c4d2d73f2eb42972a814f179022bd36f1649da07 --output tmc
chmod u+x tmc 
sudo mv tmc /usr/local/bin

echo "-- Installing expect --"
sudo apt-get install -y expect

echo "-- Installing git --"
sudo apt-get install git -y