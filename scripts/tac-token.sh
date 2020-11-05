#!/usr/bin/env bash
kubectl get secret $(kubectl get serviceaccount kubeapps-operator -n kubeapps -o jsonpath='{range .secrets[*]}{.name}{"\n"}{end}' | grep kubeapps-operator-token) -n kubeapps -o jsonpath='{.data.token}' -o go-template='{{.data.token | base64decode}}' | pbcopy
echo "*************************"
echo "Token copied to clipboard"
echo "*************************"