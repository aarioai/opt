#!/bin/bash
set -euo pipefail

# Require: nerdctl + helm

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-yq.sh" ]; then . ../../aa/lib/aa-posix-yq.sh; else . /opt/aa/lib/aa-posix-yq.sh; fi

export K8S_TEST_POD
readonly K8S_TEST_POD='aa-temp-test'

export K8S_ENV_YAML
readonly K8S_ENV_YAML='._env.yaml'

export K8S_SET_YAML_REL
readonly K8S_SET_YAML_REL='templates/set.yaml'

export K8S_GLOBAL_YAML
readonly K8S_GLOBAL_YAML='global.yaml'

export K8S_TLS_CERT_DIR_REL
readonly K8S_TLS_CERT_DIR_REL='.cert'

export K8S_TLS_CERT_DIR_FINAL
readonly K8S_TLS_CERT_DIR_FINAL='/etc/cert'

export K8S_NSENTER_CMD_TAG
readonly K8S_NSENTER_CMD_TAG='nsenter'

export K8S_SELECTOR_TAG
readonly K8S_SELECTOR_TAG='selector'


export K8S_TLS_TAG
readonly K8S_TLS_TAG='tls'

export K8S_TLS_CN_TAG
readonly K8S_TLS_CN_TAG='CN'    # common name

export K8S_TLS_CERT_TAG
readonly K8S_TLS_CERT_TAG='cert'

export K8S_TLS_CREAT_NX_TAG
readonly K8S_TLS_CREAT_NX_TAG='createNx'

export K8S_TLS_CERT_BASE_TAG
readonly K8S_TLS_CERT_BASE_TAG='base'

export K8S_TLS_CERT_DIR_TAG
readonly K8S_TLS_CERT_DIR_TAG='dir'

export K8S_TLS_EXPIRE_DAYS_TAG
readonly K8S_TLS_EXPIRE_DAYS_TAG='expireDays'

export K8S_TLS_CERT_FILE_TAG
readonly K8S_TLS_CERT_FILE_TAG='file'

export K8S_TLS_CERT_KEY_TAG
readonly K8S_TLS_CERT_KEY_TAG='key'

export K8S_TLS_DOWN_TAG
readonly K8S_TLS_DOWN_TAG='down'

export K8S_TLS_HOSTS_TAG
readonly K8S_TLS_HOSTS_TAG='hosts'

export K8S_TLS_SUBJ_TAG
readonly K8S_TLS_SUBJ_TAG='subj'

export K8S_TLS_SAN_TAG
readonly K8S_TLS_SAN_TAG='subjectAltName'  # subjectAltName

k8sDefaultContainerName(){
  Usage $# -eq 1 'k8sDefaultTlsSecretName <chart_name>'
  PanicIfEmpty "$1" 'chart_name'
  printf 'aa-%s' "$1"
}
export k8sDefaultContainerName
readonly k8sDefaultContainerName

k8sDefaultTlsSecretName(){
  Usage $# -eq 1 'k8sDefaultTlsSecretName <common_name>'
  PanicIfEmpty "$1" 'common_name'
  printf 'tls-%s' "$1"
}
export k8sDefaultTlsSecretName
readonly k8sDefaultTlsSecretName

k8sDefaultSelector(){
  Usage $# -eq 1 'k8sDefaultSelector <app>'
  PanicIfEmpty "$1" 'app'
  printf 'app=%s' "$1"
}
export k8sDefaultSelector
readonly k8sDefaultSelector

k8sKubectlPrefix(){
  local _k8s_cmd_prefix="$SUDO"
  if command -v k3s >/dev/null 2>&1; then
    _k8s_cmd_prefix="$_k8s_cmd_prefix k3s"
  fi
  printf '%s' "$_k8s_cmd_prefix"
}
export k8sKubectlPrefix
readonly k8sKubectlPrefix

k8sJournalCtrlError(){
  if command -v k3s >/dev/null 2>&1; then
    Debug "$SUDO journalctl -u k3s | grep error | tail -10"
    $SUDO journalctl -u k3s | grep error | tail -10
  fi
}
export k8sJournalCtrlError
readonly k8sJournalCtrlError

k8sRmiNoneImages(){
  Debug "nerdctl image prune -f $*"
  $SUDO nerdctl image prune -f "$@"
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages

k8sPvcStatus(){
  Usage $# -eq 2 'k8sPvcStatus <namespace> <pvc name>'
  local _k8s_namespace="$1"
  local _k8s_pvc="$2"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  local i
  for i in {1..30}; do
    local PVC_STATUS
    PVC_STATUS=$($_k8s_cmd_prefix kubectl get pvc "$_k8s_pvc" -n "$_k8s_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true || echo "Pending")
    if [ "$PVC_STATUS" = "Bound" ]; then
      return 0
    fi
    Debug "kubectl get pvc $_k8s_pvc -n $_k8s_namespace -o jsonpath='{.status.phase}' ($i/30)"
    sleep 2
  done

  $_k8s_cmd_prefix kubectl describe pvc "$_k8s_pvc" -n "$_k8s_namespace"
  return 1
}
export k8sPvcStatus
readonly k8sPvcStatus

k8sStatus(){
  Usage $# -ge 3 'k8sStatus <namespace> <selector> <container> [pvcs]...'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  local _k8s_container="$3"
  shift 3

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  Heading "[SERVICE] kubectl get service -n $_k8s_namespace -l $_k8s_selector -o wide"
  $_k8s_cmd_prefix kubectl get service -n "$_k8s_namespace" -l "$_k8s_selector" -o wide

  Heading "[POD] kubectl get pods -n $_k8s_namespace -l $_k8s_selector"
  $_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector"

  Heading "[CONTAINER] crictl ps -a --name $_k8s_container"
  $_k8s_cmd_prefix crictl ps -a --name "$_k8s_container"

  local _k8s_pvc_full
  for _k8s_pvc in "$@"; do
    for _k8s_pod in $($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
      _k8s_pvc_full="${_k8s_pvc}-${_k8s_pod}"
      Heading "[PVC] $_k8s_pvc_full"
      if ! k8sPvcStatus "$_k8s_namespace" "$_k8s_pvc_full"; then
        ErrorD "PVC $_k8s_pvc_full bind failed" "PVC ${_k8s_pvc_full}绑定失败"
      fi
    done
  done
}
export k8sStatus
readonly k8sStatus

k8sWaitReady(){
  Usage $# -ge 3 'k8sWaitReady <namespace> <selector> <container_name> [pvcs]...'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  local _k8s_container="$3"
  shift 3

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  Heading "kubectl wait --for=condition=Ready pod -n $_k8s_namespace -l $_k8s_selector --timeout=180s"
  if ! $_k8s_cmd_prefix kubectl wait --for=condition=Ready pod -n "$_k8s_namespace" -l "$_k8s_selector" --timeout=180s 2>/dev/null; then
    k8sLogs "$_k8s_namespace" "$_k8s_selector" "$_k8s_container"
    return 1
  fi

  k8sStatus "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" "$@"
}
export k8sWaitReady
readonly k8sWaitReady

k8sDestroy(){
  Usage $# 1 2 'k8sDestroy <namespace> [no_confirmation:|-y]'
  local _k8s_namespace="$1"
  local _k8s_no_confirm="${2:-}"

  if [ "$_k8s_no_confirm" != '-y' ]; then
    local _k8s_confirm_en="[DANGEROUS] destroy all pvc/services/pods/containers with namespace $_k8s_namespace?"
    local _k8s_confirm_cn="[危险] namespace $_k8s_namespace 可能包含其他服务，确定销毁该namespace下所有 pvc/services/pods/containers？"
    if ! ConfirmD "$_k8s_confirm_en" "$_k8s_confirm_cn"; then
      return 0
    fi
  fi

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  Warn "kubectl delete namespace $_k8s_namespace"
  $_k8s_cmd_prefix kubectl delete namespace "$_k8s_namespace" -v=6
}
export k8sDestroy
readonly k8sDestroy

k8sCreateTlsSecret(){
  Usage $# -eq 4 "k8sCreateTlsSecret <namespace> <name> <privkey_file=$CERT_KEY_FILE> <cert_file=$CERT_FILE>"
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_privkey="${3:-"$CERT_KEY_FILE"}"
  local _k8s_cert="${4:-"$CERT_FILE"}"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if $_k8s_cmd_prefix kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null 2>&1; then
    return 0
  fi

  InfoD "Creating tls secret..." "创建tls secret中..."
  Debug "kubectl create secret tls $_k8s_service -n $_k8s_namespace --key=$_k8s_privkey --cert=$_k8s_cert"
  if ! $_k8s_cmd_prefix kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --key="$_k8s_privkey" --cert="$_k8s_cert" >/dev/null; then
    PanicD "create tls secret failed" "创建tls secret失败"
  fi

  InfoD "Verifying tls secret..." "验证tls secret中..."
  Debug "kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! $_k8s_cmd_prefix kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify kubectl secret failed" "验证 kubectl secret 失败"
  fi
}
export k8sCreateTlsSecret
readonly k8sCreateTlsSecret

k8sDeleteSecret(){
  Usage $# -eq 2 'k8sDeleteSecret <namespace> <secret>'
  local _k8s_namespace="$1"
  local _k8s_secret="$2"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if $_k8s_cmd_prefix kubectl get secret "$_k8s_secret" -n "$_k8s_namespace" >/dev/null 2>&1; then
    Debug "kubectl delete secret $_k8s_secret -n $_k8s_namespace --ignore-not-found=true"
    $_k8s_cmd_prefix kubectl delete secret "$_k8s_secret" -n "$_k8s_namespace" --ignore-not-found=true
  fi
}
export k8sDeleteSecret
readonly k8sDeleteSecret

k8sTlsSecrets(){
  Usage $# 3 4 'k8sTlsSecrets <workdir> <namespace> <values> [format=|json]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_namespace="$2"
  local _k8s_values="$3"
  local _k8s_format="${4:-}"

  if ! k8sValuesExistsTLS "$_k8s_values"; then
    return
  fi

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  # {} and [] break yq's JSON conversion. Use base64 to encode them.
  local _k8s_tls_block
  _k8s_tls_block=$(printf '%s\n' "$_k8s_values" | yq -r ".${K8S_TLS_TAG} // [] | .[] | tojson | @base64" 2>/dev/null)

  local _k8s_tls_b64
  while IFS= read -r _k8s_tls_b64; do
    [ -z "$_k8s_tls_b64" ] && continue
    local _k8s_tls
    _k8s_tls=$(echo "$_k8s_tls_b64" | base64 -d)
    local _k8s_tls_cn
    _k8s_tls_cn=$(YqGet ".${K8S_TLS_CN_TAG}" -s  "$_k8s_tls" WITH_PANIC)
    local _k8s_secret
    _k8s_secret=$(k8sDefaultTlsSecretName "$_k8s_tls_cn")
    Highlight "${_H_LINE_}secret: $_k8s_secret${_H_LINE}"

    if $_k8s_cmd_prefix kubectl get secret "$_k8s_secret" -n "$_k8s_namespace" >/dev/null 2>&1; then
      if [ -n "$_k8s_format" ]; then
        $_k8s_cmd_prefix kubectl get secret "$_k8s_secret" -n "$_k8s_namespace" -o "$_k8s_format" 2>/dev/null || true
      else
        $_k8s_cmd_prefix kubectl get secret "$_k8s_secret" -n "$_k8s_namespace" 2>/dev/null || true
      fi
    else
      LowlightD "no tls secret $_k8s_secret -n $_k8s_namespace" "没有tls secret $_k8s_secret -n $_k8s_namespace"
    fi
  done <<EOF
$_k8s_tls_block
EOF
}
export k8sTlsSecrets
readonly k8sTlsSecrets

k8sFindCertDir(){
    Usage $# 2 4 "k8sFindCertDir <workdir> <common_name> [tls_base] [cert_filename=$CERT_FILE]"
    local _k8s_workdir
    _k8s_workdir="$(k8sWorkDir "$1")"
    local _k8s_tls_cn="$2"
    local _k8s_tls_base="${3:-}"
    local _k8s_tls_cert_file="${4:-"$CERT_FILE"}"

    local _k8s_tls_cert_dir
    # Specified tls base directory
    if [ -n "$_k8s_tls_base" ]; then
      _k8s_tls_cert_dir="${_k8s_tls_base}/${_k8s_tls_cn}"
      $SUDO mkdir -p "$_k8s_tls_cert_dir" >/dev/null 2>&1 || true
      printf '%s' "$_k8s_tls_cert_dir"
      return 0
    fi

    local _k8s_tls_d
    # must from: ../.. --> ../ --> ./
    for _k8s_tls_d in "${_k8s_workdir}/../../$K8S_TLS_CERT_DIR_REL" "${_k8s_workdir}/../$K8S_TLS_CERT_DIR_REL" "${_k8s_workdir}/$K8S_TLS_CERT_DIR_REL" ; do
      if [ -d "$_k8s_tls_d" ]; then
        _k8s_tls_cert_dir=$(AbsDir "${_k8s_tls_d}/${_k8s_tls_cn}")
        if [ -f "${_k8s_tls_cert_dir}/${_k8s_tls_cert_file}" ]; then
          printf '%s' "$_k8s_tls_cert_dir"
          return 0
        fi
      fi
    done

    if [ -z "$_k8s_tls_cert_dir" ]; then
      _k8s_tls_cert_dir="${K8S_TLS_CERT_DIR_FINAL}/${_k8s_tls_cn}"
    fi
    $SUDO mkdir -p "$_k8s_tls_cert_dir" >/dev/null 2>&1 || true
    printf '%s' "$_k8s_tls_cert_dir"
}
export k8sFindCertDir
readonly k8sFindCertDir

k8sLogs(){
  Usage $# 3 4 'k8sLogs <namespace> <selector> <container_name> [container|pod]'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  local _k8s_container_name="$3"
  local _k8s_id="${4:-}"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if [ -z "$_k8s_id" ]; then
    Debug "kubectl logs -n $_k8s_namespace -l $_k8s_selector -f"
    if $_k8s_cmd_prefix kubectl logs -n "$_k8s_namespace" -l "$_k8s_selector"; then
      local _k8s_err
      _k8s_err=$($_k8s_cmd_prefix kubectl logs -n "$_k8s_namespace" -l "$_k8s_selector" 2>&1)
      if [ "$_k8s_err" != "No resources found in $_k8s_namespace namespace." ]; then
        return 0
      fi
      k8sJournalCtrlError
    fi

    _k8s_id=$($_k8s_cmd_prefix crictl ps -a --name "$_k8s_container_name" --quiet)
    if [ -n "$_k8s_id" ]; then
      Debug "crictl logs $_k8s_id (container name: $_k8s_container_name)"
      if $_k8s_cmd_prefix crictl logs "$_k8s_id" 2>/dev/null; then
        return 0
      fi
    fi
    Error "container $_k8s_container_name is dead"
    local _k8s_pod
    _k8s_pod=$($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$_k8s_pod" ]; then
      Debug "try: kubectl describe pod -n $_k8s_namespace -l $_k8s_selector"
      k8sJournalCtrlError
      return 1
    fi
    Debug "kubectl describe pod $_k8s_pod -n $_k8s_namespace"
    $_k8s_cmd_prefix kubectl describe pod "$_k8s_pod" -n "$_k8s_namespace"
    local _k8s_error
    _k8s_error="$($_k8s_cmd_prefix kubectl describe pod "$_k8s_pod" -n "$_k8s_namespace" | grep -Ei "Error|Failed|Warning" )"
    if [ -n "$_k8s_error" ]; then echo ''; Panic "${_k8s_error}"; fi

  elif [ "$_k8s_id" = 'pod' ]; then
    Debug "kubectl describe pod -n $_k8s_namespace -l $_k8s_selector"
    $_k8s_cmd_prefix kubectl describe pod -n "$_k8s_namespace" -l "$_k8s_selector"
  else
    Debug "crictl logs $_k8s_id"
    $_k8s_cmd_prefix crictl logs "$_k8s_id"   # 失败容器重启，名称会变
  fi
}
export k8sLogs
readonly k8sLogs

k8sNsenter(){
  Usage $# -ge 2 'k8sNsenter <namespace> <selector> [container] [command=sh] [command args]... '
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  local _k8s_container="${3:-}"
  local _k8s_ns_cmd="${4:-"sh"}"

  shift 4 2>/dev/null || shift $#
  local _k8s_ns_args=("$@")

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  local _k8s_pod
  _k8s_pod=$($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[0].metadata.name}')
  if [ -z "$_k8s_pod" ]; then
    return 1
  fi
  local _k8s_args=(-it "$_k8s_pod" -n "$_k8s_namespace")
  if [ -n "$_k8s_container" ]; then
    _k8s_args+=(-c "$_k8s_container")
  fi

  if [ "$_k8s_ns_cmd" != 'sh' ]; then
    # shellcheck disable=SC2086    # 不要加引号
    $_k8s_cmd_prefix kubectl exec "${_k8s_args[@]}" -- $_k8s_ns_cmd "${_k8s_ns_args[@]}"
    return $?
  fi

  # 优先使用 /bin/bash
  if $_k8s_cmd_prefix kubectl exec "${_k8s_args[@]}" -- /bin/bash -i 2>/dev/null; then
    return 0
  fi

  # fallback to run /bin/sh
  $_k8s_cmd_prefix kubectl exec "${_k8s_args[@]}" -- /bin/sh -i
}
export k8sNsenter
readonly k8sNsenter

k8sRestart(){
  Usage $# -eq 2 'k8sRestart <namespace> <set, e.g. deployment/redis-deploy, statefulset/mysql-set, daemonset/go-daemon>'
  local _k8s_namespace="$1"
  local _k8s_serv="$2"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  Debug "kubectl rollout restart $_k8s_serv -n $_k8s_namespace"
  $_k8s_cmd_prefix kubectl rollout restart "$_k8s_serv" -n "$_k8s_namespace"
}
export k8sRestart
readonly k8sRestart

