#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-lib.sh" ]; then . ../../aa/lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

K8S_TEST_POD='run-test'
export K8S_TEST_POD
readonly K8S_TEST_POD

k8sCreateTlsSecret(){
  Usage $# -eq 4 'k8sCreateTlsSecret <namespace> <name> <privkey_file> <cert_file>'
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_privkey="$3"
  local _k8s_cert="$4"

  Info "Creating tls secret..."
  Debug "sudo kubectl create secret tls $_k8s_service -n $_k8s_namespace --key=$_k8s_privkey --cert=$_k8s_cert"
  if ! sudo kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --key="$_k8s_privkey" --cert="$_k8s_cert"; then
    PanicD "create tls secret failed" "创建tls secret失败"
  fi

  Info "Verifying tls secret..."
  Debug "sudo kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! sudo kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify kubectl secret failed" "验证 kubectl secret 失败"
  fi
}
export k8sCreateTlsSecret
readonly k8sCreateTlsSecret



k8sRmiNoneImages(){
  Info "sudo nerdctl image prune -f"
  sudo nerdctl image prune -f
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages