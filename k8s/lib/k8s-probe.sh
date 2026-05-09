#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-template.sh" ]; then . ./k8s-template.sh; else . /opt/k8s/lib/k8s-template.sh; fi
readonly k8s_probe_help="
k8s probe <command> [.]
  -h|h            Show help
"
k8sProbeEnvYaml(){
  Usage $# 1 2 'k8sProbeEnvYaml <workdir> [WITH_PANIC]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_panic="${2:-}"
  local _k8s_env_dir
  local _k8s_env_yaml
  for _k8s_env_dir in "$_k8s_workdir" "$_k8s_workdir/.." "$_k8s_workdir/../.."; do
    _k8s_env_yaml=$(realpath "$_k8s_env_dir/$K8S_ENV_YAML")
    if [ -f "$_k8s_env_yaml" ]; then
      printf '%s' "$_k8s_env_yaml"
      return 0
    fi
  done
  if [ "$_k8s_with_panic" = WITH_PANIC ]; then
    PanicD "missing $K8S_ENV_YAML" "缺少 $K8S_ENV_YAML"
  fi
}
export k8sProbeEnvYaml
readonly k8sProbeEnvYaml

k8sProbeEnv(){
  Usage $# -eq 1 'k8sProbeEnv <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_env_yaml
  _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_workdir" WITH_PANIC)
  echo "# $_k8s_env_yaml"
  cat "$_k8s_env_yaml"
  echo ''
}
export k8sProbeEnv
readonly k8sProbeEnv

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
  echo "# $_k8s_global_yaml"
  k8sTemplate "$_k8s_workdir" "$(cat "$_k8s_global_yaml")"
  echo ''
}
export k8sProbeGlobal
readonly k8sProbeGlobal

k8sProbeConfigMap(){
  Usage $# 1 2 'k8sProbeConfigMap <workdir> [cat_then_delete=|-d]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_cat_then_delete="${2:-}"

  local _k8s_temp_dir="${_k8s_workdir}/temp"
  PanicIfNotDir "$_k8s_temp_dir"
  local _k8s_templates_dir="${_k8s_workdir}/templates"
  local _k8s_temp

  k8sClearWorkDir "$_k8s_workdir"

  for _k8s_temp in "$_k8s_temp_dir"/*.temp; do
    [ -f "$_k8s_temp" ] || continue
    # shellcheck disable=SC2086
    k8sProcessTemplate "$_k8s_temp" "$_k8s_templates_dir" $_k8s_cat_then_delete
  done
}
export k8sProbeConfigMap
readonly k8sProbeConfigMap

k8sProbeValues(){
  Usage $# -eq 1 'k8sProbeValues <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_values_yaml="$_k8s_workdir/values.yaml"
  local _k8s_namespace_prefix
  _k8s_namespace_prefix=$(k8sProbeNamespacePrefix "$_k8s_workdir" WITH_CACHE)
  local _k8s_values_override_yaml="$_k8s_workdir/values-${_k8s_namespace_prefix}.yaml"
  if [ ! -f "$_k8s_values_override_yaml" ]; then
    cat "$_k8s_values_yaml"
    return 0
  fi
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$_k8s_values_yaml" "$_k8s_values_override_yaml"
}
export k8sProbeValues
readonly k8sProbeValues

k8sProbeImages(){
  Usage $# -eq 1 'k8sProbeImages <values>'
  local _k8s_values
  _k8s_values="$(AbsDir "$1")"

  local _k8s_image
  if echo "$_k8s_values" | yq eval 'has("images")' - | grep -q true; then
    yq eval '.images[]' <<< "$_k8s_values"
  fi

  YqGet ".image" -s "$_k8s_values"
}
export k8sProbeImages
readonly k8sProbeImages

k8sProbeDryRun(){
  Usage $# -eq 1 'k8sProbeDryRun <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  k8sUp "$_k8s_workdir" --dry-run
}
export k8sProbeImages
readonly k8sProbeImages

k8sProbeStatus(){
  Usage $# -eq 1 'k8sProbeStatus <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir" WITH_CACHE)
  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir" WITH_CACHE)
  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
  local _k8s_container
  _k8s_container=$(k8sDefaultContainerName "$_k8s_chart_name")

  local _k8s_pvcs
  _k8s_pvcs=$(k8sProbePVCs "$_k8s_workdir")

  k8sStatus "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" "${_k8s_pvcs[@]}"
}
export k8sProbeStatus
readonly k8sProbeStatus

k8sProbeTLS(){
  Usage $# -ge 1 'k8sProbeTLS <workdir> [format=|json]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  shift

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir" WITH_CACHE)
  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")

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
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir" WITH_CACHE)
  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir" WITH_CACHE)
  local _k8s_selector
  _k8s_selector=$(k8sProbeSelector "$_k8s_workdir")
  local _k8s_container
  _k8s_container=$(k8sDefaultContainerName "$_k8s_chart_name")

  k8sLogs "$_k8s_namespace" "$_k8s_selector" "$_k8s_container" "$@"
}
export k8sProbeLogs
readonly k8sProbeLogs

k8sProbePVCs(){
  Usage $# -ge 1 'k8sProbeLogs <workdir> [container|pod]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_set_yaml="${_k8s_workdir}/${K8S_SET_YAML_REL}"
  PanicIfNotFile "$_k8s_set_yaml"

  local _k8s_pvcs

  while IFS= read -r _k8s_pvc; do
    [ -z "$_k8s_pvc" ] && continue
    k8sRecoverValue "$_k8s_workdir" "$_k8s_pvc"
  done < <(yq eval '.spec.volumeClaimTemplates[].metadata.name' "$_k8s_set_yaml")
}
export k8sProbePVCs
readonly k8sProbePVCs

k8sProbeSelector(){
  Usage $# -eq 1 'k8sProbeSelector <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir" WITH_CACHE)
  local _k8s_values
  _k8s_values=$(k8sProbeValues "$_k8s_workdir")

  local _k8s_selector
  _k8s_selector=$(YqGet ".${K8S_SELECTOR_TAG}" -s "$_k8s_values")
  if [ -n "$_k8s_selector" ]; then
    printf '%s' "$_k8s_selector"
    return 0
  fi

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir" WITH_CACHE)

  k8sDefaultSelector "$_k8s_chart_name"
}
export k8sProbeSelector
readonly k8sProbeSelector


k8sProbe(){
  local _k8s_workdir
  _k8s_workdir=$(k8sWorkDir)
  local _k8s_what="${1:-}"
  shift
  case "$_k8s_what" in
    configmap) k8sProbeConfigMap "$_k8s_workdir" -d ;;
    dry) k8sProbeDryRun "$_k8s_workdir" ;;
    env) k8sProbeEnv "$_k8s_workdir" ;;
    global) k8sProbeGlobal "$_k8s_workdir" ;;
    images) k8sProbeImages "$(k8sProbeValues "$_k8s_workdir")" ;;
    logs) k8sProbeLogs "$_k8s_workdir" ;;
    name) k8sProbeName "$_k8s_workdir" WITH_CACHE;;
    n|namespace) k8sProbeNamespace "$_k8s_workdir" WITH_CACHE;;
    prefix) k8sProbeNamespacePrefix "$_k8s_workdir" WITH_CACHE;;
    pvc)k8sProbePVCs "$_k8s_workdir";;
    selector) k8sProbeSelector "$_k8s_workdir";;
    setname) k8sProbeSetName "$_k8s_workdir" WITH_CACHE;;
    status) k8sProbeStatus "$_k8s_workdir";;
    tls) k8sProbeTLS "$_k8s_workdir" "$@";;
    values) k8sProbeValues "$_k8s_workdir";;
    *) Lowlight "$k8s_probe_help" ;;
  esac
  echo ''
}
export k8sProbe
readonly k8sProbe
