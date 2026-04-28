#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-lib.sh" ]; then . ../../aa/lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

export K8S_TEST_POD
readonly K8S_TEST_POD='run-test'

export K8S_UP_YAML
readonly K8S_UP_YAML='up.yaml'

export K8S_SET_YAML
readonly K8S_SET_YAML='set.yaml'

k8sIsWorkdir(){
  local workdir="$1"
  # 是正确的 workdir
  if [ -f "$workdir/service.yaml" ] || [ -f "$workdir/service.yml" ]; then
    return 0
  fi
  return 1
}
export k8sIsWorkdir
readonly k8sIsWorkdir

k8sAutoPullImages(){
  local _k8s_workdir="$1"
  local _k8s_yaml

  PanicIfNotDir "$_k8s_workdir"

  while IFS= read -r -d '' _k8s_yaml; do
    # 提取所有镜像（空格分隔）
    _k8s_images="$(kubectl apply -f "$_k8s_yaml" --dry-run=client -o jsonpath="{..containers[*].image}" 2>/dev/null || true)"

    if [ -n "$_k8s_images" ]; then
      for _k8s_image in $_k8s_images; do
        if [ -n "$_k8s_image" ]; then
          Info "Pulling image: $_k8s_image"
          SUDO nerdctl pull "$_k8s_image"
        fi
      done
    fi
  done < <(find "$_k8s_workdir" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) ! -name "$K8S_UP_YAML" -print0 2>/dev/null)
}
export k8sAutoPullImages
readonly k8sAutoPullImages

k8sCreateTlsSecret(){
  Usage $# -eq 4 "k8sCreateTlsSecret <namespace> <name> <privkey_file=$CERT_KEY_FILE> <cert_file=$CERT_FILE>"
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_privkey="${3:-"$CERT_KEY_FILE"}"
  local _k8s_cert="${4:-"$CERT_FILE"}"

  Info "Creating tls secret..."
  Debug "sudo kubectl create secret tls $_k8s_service -n $_k8s_namespace --key=$_k8s_privkey --cert=$_k8s_cert"
  if ! SUDO kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --key="$_k8s_privkey" --cert="$_k8s_cert" >/dev/null; then
    PanicD "create tls secret failed" "创建tls secret失败"
  fi

  Info "Verifying tls secret..."
  Debug "sudo kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! SUDO kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify kubectl secret failed" "验证 kubectl secret 失败"
  fi
}
export k8sCreateTlsSecret
readonly k8sCreateTlsSecret



k8sRmiNoneImages(){
  Info "sudo nerdctl image prune -f"
  SUDO nerdctl image prune -f
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages