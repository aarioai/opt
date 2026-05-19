#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-probe.sh" ]; then . ./k8s-probe.sh; else . /opt/k8s/lib/k8s-probe.sh; fi

export K8S_SET_YAML
readonly K8S_SET_YAML='set.yaml'

export K8S_UP_YAML
readonly K8S_UP_YAML='k8s.yaml'

k8sPullProbedImages(){
  Usage $# -eq 1 'k8sPullProbedImages <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_image
  while IFS= read -r _k8s_image || [ -n "$_k8s_image" ]; do
    [ -n "$_k8s_image" ] || continue
    Debug "nerdctl pull $_k8s_image"
    $(SUDO) nerdctl pull "$_k8s_image"
  done < <(k8sProbeImages "$_k8s_workdir")
}
export k8sPullProbedImages
readonly k8sPullProbedImages

k8sDownTLS(){
  Usage $# 1 2 'k8sDownTLS <workdir> [-a]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_down_all="${2:-}"

  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")
  if ! k8sValuesExistsTLS "$_k8s_values"; then
    return
  fi

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  local _k8s_tls_cns
  if [ "$_k8s_down_all" = '-a' ]; then
    _k8s_tls_cns=$(echo "$_k8s_values" | yq -r ".${K8S_TLS_TAG}[] | .${K8S_TLS_CN_TAG}")
  else
    _k8s_tls_cns=$(echo "$_k8s_values" | yq -r ".${K8S_TLS_TAG}[] | select(.${K8S_TLS_DOWN_TAG} == true) | .${K8S_TLS_CN_TAG}")
  fi

  while IFS= read -r _k8s_tls_cn || [ -n "$_k8s_tls_cn" ]; do
    [ -z "$_k8s_tls_cn" ] && continue

    local _k8s_secret
    _k8s_secret=$(k8sDefaultTlsSecretName "$_k8s_tls_cn")
    k8sDeleteSecret "$_k8s_namespace" "$_k8s_secret"
  done <<EOF
$_k8s_tls_cns
EOF
}
export k8sDownTLS
readonly k8sDownTLS

k8sUpTLS(){
  Usage $# -eq 1 'k8sUpTLS <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")

  if ! k8sValuesExistsTLS "$_k8s_values"; then
    return 0
  fi

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

    # Get cert
    local _k8s_tls_create_nx
    local _k8s_tls_cert_base
    local _k8s_tls_cert_dir
    local _k8s_tls_expire_days
    local _k8s_tls_cert_file
    local _k8s_tls_key_file
    if YqHas "$K8S_TLS_CERT_TAG" -s "$_k8s_tls"; then
      _k8s_tls_create_nx=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_CREAT_NX_TAG}" -s "$_k8s_tls" true)
      _k8s_tls_cert_base=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_CERT_BASE_TAG}" -s "$_k8s_tls")
      _k8s_tls_cert_dir=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_CERT_DIR_TAG}" -s "$_k8s_tls")
      _k8s_tls_expire_days=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_EXPIRE_DAYS_TAG}" -s "$_k8s_tls" "$CERT_EXPIRE_DAYS")
      _k8s_tls_cert_file=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_CERT_FILE_TAG}" -s "$_k8s_tls" "$CERT_FILE")
      _k8s_tls_key_file=$(YqGet ".${K8S_TLS_CERT_TAG}.${K8S_TLS_CERT_KEY_TAG}" -s "$_k8s_tls" "$CERT_KEY_FILE")
    fi

    if [ -z "$_k8s_tls_cert_dir" ]; then
      _k8s_tls_cert_dir=$(k8sFindCertDir "$_k8s_workdir" "$_k8s_tls_cn" "$_k8s_tls_cert_base" "$_k8s_tls_cert_file")
    fi

    local _k8s_tls_down='false'
    _k8s_tls_down=$(YqGet ".${K8S_TLS_DOWN_TAG}" -s "$_k8s_tls")

    local _k8s_tls_subj='false'
    _k8s_tls_subj=$(YqGet ".${K8S_TLS_SUBJ_TAG}" -s "$_k8s_tls")
    local _k8s_tls_san=''
    _k8s_tls_san=$(YqGet ".${K8S_TLS_SAN_TAG}" -s "$_k8s_tls")

    if [ -z "$_k8s_tls_san" ]; then
      _k8s_tls_hosts=()
      if YqIsNotEmptyArray 'hosts' -s "$_k8s_tls"; then
          while IFS= read -r _k8s_tls_host || [ -n "$_k8s_tls_host" ]; do
            [ -z "$_k8s_tls_host" ] && continue
            _k8s_tls_hosts+=("$_k8s_tls_host")
          done < <(echo "$_k8s_tls" | yq -r '.hosts[]' 2>/dev/null)
      fi
      if [ ${#_k8s_tls_hosts[@]} -eq 0 ]; then
          _k8s_tls_hosts=("$_k8s_tls_cn")
      fi
      _k8s_tls_san=$(FormatSubjectAltName "${_k8s_tls_hosts[@]}")
    fi

    local _k8s_tls_key_path="$_k8s_tls_cert_dir/$_k8s_tls_key_file"
    local _k8s_tls_cert_path="$_k8s_tls_cert_dir/$_k8s_tls_cert_file"

    # Handle cert file
    if [ ! -f "$_k8s_tls_key_path" ] || [ ! -f "$_k8s_tls_cert_path" ]; then
      if ! Yes "$_k8s_tls_create_nx"; then
        ErrorD "missing $_k8s_tls_key_file or $_k8s_tls_cert_file in cert dir $_k8s_tls_cert_dir" \
               "$_k8s_tls_cert_dir 文件夹缺少证书文件${_k8s_tls_key_file}或${_k8s_tls_cert_file}"
        return 1
      fi

      Info "GenerateLeafCert $_k8s_tls_cn $_k8s_tls_cert_dir $_k8s_tls_san $_k8s_tls_subj $_k8s_tls_key_file $_k8s_tls_cert_file $_k8s_tls_expire_days"
      if ! GenerateLeafCert "$_k8s_tls_cn" "$_k8s_tls_cert_dir" "$_k8s_tls_san" "$_k8s_tls_subj" "$_k8s_tls_key_file" "$_k8s_tls_cert_file" "$_k8s_tls_expire_days" >/dev/null 2>&1; then
        ErrorD "create leaf certificate failed" "创建自签名证书失败"
        return 1
      fi
    fi
    k8sCreateTlsSecret "$_k8s_namespace" "$_k8s_secret" "$_k8s_tls_key_path" "$_k8s_tls_cert_path"
  done <<EOF
$_k8s_tls_block
EOF
  return 0
}
export k8sUpTLS
readonly k8sUpTLS

k8sDestroyHere(){
  Usage $# -ge 1 'k8sDestroyHere <workdir> [no_confirmation:|-y]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift
  local _k8s_protect
  _k8s_protect=$(k8sProbeProtectStatus "$_k8s_workdir")

  if Yes "$_k8s_protect"; then
    PanicD "namespace is protected" "namespace 被保护，禁止销毁"
  fi

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  k8sDestroy "$_k8s_namespace" "$@"
}
export k8sDestroyHere
readonly k8sDestroyHere

k8sNsenterHere(){
  Usage $# -ge 1 'k8sNsenterHere <workdir> [command=<.nsenter>] [command args]...'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
  local _k8s_container
  _k8s_container=$(k8sDefaultContainerName "$_k8s_chart_name")

  if [ $# -gt 0 ]; then
    k8sNsenter "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" "${_k8s_nsenter_cmd[@]}"
    return
  fi

  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")
  local _k8s_nsenter_cmd
  _k8s_nsenter_cmd=$(YqGet ".${K8S_NSENTER_CMD_TAG}" -s "$_k8s_values")

  # shellcheck disable=SC2086
  k8sNsenter "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" $_k8s_nsenter_cmd
}
export k8sNsenterHere
readonly k8sNsenterHere

k8sDebugImageHere(){
  Usage $# -ge 2 "k8sDebugImage <workdir> <image> [command...]"
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_image="$2"
  shift 2

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  Info "$*"
  k8sDebugImage "$_k8s_image" "$_k8s_namespace" "$@"
}
export k8sDebugImageHere
readonly k8sDebugImageHere

k8sRestartHere(){
  Usage $# -ge 1 'k8sRestartHere <workdir> [no_confirmation:|-y]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_setname
  _k8s_setname=$(k8sProbeSetName "$_k8s_workdir")

  k8sRestart "$_k8s_namespace" "$_k8s_setname"
}
export k8sRestartHere
readonly k8sRestartHere

k8sProbePvcBytes(){
  Usage $# -eq 1 'k8sProbePvcBytes <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_size
  while IFS= read -r _k8s_size || [[ -n "$_k8s_size" ]]; do
    _k8s_size="${_k8s_size% }"      # trim spaces
    [ -z "$_k8s_size" ] && continue

    local _k8s_size_num
    _k8s_size_num=$(printf '%s' "$_k8s_size" | sed 's/[^0-9.].*$//')
    local _k8s_size_unit
    _k8s_size_unit=$(printf '%s' "$_k8s_size" | sed 's/^[0-9.]*//')

    [ -z "$_k8s_size_num" ] && return 1

    case "$_k8s_size_unit" in
      KI|Ki|ki|k)
        awk "BEGIN{printf \"%.0f\", $_k8s_size_num * 1024}"
        ;;
      MI|Mi|mi|M|m)
         awk "BEGIN{printf \"%.0f\", $_k8s_size_num * 1024 * 1024}"
        ;;
      GI|Gi|gi|G|g)
        awk "BEGIN{printf \"%.0f\", $_k8s_size_num * 1024 * 1024 * 1024}"
        ;;
      TI|Ti|ti|T|t)
        awk "BEGIN{printf \"%.0f\", $_k8s_size_num * 1024 * 1024 * 1024 * 1024}"
        ;;
      *)
        # fallback assume bytes
        awk "BEGIN{printf \"%.0f\", $_k8s_size_num}"
        ;;
    esac
    echo ""
  done < <(k8sProbePvcSizes "$_k8s_workdir" 2>/dev/null)
}
export k8sProbePvcBytes
readonly k8sProbePvcBytes

k8sProbePvcBytesTotal(){
  Usage $# -eq 1 'k8sProbePvcBytes <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_bytes
  local _k8s_total=0
  while IFS= read -r _k8s_bytes || [[ -n "$_k8s_bytes" ]]; do
    [ -z "$_k8s_bytes" ] && continue
    _k8s_total=$(( _k8s_total + _k8s_bytes ))
  done < <(k8sProbePvcBytes "$_k8s_workdir" 2>/dev/null)
  printf '%s' "$_k8s_total"
}
export k8sProbePvcBytesTotal
readonly k8sProbePvcBytesTotal

k8sUp(){
  Usage $# -ge 1 'k8sUp <workdir> [helm args]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  Info "k8s up"

  local _k8s_dry_run=0
  for _k8s_arg in "$@"; do
    if [ "$_k8s_arg" = "--dry-run" ]; then
      _k8s_dry_run=1
      break
    fi
  done

  local _k8s_env
  _k8s_env=$(k8sProbeEnv "$_k8s_workdir")
  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  k8sUpNamespaceNx "$_k8s_workdir"
  k8sProbeConfigMap "$_k8s_workdir"

  if ! Yes "$_k8s_dry_run"; then
    k8sPullProbedImages "$_k8s_workdir"
    # Creating TLS secrets
    if ! k8sUpTLS "$_k8s_workdir"; then
      PanicD "generating TLS secrets failed" "无法创建TLS secrets"
    fi
  fi
  local _k8s_helm_file="${_k8s_workdir}/${K8S_VALUES_YAML_NAME}-${_k8s_env}.yaml"
  if [ ! -f "$_k8s_helm_file" ]; then
    _k8s_helm_file="${_k8s_workdir}/${K8S_VALUES_YAML_NAME}.yaml"
  fi
  PanicIfNotFiles "$_k8s_helm_file"

  # .Release.Name => $_k8s_chart_name
  # .Release.Namespace => $_k8s_namespace
  Debug "helm install $_k8s_chart_name $_k8s_workdir -n $_k8s_namespace -f $_k8s_helm_file $*"
  helm install "$_k8s_chart_name" "$_k8s_workdir" -n "$_k8s_namespace" -f "$_k8s_helm_file" "$@"

  if Yes "$_k8s_dry_run"; then
    return 0
  fi

  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
  local _k8s_container
  _k8s_container=$(k8sDefaultContainerName "$_k8s_chart_name")

  local _k8s_pvc_total_bytes
  _k8s_pvc_total_bytes=$(k8sProbePvcBytesTotal "$_k8s_workdir")

  local _k8s_pvcs
  _k8s_pvcs=$(k8sProbePVCs "$_k8s_workdir")

  k8sWaitReady "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" "$_k8s_pvc_total_bytes" "${_k8s_pvcs[@]}"

  k8sClearWorkDir "$_k8s_workdir"
}
export k8sUp
readonly k8sUp

k8sDown(){
  Usage $# 1 2 'k8sDown <workdir> [-a|pvc|tls]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  Info "k8s down"

  local _k8s_down_pvc=''
  local _k8s_down_tls=''
  for _k8s_down_arg in "$@"; do
    case "$_k8s_down_arg" in
      -a|all) _k8s_down_pvc='1'; _k8s_down_tls='-a' ;;
      pvc) _k8s_down_pvc='1' ;;
      tls) _k8s_down_tls='-a' ;;
    esac
  done

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  k8sProbeConfigMap "$_k8s_workdir"

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  Debug "helm uninstall $_k8s_chart_name -n $_k8s_namespace"
  helm uninstall "$_k8s_chart_name" -n "$_k8s_namespace" 2>/dev/null || true

  k8sClearWorkDir "$_k8s_workdir"

  k8sDownTLS "$_k8s_workdir" $_k8s_down_tls

  local _k8s_setname
  _k8s_setname=$(k8sProbeSetName "$_k8s_workdir")
  local _k8s_sn0="${_k8s_setname%%/*}"
  local _k8s_sn1="${_k8s_setname#*/}"

  Debug "kubectl delete $_k8s_sn0 $_k8s_sn1 -n $_k8s_namespace"
  $_k8s_cmd_prefix kubectl delete "$_k8s_sn0" "$_k8s_sn1" -n "$_k8s_namespace" --ignore-not-found

  local _k8s_has_pvc=0
  if $_k8s_cmd_prefix kubectl get pvc -n "$_k8s_namespace" -l "app=$_k8s_chart_name" --no-headers 2>/dev/null | grep . >/dev/null 2>&1
  then
    _k8s_has_pvc=1
  else
    return 0
  fi

  if [ -z "$_k8s_down_pvc" ]; then
    Notice "$_k8s_chart_name pvc is not deleted"
    return 0
  fi

  Notice "kubectl delete pvc -n $_k8s_namespace -l app=$_k8s_chart_name"
  $_k8s_cmd_prefix kubectl delete pvc -n "$_k8s_namespace" -l "app=$_k8s_chart_name"
}
export k8sDown
readonly k8sDown

k8sUpDown(){
  Usage $# -ge 1 'k8sUpDown <workdir> [helm args]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  k8sDown "$_k8s_workdir"
  k8sUp "$_k8s_workdir" "$@"
}
export k8sUpDown
readonly k8sUpDown

k8sHistory(){
  Usage $# -ge 1 'k8sUpDown <workdir> [helm args]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  Debug "helm history $_k8s_chart_name -n $_k8s_namespace"
  helm history "$_k8s_chart_name" -n "$_k8s_namespace"
}
export k8sHistory
readonly k8sHistory

k8sUpgrade(){
  Usage $# -ge 1 'k8sUpgrade <workdir> [helm args]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  k8sProbeConfigMap "$_k8s_workdir"
  k8sPullProbedImages "$_k8s_workdir"

  local _k8s_helm_file="${_k8s_workdir}/${K8S_VALUES_YAML_NAME}-${_k8s_prefix}.yaml"
  if [ ! -f "$_k8s_helm_file" ]; then
    _k8s_helm_file="${_k8s_workdir}/${K8S_VALUES_YAML_NAME}.yaml"
  fi
  PanicIfNotFiles "$_k8s_helm_file"

  local _k8s_backup_dir="${_k8s_workdir}/${K8S_BACKUP_DIR}"
  local _k8s_backup_file
  _k8s_backup_file="$(date '+%Y%m%d-%H%M%S').tar.gz"
  ChmodOrMkdir 755 "$_k8s_backup_dir"

  Debug "helm get values $_k8s_chart_name -n $_k8s_namespace -o yaml > $_k8s_backup_file"
  helm get values "$_k8s_chart_name" -n "$_k8s_namespace" -o yaml > "$_k8s_backup_file"

  Debug "helm repo update"
  helm repo update

  Debug "helm upgrade $_k8s_chart_name $_k8s_workdir -n $_k8s_namespace -f $_k8s_helm_file --atomic --wait $*"
  helm upgrade "$_k8s_chart_name" "$_k8s_workdir" -n "$_k8s_namespace" -f "$_k8s_helm_file" --atomic --wait "$@"

  Debug "helm status $_k8s_chart_name -n $_k8s_namespace"
  helm status "$_k8s_chart_name" -n "$_k8s_namespace"

}
export k8sUpgrade
readonly k8sUpgrade