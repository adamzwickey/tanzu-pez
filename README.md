# tanzu-pez
This project is meant to automate the paving of TKG-S environments, including common extensions, in an PEZ env.  It includes TKG-S, TMC, TAC, TBS, TSM (automation soon), and TO (automation soon).  You could call this "__Tanzu In A Box__".  


![home](https://gitlab.com/azwickey/tanzu-pez/-/raw/master/img/arch.png "arch")

Most installations are done via and ArgoCD utilizing the [App of Apps pattern](https://argoproj.github.io/argo-cd/operator-manual/cluster-bootstrapping/)


![home](https://gitlab.com/azwickey/tanzu-pez/-/raw/master/img/argo.png "argo")

## Installation
It will be easiest and fastest to execute the bootstrapping from the ubuntu jumpbox.  However, it is also possible to execute from a local workstation (e.g. macbook) assuming that you have network connectivity over VPN to all VMs in cluster.  Note, that tools install script will only work in an Ubuntu env.

- Make sure that you have a vSphere 7u1 environment with WCP succesfully enabled.
- Fork this repo.  Since this is your GitOps source of truth, you must fork rather than simply clone
- Make a copy of vars.yaml.example named vars.yaml in the root directory of your repo. You must set an environment variable indicating where your vars.yaml is located.
```bash
export VARS_YAML=vars.yaml 
```
- Edit vars.yaml, providing configuration values that reflect your desired envornment.
- Additionally, edit the values.yaml file(s) in `/cd/clusters/shared-services`, `/cd/clusters/workload1`, and `/cd/clusters/workload2` to reflect your environment.  This will drive the true GitOps worklfow.  Any value that has a comment of `# This must be overridden ` does not need to be changed as this is a _Secret_ that will be read from the vars.yaml.  These changes must be checked into and pushed to your fork of the repo.
- Prepare your jumpbox with the needed tools (kubectl w/ vsphere plugin, jq, yq, argocd cli, ect...) by executing the tools installation script.  Note that you'll need to enter your sudo pwd for apt-get installations.
```bash
source ./scripts/install-tools.sh
```
- There are a few tools you must download and install yourself:
```bash
-- TMC CLI
-- ytt
-- kbld
-- kapp
-- kp
```

- When you are ready to deploy execute the install script:
```bash
source ./scripts/bootstrap.sh
```
- Installation typically takes around 45 min, depending on the speed of your env.  In almost all cases the install script is Idempotent.  If you have an incorrect setting you typically can simply re-execute the script.

## Cleanup
- To tear down the env execute the delete script.  At the moment this script doesn't remove the cluser from TMC or TSM.
```bash
source ./scripts/delete.sh
```