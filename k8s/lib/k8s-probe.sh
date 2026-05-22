#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-template.sh" ]; then . ./k8s-template.sh; else . /opt/k8s/lib/k8s-template.sh; fi
readonly k8s_probe_help="
k8s probe <CMD> [.]
  -h|-help|help     Show help
  cname|container   Show container name
  configmap         Show configmaps
  cpu|memory|top    Show CPU/memory usage
  debug|dry|dry-run Dry run 'k8s up', i.e. show all rendered yaml configurations
  desc|describe     kubectl describe pods <pod> -n <namespace>
    [pod]
  env               Get .env in $K8S_ENV_YAML
    [-v]              Cat $K8S_ENV_YAML
  global            Render $K8S_GLOBAL_YAML
  images            List all images by .Values.image or .Values.images
  logs              Show logs of current service
  name              Show .Chart.name
  n|namespace       Show current namespace (by $K8S_GLOBAL_YAML)
  protect           Show namespace protect status, i.e. Namespace .metadata.labels.protect in $K8S_GLOBAL_YAML
  pvc               Show PVCs
  pvc-size|pvc-sizes  Show PVC sizes
    [name]          Show the specific PVC size
  pvc-byte|pvc-bytes) Show PVC sizes in bytes
  pvc-total         Count all pvc sizes in bytes
  selector          Show .Values.selector or app=<.Chart.Name>
  setname           Show deployment/statefulset/deamonset's name
  status            Show status of current pods, services, and PVCs
  tls               Show TLS secrets of current service
    json              Show in JSON format
  values            Render ${K8S_VALUES_YAML_NAME}-<env>.yaml
"


k8sProbeGlobalYaml(){
  Usage $# 1 2 'k8sProbeGlobalYaml <workdir> [WITH_PANIC]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_panic="${2:-}"

  local _k8s_global_dir
  local _k8s_global_yaml
  for _k8s_global_dir in "$_k8s_workdir" "$_k8s_workdir/.." "$_k8s_workdir/../.."; do
    _k8s_global_yaml=$(realpath "$_k8s_global_dir/$K8S_GLOBAL_YAML")
    if [ -f "$_k8s_global_yaml" ]; then
      printf '%s' "$_k8s_global_yaml"
      return 0
    fi
  done
  if [ "$_k8s_with_panic" = WITH_PANIC ]; then
    PanicD "missing $K8S_GLOBAL_YAML" "缺少 $K8S_GLOBAL_YAML"
  fi
}
export k8sProbeGlobalYaml
readonly k8sProbeGlobalYaml

k8sProbeGlobal(){
  Usage $# -eq 1 'k8sProbeGlobal <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_global_yaml
  _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_workdir" WITH_PANIC)
  Lowlight "# $_k8s_global_yaml"
  k8sRenderTemplate "$_k8s_workdir" "$(cat "$_k8s_global_yaml")"
  echo ''
}
export k8sProbeGlobal
readonly k8sProbeGlobal

k8sProbeConfigMap(){
  Usage $# 1 2 'k8sProbeConfigMap <workdir> [cat_then_delete=|-d]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_cat_then_delete="${2:-}"

  local _k8s_env
  _k8s_env=$(k8sProbeEnv "$_k8s_workdir")

  # Try configmap-<env>
  local _k8s_configmap_dir="${_k8s_workdir}/configmap-${_k8s_env}"
  if [ ! -d "$_k8s_configmap_dir" ]; then
    # Fallback to configmap
    _k8s_configmap_dir="${_k8s_workdir}/configmap"
  fi

  if [ ! -d "$_k8s_configmap_dir" ]; then
    return
  fi

  local _k8s_templates_dir="${_k8s_workdir}/templates"
  local _k8s_cfg

  k8sAddYamlToGitIgnore "$_k8s_workdir"
  k8sClearWorkDir "$_k8s_workdir"

  for _k8s_cfg in "$_k8s_configmap_dir"/*.yaml; do
    [ -f "$_k8s_cfg" ] || continue
    # shellcheck disable=SC2086
    k8sRenderConfigmap "$_k8s_workdir" "$_k8s_env" "$_k8s_cfg" "$_k8s_templates_dir" $_k8s_cat_then_delete
  done
}
export k8sProbeConfigMap
readonly k8sProbeConfigMap

k8sProbeImages(){
  Usage $# -eq 1 'k8sProbeDryRun <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_values
  _k8s_values="$(k8sProbeValues "$_k8s_workdir")"


  local _k8s_image
  if echo "$_k8s_values" | yq 'has("images")' | grep -q true; then
    yq -e '.images[]' <<< "$_k8s_values"
  fi
  YqGet ".image" -s "$_k8s_values"
}
export k8sProbeImages
readonly k8sProbeImages

k8sProbeDryRun(){
  Usage $# -eq 1 'k8sProbeDryRun <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  k8sUp "$_k8s_workdir" --dry-run=client
}
export k8sProbeImages
readonly k8sProbeImages

k8sProbeStatus(){
  Usage $# -eq 1 'k8sProbeStatus <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
  local _k8s_pvcs
  _k8s_pvcs=$(k8sProbePVCs "$_k8s_workdir")

  k8sStatus "$_k8s_namespace" "$_k8s_selector" "${_k8s_pvcs[@]}"
}
export k8sProbeStatus
readonly k8sProbeStatus

k8sProbeTLS(){
  Usage $# -ge 1 'k8sProbeTLS <workdir> [format=|json]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")

  if ! YqHas ".${K8S_TLS_TAG}" -s "$_k8s_values"; then
    return
  fi

  GrayLine '='
  YqGet ".${K8S_TLS_TAG}" -s "$_k8s_values"
  GrayLine '='

  k8sTlsSecrets "$_k8s_workdir" "$_k8s_namespace" "$_k8s_values" "$@"
}
export k8sProbeTLS
readonly k8sProbeTLS

k8sProbeLogs(){
  Usage $# -ge 1 'k8sProbeLogs <workdir> [container|pod]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir")
  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")

  k8sLogs "$_k8s_namespace" "$_k8s_selector" "$@"
}
export k8sProbeLogs
readonly k8sProbeLogs

k8sProbePVCs(){
  Usage $# -ge 1 'k8sProbeLogs <workdir> [container|pod]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_set_yaml="${_k8s_workdir}/${K8S_SET_YAML_REL}"
  if [ ! -f "$_k8s_set_yaml" ]; then
    return
  fi

  local _k8s_pvcs

  while IFS= read -r _k8s_pvc || [[ -n "$_k8s_pvc" ]]; do
    [ -z "$_k8s_pvc" ] && continue
    k8sRenderTemplate "$_k8s_workdir" "$_k8s_pvc"
  done < <(yq eval '.spec.volumeClaimTemplates[].metadata.name' "$_k8s_set_yaml")
}
export k8sProbePVCs
readonly k8sProbePVCs

k8sProbePvcSizes(){
  Usage $# -eq 1 'k8sProbePvcSizes <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_set_yaml="${_k8s_workdir}/${K8S_SET_YAML_REL}"
  PanicIfNotFiles "$_k8s_set_yaml"

  local _k8s_pvcs

  while IFS= read -r _k8s_pvc || [[ -n "$_k8s_pvc" ]]; do
    [ -z "$_k8s_pvc" ] && continue
    k8sRenderTemplate "$_k8s_workdir" "$_k8s_pvc"
    echo ""
  done < <(yq eval '.spec.volumeClaimTemplates[0].spec.resources.requests.storage' "$_k8s_set_yaml")
}
export k8sProbePvcSize
readonly k8sProbePvcSize

k8sProbeSelector(){
  Usage $# -eq 1 'k8sProbeSelector <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")

  local _k8s_helper_tpl="${_k8s_workdir}/${K8S_HELPER_TPL}"

  local _k8s_selector
  _k8s_selector=$(sed -n '/{{-*[[:space:]]*define "helpers.selector"/,/{{-*[[:space:]]*end/{
    /{{-*[[:space:]]*define/d
    /{{-*[[:space:]]*end/d
    p
  }' "$_k8s_helper_tpl")

  k8sRenderTemplate "$_k8s_workdir" "$_k8s_selector"  | yq eval 'to_entries | map(.key + "=" + (.value | tostring)) | join(",")' -
}
export k8sProbeSelector
readonly k8sProbeSelector

k8sProbeCpuUsage(){
  Usage $# -ge 1 'k8sProbeCpuUsage <workdir> [--sort-by=cpu|memory]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  $(k8sKubectlPrefix) kubectl top pod -n "$_k8s_namespace" "$@"
}
export k8sProbeCpuUsage
readonly k8sProbeCpuUsage

k8sProbePods(){
  Usage $# -ge 1 'k8sProbePods <workdir> [--args]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  $(k8sKubectlPrefix) kubectl get pods -n "$_k8s_namespace" "$@"
}

k8sProbeDescribePod(){
  Usage $# -ge 1 'k8sProbeDescribePod <workdir> [pod name]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_pod="${2:-}"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if [ -z "$_k8s_pod" ]; then
    local _k8s_selector
    _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
    Debug "kubectl describe pods -n $_k8s_namespace -l $_k8s_selector"
    $_k8s_cmd_prefix kubectl describe pods -n "$_k8s_namespace" -l "$_k8s_selector"
    return
  fi

  Debug "kubectl describe pod $_k8s_pod -n $_k8s_namespace "
  $_k8s_cmd_prefix kubectl describe pod "$_k8s_pod" -n "$_k8s_namespace"
}

k8sProbe(){
  local _k8s_workdir
  _k8s_workdir=$(k8sWorkDir)
  local _k8s_what="${1:-}"
  shift
  case "$_k8s_what" in
    cname|container) k8sProbeContainerName "$_k8s_workdir" ;;
    configmap) k8sProbeConfigMap "$_k8s_workdir" -d ;;
    cpu|memory|top) k8sProbeCpuUsage "$_k8s_workdir" "$@";;
    debug|dry|dry-run) k8sProbeDryRun "$_k8s_workdir" ;;
    desc|describe) k8sProbeDescribePod "$_k8s_workdir" "$@";;
    env) k8sProbeEnv "$_k8s_workdir" "$@";;
    global) k8sProbeGlobal "$_k8s_workdir" ;;
    images) k8sProbeImages "$_k8s_workdir" ;;
    logs) k8sProbeLogs "$_k8s_workdir" ;;
    name) k8sProbeName "$_k8s_workdir" ;;
    n|ns|namespace) k8sProbeNamespace "$_k8s_workdir" ;;
    pod|pods) k8sProbePods "$_k8s_workdir" "$@" ;;
    protect) k8sProbeProtectStatus "$_k8s_workdir" ;;
    pvc) k8sProbePVCs "$_k8s_workdir" ;;
    pvc-size|pvc-sizes) k8sProbePvcSizes "$_k8s_workdir" ;;
    pvc-byte|pvc-bytes) k8sProbePvcBytes "$_k8s_workdir" ;;
    pvc-total) k8sProbePvcBytesTotal "$_k8s_workdir" ;;
    selector) k8sProbeSelector "$_k8s_workdir" ;;
    setname) k8sProbeSetName "$_k8s_workdir" ;;
    status) k8sProbeStatus "$_k8s_workdir" ;;
    tls) k8sProbeTLS "$_k8s_workdir" "$@" ;;
    values) k8sProbeValues "$_k8s_workdir" ;;
    *) Lowlight "$k8s_probe_help" ;;
  esac
  echo ''
}
export k8sProbe
readonly k8sProbe
