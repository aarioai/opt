#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-base.sh" ]; then . ./k8s-base.sh; else . /opt/k8s/lib/k8s-base.sh; fi

export K8S_CHART_YAML='Chart.yaml'
readonly K8S_CHART_YAML

_K8S_CHART_NAME_=''
_K8S_NAMESPACE_PREFIX_=''
_K8S_NAMESPACE_=''
_K8S_SETNAME_=''

k8sWorkDir(){
  Usage $# -le 1 'k8sWorkDir [dir=.]'
  local _k8s_workdir=${1:-"."}
  for _k8s_dir in "$_k8s_workdir" "$_k8s_workdir/.." "$_k8s_workdir/../.."; do
    if [ -f "${_k8s_dir}/${K8S_CHART_YAML}" ]; then
      printf '%s' "$(AbsDir "$_k8s_dir")"
      return 0
    fi
  done

  PanicD "missing Chart.yaml, current directory is not a helm directory" "缺少Chart.yaml，当前文件夹不是正确的helm文件夹"
}
export k8sWorkDir
readonly k8sWorkDir

k8sClearWorkDir(){
  Usage $# -eq 1 'k8sClearWorkDir <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  Debug "rm -f ${_k8s_workdir}/templates/*.temp.yaml"
  rm -f "${_k8s_workdir}/templates"/*.temp.yaml
}
export k8sClearWorkDir
readonly k8sClearWorkDir

k8sProbeNamespacePrefix(){
  Usage $# 1 2 'k8sProbeNamespacePrefix <workdir> [WITH_CACHE]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_NAMESPACE_PREFIX_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_env_yaml
    _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_workdir" WITH_PANIC)
    local _k8s_namespace_prefix
    _k8s_namespace_prefix=$(YqGet ".namespace.prefix" -f "$_k8s_env_yaml" WITH_PANIC)
    _K8S_NAMESPACE_PREFIX_="$_k8s_namespace_prefix"
  fi
  printf '%s' "$_K8S_NAMESPACE_PREFIX_"
}
export k8sProbeNamespacePrefix
readonly k8sProbeNamespacePrefix

k8sProbeNamespace(){
  Usage $# 1 2 'k8sProbeNamespace <workdir> [WITH_CACHE]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_NAMESPACE_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_global_yaml
    _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_workdir" WITH_PANIC)
    _k8s_namespace=$(yq 'select(.kind == "Namespace") | .metadata.name' "$_k8s_global_yaml")
    _k8s_namespace=$(k8sTemplate "$_k8s_workdir" "$_k8s_namespace")
    PanicIfEmpty "$_k8s_namespace" 'Namespace.metadata.name'
    _K8S_NAMESPACE_="$_k8s_namespace"
  fi
  printf '%s' "$_K8S_NAMESPACE_"
}
export k8sProbeNamespace
readonly k8sProbeNamespace

k8sProbeName(){
  Usage $# 1 2 'k8sProbeName <workdir> [WITH_CACHE]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_CHART_NAME_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_chart_name
    _k8s_chart_name=$(YqGet '.name' -f "${_k8s_workdir}/${K8S_CHART_YAML}" WITH_PANIC)
    _K8S_CHART_NAME_="$_k8s_chart_name"
  fi
  printf '%s' "$_K8S_CHART_NAME_"
}
export k8sProbeName
readonly k8sProbeName

k8sRecoverValue(){
  Usage $# -eq 2 'k8sGetValue <workdir> <value_with_pattern>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_value="$2"

  local _k8s_chart_name
  _k8s_chart_name=$(k8sProbeName "$_k8s_workdir" WITH_CACHE)

  printf '%s' "$_k8s_value" | sed "s/{{[[:space:]]*\.[[:space:]]*Chart\.Name[[:space:]]*}}/${_k8s_chart_name}/g"
}
export k8sRecoverValue
readonly k8sRecoverValue

k8sGetValue(){
  Usage $# -ge 4 'k8sGetValue <workdir> <key> <-f|-s> <yaml|str>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_yq_key="$2"
  local _k8s_yq_type="$3"
  local _k8s_yq_input="$4"

  k8sRecoverValue "$_k8s_workdir" "$(YqGet "$_k8s_yq_key" "$_k8s_yq_type" "$_k8s_yq_input" WITH_PANIC)"
}
export k8sGetValue
readonly k8sGetValue

k8sProbeSetName(){
  Usage $# -ge 1 'k8sProbeSetName <workdir> [WITH_CACHE]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_SETNAME_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_set_yaml="${_k8s_workdir}/${K8S_SET_YAML_REL}"
    PanicIfNotFile "$_k8s_set_yaml"

    local _k8s_kind
    _k8s_kind=$(YqGet '.kind' -f "$_k8s_set_yaml" WITH_PANIC)
    local _k8s_set
    _k8s_set=$(k8sGetValue "$_k8s_workdir" '.metadata.name' -f "$_k8s_set_yaml")
    _K8S_SETNAME_="${_k8s_kind,,}/${_k8s_set}"
  fi

  printf '%s' "$_K8S_SETNAME_"
}
export k8sProbeLogs
readonly k8sProbeLogs

k8sTemplate(){
  Usage $# -eq 2 'k8sTemplate  <env_yaml|workdir> <str>'
  local _k8s_env_yaml="$1"
  local _k8s_template_str="$2"

  if [ -d "$_k8s_env_yaml" ];then
    _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_env_yaml" WITH_PANIC)
  fi

  PanicIfNotFile "$_k8s_env_yaml"

  local _k8s_env_value

  while read -r _k8s_template; do
    _k8s_env_value=$(YqGet ".$_k8s_template" -f "$_k8s_env_yaml" WITH_PANIC)
    if [ "$_k8s_template" = 'namespace.prefix' ]; then
      _K8S_NAMESPACE_PREFIX_="$_k8s_env_value"
    fi
    _k8s_template_str=$(printf "%s" "$_k8s_template_str" | sed "s/{{ \.Env\.$_k8s_template }}/$_k8s_env_value/g")
  done <<< "$(echo "$_k8s_template_str" | grep -oP '\{\{ \.Env\.\K[^}]+(?= \}\})')"

  printf '%s' "$(Unquote "$_k8s_template_str")"
}
export k8sTemplate
readonly k8sTemplate

k8sProcessTemplate(){
  Usage $# 2 3 'k8sProcessTemplate <temp_file> <dst_dir> [cat_then_delete=|-d]'
  local _k8s_temp_file="$1"
  local _k8s_temp_dst="$2"
  local _k8s_cat_then_delete="${3:-}"
  PanicIfNotFile "$_k8s_temp_file"

  if [ "$_k8s_temp_dst" = '-d' ]; then
    _k8s_temp_dst=''
    _k8s_cat_then_delete='-d'
  fi

  local _k8s_temp_dir
  _k8s_temp_dir=$(AbsDir "$_k8s_temp_file")
  local _k8s_temp_filename
  _k8s_temp_filename=$(basename "$_k8s_temp_file")
  _k8s_temp_dst="${_k8s_temp_dst}/${_k8s_temp_filename}.yaml"

  # 下面 trap 需要用到全局变量，因此不能使用 local
  _k8s_g_temp=$(mktemp)
  trap 'rm -f "$_k8s_g_temp"' EXIT
  trap 'rm -f "$_k8s_g_temp"; exit 1' INT TERM

  cat "$_k8s_temp_file" > "$_k8s_g_temp"

  local _k8s_temp_tag
  local _k8s_data_file
  MatchedLines "$_k8s_g_temp" '@include/' | while IFS= read -r _k8s_temp_tag; do
    [ -n "$_k8s_temp_tag" ] || continue
    _k8s_data_file="${_k8s_temp_dir}/${_k8s_temp_tag#@}"
    ReplaceYamlConfig "$_k8s_g_temp" "$_k8s_g_temp" "$_k8s_temp_tag" "$_k8s_data_file"
  done
  if [ "$_k8s_cat_then_delete" = '-d' ]; then
    echo "# Generated $_k8s_temp_dst"
    cat "$_k8s_g_temp"
  else
    chmod a+r "$_k8s_g_temp"
    rm -f "$_k8s_temp_dst"
    mv "$_k8s_g_temp" "$_k8s_temp_dst"
    Debug "convert $(LastN 2 '/' "$_k8s_temp_file") => $(LastN 2 '/' "$_k8s_temp_dst")"
  fi
  rm -f "$_k8s_g_temp"

}
export k8sProcessTemplate
readonly k8sProcessTemplate

k8sValuesExistsTLS(){
  Usage $# -eq 1 'k8sValuesExistsTLS <values>'
  local _k8s_values
  _k8s_values="$(AbsDir "$1")"

  YqIsNotEmptyArray ".${K8S_TLS_TAG}" -s "$_k8s_values"
}
export k8sValuesExistsTLS
readonly k8sValuesExistsTLS

