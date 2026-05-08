#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-base.sh" ]; then . ./k8s-base.sh; else . /opt/k8s/lib/k8s-base.sh; fi

_K8S_NAMESPACE_PREFIX_=''
_K8S_NAMESPACE_=''


k8sProbeNamespacePrefix(){
  Usage $# 1 2 'k8sProbeNamespacePrefix <chart_dir> [WITH_CACHE]'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_NAMESPACE_PREFIX_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_env_yaml
    _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_chart_dir" WITH_PANIC)
    local _k8s_namespace_prefix
    _k8s_namespace_prefix=$(YqGet ".namespace.prefix" -f "$_k8s_env_yaml" WITH_PANIC)
    _K8S_NAMESPACE_PREFIX_="$_k8s_namespace_prefix"
  fi
  printf '%s' "$_K8S_NAMESPACE_PREFIX_"
}
export k8sProbeNamespacePrefix
readonly k8sProbeNamespacePrefix

k8sProbeNamespace(){
  Usage $# 1 2 'k8sProbeNamespace <chart_dir> [WITH_CACHE]'
  local _k8s_chart_dir
  _k8s_chart_dir="$(AbsDir "$1")"
  local _k8s_with_cache="${2:-}"

  if [ -z "$_K8S_NAMESPACE_" ] || [ "$_k8s_with_cache" != WITH_CACHE ]; then
    local _k8s_global_yaml
    _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_chart_dir" WITH_PANIC)
    _k8s_namespace=$(yq 'select(.kind == "Namespace") | .metadata.name' "$_k8s_global_yaml")
    _k8s_namespace=$(k8sTemplate "$_k8s_chart_dir" "$_k8s_namespace")
    PanicIfEmpty "$_k8s_namespace" 'Namespace.metadata.name'
    _K8S_NAMESPACE_="$_k8s_namespace"
  fi
  printf '%s' "$_K8S_NAMESPACE_"
}
export k8sProbeNamespace
readonly k8sProbeNamespace

k8sTemplate(){
  Usage $# -eq 2 'k8sTemplate  <env_yaml|chat_dir> <str>'
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
  Usage $# 1 2 'k8sProcessTemplate <temp_file> [cat_then_delete=|-d]'
  local _k8s_temp_file="$1"
  local _k8s_cat_then_delete="${2:-}"
  PanicIfNotFile "$_k8s_temp_file"

  local _k8s_temp_dir
  _k8s_temp_dir=$(AbsDir "$_k8s_temp_file")
  local _k8s_temp_filename
  _k8s_temp_filename=$(basename "$_k8s_temp_file")
  local _k8s_temp_dst="${_k8s_temp_dir}/${_k8s_temp_filename}.yaml"

  # 下面 trap 需要用到全局变量，因此不能使用 local
  _k8s_g_temp=$(mktemp)
  trap 'rm -f "$_k8s_g_temp"' EXIT
  trap 'rm -f "$_k8s_g_temp"; exit 1' INT TERM

  cat "$_k8s_temp_file" > "$_k8s_g_temp"

  local _k8s_temp_tag
  local _k8s_data_file
  MatchedLines "$_k8s_g_temp" '@data/' | while IFS= read -r _k8s_temp_tag; do
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