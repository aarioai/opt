#!/bin/bash
set -euo pipefail

# Require: nerdctl + helm

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-yq.sh" ]; then . ../../aa/lib/aa-posix-yq.sh; else . /opt/aa/lib/aa-posix-yq.sh; fi

export K8S_DEBUG_POD
readonly K8S_DEBUG_POD='aa-debug-pod'

export K8S_INCLUDE_PREFIX
readonly K8S_INCLUDE_PREFIX='@include/'

export K8S_GENERATED_PREFIX
readonly K8S_GENERATED_PREFIX='generated---'      # Do not start with _ or ., otherwise may ignored by helm

export K8S_GITIGNORE_GENERATED_FILE
readonly K8S_GITIGNORE_GENERATED_FILE="**/templates/${K8S_GENERATED_PREFIX}*.yaml"

export K8S_BACKUP_DIR
readonly K8S_BACKUP_DIR='backup'

export K8S_CHART_YAML='Chart.yaml'
readonly K8S_CHART_YAML

export K8S_VALUES_YAML_NAME='values'   # values.yaml / values-<env>.yaml
readonly K8S_VALUES_YAML_NAME

export K8S_ENV_YAML
readonly K8S_ENV_YAML='._env.yaml'

export K8S_HELPER_TPL
readonly K8S_HELPER_TPL='templates/_helpers.tpl'

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

k8sDefaultTlsSecretName(){
  Usage $# -eq 1 'k8sDefaultTlsSecretName <common_name>'
  PanicIfEmpty "$1" 'common_name'
  printf 'tls-%s' "$1"
}
export k8sDefaultTlsSecretName
readonly k8sDefaultTlsSecretName

k8sKubectlPrefix(){
  local _k8s_cmd_prefix
  _k8s_cmd_prefix="$(SUDO)"
  if command -v k3s >/dev/null 2>&1; then
    _k8s_cmd_prefix="$_k8s_cmd_prefix k3s"
  fi
  printf '%s' "$_k8s_cmd_prefix"
}
export k8sKubectlPrefix
readonly k8sKubectlPrefix

k8sJournalCtrlError(){
  Usage $# 0 2 'k8sJournalCtrlError [namespace] [pod_name|service_name|name]'
  local _k8s_namespace="${1:-}"
  local _k8s_name="${2:-}"

  local _k8s_cmd_tip=''
  local _k8s_cmd=''
  if command -v k3s >/dev/null 2>&1; then
    _k8s_cmd_tip='journalctl -u k3s'
    _k8s_cmd="$(SUDO) journalctl -u k3s"
  fi

  if [ -z "$_k8s_namespace" ] && [ -z "$_k8s_name" ]; then
    Debug "$_k8s_cmd_tip | grep -i 'error' | tail -10"
    $_k8s_cmd | grep -i 'error' | tail -10
    return
  fi

  if [ -n "$_k8s_namespace" ] && [ -n "$_k8s_name" ]; then
    Debug "$_k8s_cmd_tip | grep -i 'error' | grep '$_k8s_namespace' | grep '$$_k8s_name' | tail -10"
    $_k8s_cmd | grep -i 'error' | grep "$_k8s_namespace" | grep "$_k8s_name"  | tail -10
    return
  fi

  local _k8s_pattern="$_k8s_namespace"
  if [ -z "$_k8s_pattern" ]; then
    _k8s_pattern="$_k8s_name"
  fi
  Debug "$_k8s_cmd_tip | grep -i 'error' | grep '$_k8s_pattern'| tail -10"
  $_k8s_cmd | grep -i 'error' | grep "$_k8s_pattern" | tail -10
  return
}
export k8sJournalCtrlError
readonly k8sJournalCtrlError

k8sRmiNoneImages(){
  Debug "nerdctl image prune -f $*"
  $(SUDO) nerdctl image prune -f "$@"
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages

k8sPS2(){
  printf "${_GREEN_}%s%s%s%s%s%s${_NC_}\n" "$(StrPad "CONTAINER_ID" 14)" "$(StrPad "NAME" 18)" "$(StrPad "STATUS" 9)" "$(StrPad "CREATED_AT" 13)" "$(StrPad "PORTS" 20)"  "NAMES"
  $(SUDO) nerdctl ps -a --format '{{json .}}' | while IFS= read -r _k8s_line; do
    local _k8s_c_id
    _k8s_c_id=$(echo "$_k8s_line" | jq -r '.ID')

    local _k8s_created_at
    _k8s_created_at=$(date -d "$(echo "$_k8s_line" | jq -r '.CreatedAt')" '+%m-%d %H:%M')
    local _k8s_names
    _k8s_names=$(echo "$_k8s_line" | jq -r '.Names')
    local _k8s_clean_names="${_k8s_names#k8s://}"
    _k8s_namespace=$(echo "$_k8s_clean_names" | cut -d/ -f1)
    _k8s_pod=$(echo "$_k8s_clean_names" | cut -d/ -f2)

    local _k8s_name="${_k8s_clean_names##*/}"
    case "$_k8s_name" in
      aa-*) ;;
      *) continue;;
    esac

    printf "${_BLUE_}%s${_NC_}%s%s" "$(StrFix "$_k8s_c_id" 14)" "$(StrFix "$_k8s_name" 18)"

    local _k8s_c_status
    _k8s_c_status=$(echo "$_k8s_line" | jq -r '.Status')
    local _k8s_c_sts
    _k8s_c_sts="$(StrPad "$_k8s_c_status" 9)"

    case "$_k8s_c_status" in
      Created) printf "${_MAGENTA_}%s${_NC_}" "$_k8s_c_sts" ;;     # created but not running
      Existed*) printf "${_RED_}%s${_NC_}" "$_k8s_c_sts" ;;    # Exited (0)  normal exited;   Exited (1) abnormal exited;
      Restarting) printf "${_CYAN_}%s${_NC_}" "$_k8s_c_sts" ;;
      Paused) printf "${_BLUE_}%s${_NC_}" "$_k8s_c_sts"  ;;
      *) printf '%s' "$_k8s_c_sts" ;;     # Up = running
    esac

    local _k8s_ports
    _k8s_ports=$(printf "%s" "$(
      kubectl get pod "$_k8s_pod" -n "$_k8s_namespace" -o json \
      | jq -r '
          .spec.containers[]
          | .ports // []
          | map(
              if (.protocol // "TCP") == "TCP" then
                ":\(.containerPort)"
              else
                ":\(.containerPort)/\(.protocol)"
              end
            )
          | join(",")
        '
    )")

    printf "${_GRAY_}%s${_YELLOW_}%s${_GRAY_}%s${_NC_}\n" "$(StrPad "$_k8s_created_at" 13)" "$(StrFix "$_k8s_ports" 20)" "$_k8s_names"
done
}

k8sPvcStatus(){
  Usage $# -eq 2 'k8sPvcStatus <namespace> <pvc name>'
  local _k8s_namespace="$1"
  local _k8s_pvc="$2"

  local _k8s_i=0
  for _k8s_i in {1..12}; do
    local PVC_STATUS
    PVC_STATUS=$($(k8sKubectlPrefix) kubectl get pvc "$_k8s_pvc" -n "$_k8s_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true || echo "Pending")
    if [ "$PVC_STATUS" = "Bound" ]; then
      return 0
    fi
    Debug "kubectl get pvc $_k8s_pvc -n $_k8s_namespace -o jsonpath='{.status.phase}' ($_k8s_i/12)"
    sleep 5
  done

  $_k8s_cmd_prefix kubectl describe pvc "$_k8s_pvc" -n "$_k8s_namespace"
  return 1
}
export k8sPvcStatus
readonly k8sPvcStatus

k8sStatus(){
  Usage $# -ge 2 'k8sStatus <namespace> <selector> [pvcs]...'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  shift 2

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  Heading "[SERVICE] kubectl get service -n $_k8s_namespace -l $_k8s_selector -o wide"
  $_k8s_cmd_prefix kubectl get service -n "$_k8s_namespace" -l "$_k8s_selector" -o wide

  Heading "[POD] kubectl get pods -n $_k8s_namespace -l $_k8s_selector"
  $_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector"

  local _k8s_pods=()
  for _k8s_pod in $($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
    [ -n "$_k8s_pod" ] || continue
    _k8s_pods+=("$_k8s_pod")
  done

  for _k8s_pvc in "$@"; do
    [ -n "$_k8s_pvc" ] || continue
    for _k8s_pod in $($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
      [[ $_k8s_pod =~ -[0-9]+$ ]] || continue
      # Show PVC
      local _k8s_pvc_full="${_k8s_pvc}-${_k8s_pod}"
      if ! k8sPvcStatus "$_k8s_namespace" "$_k8s_pvc_full"; then
        HeadingD "[PVC] $_k8s_pvc_full bind failed" "[PVC] $_k8s_pvc_full 绑定失败"
      else
        local _k8s_pvc_size
        _k8s_pvc_size=$($_k8s_cmd_prefix kubectl get pvc "$_k8s_pvc_full" -n "$_k8s_namespace" -o jsonpath='{.status.capacity.storage}')
        Heading "[PVC] $_k8s_pvc_full ($_k8s_pvc_size)"
      fi
    done
  done

  Heading "[CONTAINER] crictl ps -a --pod <POD ID>  --namespace $_k8s_namespace"
  $_k8s_cmd_prefix crictl ps -a --pod ONLY_HEADER --namespace dev-state
  for _k8s_pod in "${_k8s_pods[@]}"; do
    $_k8s_cmd_prefix crictl pods --name "$_k8s_pod" --namespace "$_k8s_namespace" -q | while IFS= read -r _k8s_pod_id || [[ -n "$_k8s_pod_id" ]]; do
      $_k8s_cmd_prefix crictl ps -a --pod "$_k8s_pod_id" --namespace "$_k8s_namespace"  | while IFS= read -r _k8s_ps || [[ -n "$_k8s_ps" ]]; do
        case "$_k8s_ps" in
          CONTAINER*) continue ;;
          *) echo "$_k8s_ps" ;;
        esac
      done
    done
  done

  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")
  if YqHas ".${K8S_TLS_TAG}" -s "$_k8s_values"; then
    k8sTlsSecrets "$_k8s_workdir" "$_k8s_namespace" "$_k8s_values" "$@"
  fi

  # Show CPU and memory usage
  local _k8s_top_header=0
  local _k8s_pod_status
  local _k8s_pod_reason
  local _k8s_i=0
  for _k8s_pod in "${_k8s_pods[@]}"; do
    _k8s_pod_status=$($_k8s_cmd_prefix kubectl get pod "$_k8s_pod" -n "$_k8s_namespace" -o jsonpath='{.status.phase}')
    case "$_k8s_pod_status" in
      Pending|Failed|Completed|Unknown|Succeeded)
        continue
        ;;
    esac

    # Ignore crashed pod
    _k8s_pod_reason=$(
      $_k8s_cmd_prefix kubectl get pod "$_k8s_pod" \
        -n "$_k8s_namespace" \
        -o json \
      | jq -r '
          [
            .status.containerStatuses[]?
            | (
                .state.waiting.reason //
                .state.terminated.reason //
                ""
              )
          ]
          | join(",")
        ' 2>/dev/null
    )
     # Ignore unhealthy pods
    case "$_k8s_pod_status,$_k8s_pod_reason" in
      Failed,*|\
      Unknown,*|\
      Succeeded,*|\
      *,CrashLoopBackOff*|\
      *,ImagePullBackOff*|\
      *,ErrImagePull*|\
      *,CreateContainerConfigError*|\
      *,CreateContainerError*|\
      *,RunContainerError*|\
      *,ContainerCannotRun*|\
      *,Error*|\
      *,Exited*|\
      *,OOMKilled*)
        continue
      ;;
    esac
    for _k8s_i in {1..12}; do
      if $_k8s_cmd_prefix kubectl top pod "$_k8s_pod" -n "$_k8s_namespace" >/dev/null 2>&1; then
        break
      fi

      _k8s_pod_status=$($_k8s_cmd_prefix kubectl get pod "$_k8s_pod" -n "$_k8s_namespace" -o jsonpath='{.status.phase}')
      case "$_k8s_pod_status" in
        Pending|Failed|Completed|Unknown|Succeeded)
          Info "pod $_k8s_pod is $_k8s_pod_status"
          return 0
          ;;
      esac

      Debug "waiting top metrics of pod $_k8s_pod -n $_k8s_namespace (status: $_k8s_pod_status)"
      sleep 5
    done
    if [ "$_k8s_top_header" -eq 0 ]; then
      _k8s_top_header=1
      Heading "[NAME  CPU(cores)  MEMORY(bytes)] kubectl top pod <POD NAME> -n $_k8s_namespace"
    fi
    $_k8s_cmd_prefix kubectl top pod "$_k8s_pod" -n "$_k8s_namespace" | while IFS= read -r _k8s_top || [[ -n "$_k8s_top" ]]; do
      case "$_k8s_top" in
        NAME*);;
        *) echo "$_k8s_top" ;;
      esac
    done
  done
}
export k8sStatus
readonly k8sStatus

k8sWaitReady(){
  Usage $# -ge 2 'k8sWaitReady <namespace> <selector> [pvc_total_bytes=0] [pvcs]...'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"
  local _k8s_pvc_total_bytes="${3:-0}"
  shift 3 2>/dev/null || shift $#

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if [ -n "$_k8s_pvc_total_bytes" ] && [ "$_k8s_pvc_total_bytes" -gt 0 ]; then
    Info "allocating $# PVC (total: $(BytesToIEC "$_k8s_pvc_total_bytes")): $*"
  fi

  while ! kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" --no-headers 2>/dev/null | grep -q .; do
    Debug "Waiting for pod to be created..."
    sleep 2
  done

  local _k8s_pvc_bind_fail=0
  for _k8s_pvc in "$@"; do
    [ -n "$_k8s_pvc" ] || continue
    for _k8s_pod in $($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
      [ -n "$_k8s_pod" ] || continue
      _k8s_pods+=("$_k8s_pod")
      [[ $_k8s_pod =~ -[0-9]+$ ]] || continue
      local _k8s_pvc_full="${_k8s_pvc}-${_k8s_pod}"
      if ! k8sPvcStatus "$_k8s_namespace" "$_k8s_pvc_full"; then
        _k8s_pvc_bind_fail=1
      fi
    done
  done

  local _k8s_wait_timeout=15
  if [ "$_k8s_pvc_bind_fail" -eq 1 ]; then
    local _k8s_pvc_total_gi=$(( (_k8s_pvc_total_bytes + 1073741823) / 1073741824 ))
    if [ "$_k8s_pvc_total_gi" -le 1 ]; then
      _k8s_wait_timeout=30
    elif [ "$_k8s_pvc_total_gi" -le 10 ]; then
      _k8s_wait_timeout=60
    elif [ "$_k8s_pvc_total_gi" -le 40 ]; then
      _k8s_wait_timeout=120
    elif [ "$_k8s_pvc_total_gi" -le 80 ]; then
      _k8s_wait_timeout=180
    elif [ "$_k8s_pvc_total_gi" -le 200 ]; then
      _k8s_wait_timeout=240
    elif [ "$_k8s_pvc_total_gi" -le 500 ]; then
      _k8s_wait_timeout=300
    elif [ "$_k8s_pvc_total_gi" -le 1000 ]; then
      _k8s_wait_timeout=600
    else
      _k8s_wait_timeout=1080
    fi
  fi

  Debug "kubectl wait --for=condition=Ready pods -n $_k8s_namespace -l $_k8s_selector --timeout=${_k8s_wait_timeout}s"
  if ! $_k8s_cmd_prefix kubectl wait \
    --for=condition=Ready pods \
    -n "$_k8s_namespace" \
    -l "$_k8s_selector" \
    --timeout="${_k8s_wait_timeout}s" 2>/dev/null; then
    k8sLogs "$_k8s_namespace" "$_k8s_selector"
    return 1
  fi

  k8sStatus "$_k8s_namespace" "$_k8s_selector" "$@"
}
export k8sWaitReady
readonly k8sWaitReady

k8sExistsNamespaces(){
  Usage $# -ge 1 'k8sExistsNamespaces <namespace> [namespace]...'
  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  local _k8s_namespace
  for _k8s_namespace in "$@"; do
    if ! $_k8s_cmd_prefix kubectl get ns "$_k8s_namespace" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}
export k8sNamespaceExists
readonly k8sNamespaceExists

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

  if k8sExistsNamespaces "$_k8s_namespace"; then
    Warn "kubectl delete namespace $_k8s_namespace"
    $_k8s_cmd_prefix kubectl delete namespace "$_k8s_namespace"  -v=6
  fi

  k8sPS2
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

  InfoD "Creating TLS secret..." "创建 TLS secret中..."
  Debug "kubectl create secret tls $_k8s_service -n $_k8s_namespace --key=$_k8s_privkey --cert=$_k8s_cert"
  if ! $_k8s_cmd_prefix kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --key="$_k8s_privkey" --cert="$_k8s_cert" >/dev/null; then
    PanicD "create tls secret failed" "创建 TLS secret失败"
  fi

  InfoD "Verifying TLS secret..." "验证 TLS secret中..."
  Debug "kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! $_k8s_cmd_prefix kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify kubectl secret failed" "验证 kubectl secret 失败"
  fi

  return 0
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
  while IFS= read -r _k8s_tls_b64 || [ -n "$_k8s_tls_b64" ]; do
    [ -z "$_k8s_tls_b64" ] && continue
    local _k8s_tls
    _k8s_tls=$(echo "$_k8s_tls_b64" | base64 -d)
    local _k8s_tls_cn
    _k8s_tls_cn=$(YqGet ".${K8S_TLS_CN_TAG}" -s  "$_k8s_tls" WITH_PANIC)
    local _k8s_secret
    _k8s_secret=$(k8sDefaultTlsSecretName "$_k8s_tls_cn")
    Heading "[SECRET]: $_k8s_secret"

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
      MkdirsOrSudo "$_k8s_tls_cert_dir" >/dev/null 2>&1 || true
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
    MkdirsOrSudo "$_k8s_tls_cert_dir" >/dev/null 2>&1 || true
    printf '%s' "$_k8s_tls_cert_dir"
}
export k8sFindCertDir
readonly k8sFindCertDir

k8sPodContainerLogs(){
  Usage $# -eq 2 'k8sPodContainerLogs <namespace> <pod>'
  local _k8s_namespace="$1"
  local _k8s_pod="$2"
  local _k8s_pod_id
  local _k8s_container_id
  local _k8s_logs
  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)
  $_k8s_cmd_prefix crictl pods --name "$_k8s_pod" --namespace "$_k8s_namespace" -q | while IFS= read -r _k8s_pod_id || [[ -n "$_k8s_pod_id" ]]; do
    $_k8s_cmd_prefix crictl ps -a --pod "$_k8s_pod_id" -q  | while IFS= read -r _k8s_container_id || [[ -n "$_k8s_container_id" ]]; do
      Debug "crictl logs $_k8s_container_id"
      _k8s_logs=$($_k8s_cmd_prefix crictl logs "$_k8s_container_id" 2>/dev/null)
      if [ -n "$_k8s_logs" ]; then
        echo "$_k8s_logs"
      fi
    done
  done
}
export k8sPodContainerLogs
readonly k8sPodContainerLogs

k8sLogs(){
  Usage $# 2 3 'k8sLogs <namespace> <selector> [<container_id>|pod|-j]'
  local _k8s_namespace="$1"
  local _k8s_selector="$2"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if [ $# -gt 2 ] && [ -n "$3" ]; then
    case "$3" in
      -j)
        k8sJournalCtrlError "$_k8s_namespace"
        ;;
      pod)
        Debug "kubectl describe pod -n $_k8s_namespace -l $_k8s_selector"
        $_k8s_cmd_prefix kubectl describe pod -n "$_k8s_namespace" -l "$_k8s_selector"
        return
        ;;
      *)
        local _k8s_id="$3"
        Debug "crictl logs $_k8s_id"  # container id
        $_k8s_cmd_prefix crictl logs "$_k8s_id"   # 失败容器重启，名称会变
        return
        ;;
    esac
  fi

  local _k8s_err
  _k8s_err=$($_k8s_cmd_prefix kubectl logs -n "$_k8s_namespace" -l "$_k8s_selector" 2>&1)
  case "$_k8s_err" in
    *"net/http: TLS handshake timeout") ;;
    *"No resources found in $_k8s_namespace namespace."*) return 0;;
    *)
       Debug "kubectl logs -n $_k8s_namespace -l $_k8s_selector"
       $_k8s_cmd_prefix kubectl logs -n "$_k8s_namespace" -l "$_k8s_selector"
       return 0
      ;;
  esac

  local no_pod=1
  for _k8s_pod in $($_k8s_cmd_prefix kubectl get pods -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
    [ -n "$_k8s_pod" ] || continue
    no_pod=0
    k8sPodContainerLogs "$_k8s_namespace" "$_k8s_pod"

    _k8s_error="$($_k8s_cmd_prefix kubectl describe pod "$_k8s_pod" -n "$_k8s_namespace" | grep -Ei "Error|Failed|Warning" )"
    if [ -n "$_k8s_error" ]; then Debug "kubectl describe pod $_k8s_pod -n $_k8s_namespace${LF}"; Panic "${_k8s_error}"; fi
  done

  if [ "$no_pod" -eq 0 ]; then
    Debug "try: kubectl describe pod -n $_k8s_namespace -l $_k8s_selector"
    k8sJournalCtrlError "$_k8s_namespace"
    return 1
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
    return
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

k8sAddYamlToGitIgnore(){
  Usage $# -eq 1 'k8sAddYamlToGitIgnore <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_gitignore=""
  local _k8s_current_dir="$_k8s_workdir"
  while [ "$_k8s_current_dir" != "/" ]; do
    if [ -f "${_k8s_current_dir}/.gitignore" ]; then
      _k8s_gitignore="${_k8s_current_dir}/.gitignore"
      break
    fi
    _k8s_current_dir="$(dirname "$_k8s_current_dir")"
  done

  if [ -z "$_k8s_gitignore" ]; then
    # fallback: create a .gitignore
    Notice "creating $K8S_GITIGNORE_GENERATED_FILE ==> $_k8s_gitignore"
    WriteFileOrPanic "$K8S_GITIGNORE_GENERATED_FILE" '->' "$_k8s_gitignore"
    ChmodOrSudo 644 "$_k8s_gitignore" || true
    return
  fi

  if grep -Fqx "$K8S_GITIGNORE_GENERATED_FILE" "$_k8s_gitignore"; then
    return 0
  fi

  Info "appending ${K8S_GITIGNORE_GENERATED_FILE} ==> $_k8s_gitignore"
  PrependToFileOrSudo "$_k8s_gitignore" "${K8S_GITIGNORE_GENERATED_FILE}${LF}"
}
export k8sAddYamlToGitIgnore
readonly k8sAddYamlToGitIgnore

k8sDebugImage(){
  Usage $# -ge 2 "k8sDebugImage <image> <namespace> [command=/bin/sh] [command_args...]"
  local _k8s_image="$1"
  local _k8s_namespace="$2"
  local _k8s_command="${3:-"/bin/sh"}"
  shift 3 2>/dev/null || shift $#

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if ! k8sExistsNamespaces "$_k8s_namespace"; then
    Warn "namespace $_k8s_namespace is not exists. use default"
    _k8s_namespace="default"
  fi

  Debug "kubectl delete pod $K8S_DEBUG_POD -n $_k8s_namespace --ignore-not-found"
  $_k8s_cmd_prefix kubectl delete pod "$K8S_DEBUG_POD" -n "$_k8s_namespace" --ignore-not-found >/dev/null 2>&1

  InfoD "interactive terminal mode requires manual execution, please copy and run the command below" \
    "交互行为不可通过脚本发起，因此需要手动复制下面命令去运行"

  Highlight "kubectl run $K8S_DEBUG_POD -n $_k8s_namespace -it --rm --restart=Never --image-pull-policy=IfNotPresent --image=$_k8s_image -- $_k8s_command $*"
}
export k8sDebugImage
readonly k8sDebugImage

k8sDownJobs(){
  Usage $# -eq 2 'k8sDownJobs <namespace> <selector>'
  _k8s_namespace="$1"
  _k8s_selector="$2"

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  for _k8s_job in $($_k8s_cmd_prefix kubectl get jobs -n "$_k8s_namespace" -l "$_k8s_selector" -o jsonpath='{.items[*].metadata.name}'); do
    Debug "kubectl delete job $_k8s_job -n $_k8s_namespace"
    $_k8s_cmd_prefix kubectl delete job "$_k8s_job" -n "$_k8s_namespace"
  done
}
export k8sDownJobs
readonly k8sDownJobs