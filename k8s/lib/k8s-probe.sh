#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-template.sh" ]; then . ./k8s-template.sh; else . /opt/k8s/lib/k8s-template.sh; fi

# Is Helm chart directory
k8sIsChartDir(){
  local dir="$1"
  if [ -d "$dir" ] && [ -f "$dir/Chart.yaml" ]; then
    return 0
  fi
  return 1
}
export k8sIsChartDir
readonly k8sIsChartDir

k8sProbeEnvYaml(){
  Usage $# 1 2 'k8sProbeEnvYaml <chart_dir> [WITH_PANIC]'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"
  local _k8s_with_panic="${2:-}"
  local _k8s_env_dir
  local _k8s_env_yaml
  for _k8s_env_dir in "$_k8s_chart_dir" "$_k8s_chart_dir/.." "$_k8s_chart_dir/../.."; do
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
  Usage $# -eq 1 'k8sProbeEnv <chat_dir>'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"

  local _k8s_env_yaml
  _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_chart_dir" WITH_PANIC)
  echo "# $_k8s_env_yaml"
  cat "$_k8s_env_yaml"
  echo ''
}
export k8sProbeEnv
readonly k8sProbeEnv

k8sProbeGlobalYaml(){
  Usage $# 1 2 'k8sProbeGlobalYaml <chart_dir> [WITH_PANIC]'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"
  local _k8s_with_panic="${2:-}"

  local _k8s_global_dir
  local _k8s_global_yaml
  for _k8s_global_dir in "$_k8s_chart_dir" "$_k8s_chart_dir/.." "$_k8s_chart_dir/../.."; do
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
  Usage $# -eq 1 'k8sProbeGlobal <chat_dir>'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"

  local _k8s_global_yaml
  _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_chart_dir" WITH_PANIC)
  echo "# $_k8s_global_yaml"
  k8sTemplate "$_k8s_chart_dir" "$(cat "$_k8s_global_yaml")"
  echo ''
}
export k8sProbeGlobal
readonly k8sProbeGlobal

k8sProbeConfigMap(){
  Usage $# 1 2 'k8sProbeConfigMap <chat_dir> [cat_then_delete=|-d]'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"
  local _k8s_cat_then_delete="${2:-}"

  local _k8s_templates_dir="${_k8s_chart_dir}/templates"
  PanicIfNotDir "$_k8s_templates_dir"
  local _k8s_temp
  for _k8s_temp in "$_k8s_templates_dir"/*.temp; do
    [ -f "$_k8s_temp" ] || continue
    # shellcheck disable=SC2086
    k8sProcessTemplate "$_k8s_temp" $_k8s_cat_then_delete
  done
}
export k8sProbeConfigMap
readonly k8sProbeConfigMap

k8sProbeValues(){
  Usage $# -eq 1 'k8sProbeValues <chat_dir>'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"

  local _k8s_values_yaml="$_k8s_chart_dir/values.yaml"
  local _k8s_namespace_prefix
  _k8s_namespace_prefix=$(k8sProbeNamespacePrefix "$_k8s_chart_dir" WITH_CACHE)
  local _k8s_values_override_yaml="$_k8s_chart_dir/values-${_k8s_namespace_prefix}.yaml"
  if [ ! -f "$_k8s_values_override_yaml" ]; then
    cat "$_k8s_values_yaml"
    return 0
  fi
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$_k8s_values_yaml" "$_k8s_values_override_yaml"
}
export k8sProbeValues
readonly k8sProbeValues

k8sProbeImages(){
  echo ''
}
export k8sProbeImages
readonly k8sProbeImages

k8sProbe(){
  local chart_dir='./'
  if ! k8sIsChartDir "$chart_dir"; then
    PanicD "missing Chart.yaml, current directory is not a helm directory" "缺少Chart.yaml，当前文件夹不是正确的helm文件夹"
  fi
  local _k8s_what="${1:-}"
  case "$_k8s_what" in
    configmap) k8sProbeConfigMap "$chart_dir" -d;;
    env) k8sProbeEnv "$chart_dir" ;;
    global) k8sProbeGlobal "$chart_dir" ;;
    n|namespace) k8sProbeNamespace "$chart_dir" WITH_CACHE;;
    prefix) k8sProbeNamespacePrefix "$chart_dir" WITH_CACHE;;
    values) k8sProbeValues "$chart_dir";;
  esac
  echo ''
}
export k8sProbe
readonly k8sProbe
