#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-probe.sh" ]; then . ./k8s-probe.sh; else . /opt/k8s/lib/k8s-probe.sh; fi

export K8S_SET_YAML
readonly K8S_SET_YAML='set.yaml'

export K8S_UP_YAML
readonly K8S_UP_YAML='k8s.yaml'

k8sPullImages(){
  echo ""
}
export k8sPullImages
readonly k8sPullImages

k8sCreateTlsSecret(){
  Usage $# -eq 4 "k8sCreateTlsSecret <namespace> <name> <privkey_file=$CERT_KEY_FILE> <cert_file=$CERT_FILE>"
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_privkey="${3:-"$CERT_KEY_FILE"}"
  local _k8s_cert="${4:-"$CERT_FILE"}"

  if $SUDO kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null 2>&1; then
    return 0
  fi

  Info "Creating tls secret..."
  Debug "kubectl create secret tls $_k8s_service -n $_k8s_namespace --key=$_k8s_privkey --cert=$_k8s_cert"
  if ! $SUDO kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --key="$_k8s_privkey" --cert="$_k8s_cert" >/dev/null; then
    PanicD "create tls secret failed" "创建tls secret失败"
  fi

  Info "Verifying tls secret..."
  Debug "kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! $SUDO kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify kubectl secret failed" "验证 kubectl secret 失败"
  fi
}
export k8sCreateTlsSecret
readonly k8sCreateTlsSecret


k8sUp(){
  k8sProbeConfigMap
  k8sPullImages

}
export k8sUp
readonly k8sUp