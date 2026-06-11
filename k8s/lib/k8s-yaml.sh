#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-template.sh" ]; then . ./k8s-template.sh; else . /opt/k8s/lib/k8s-template.sh; fi

k8sExtraCommand(){
  Usage $# -ge 2 'k8sExtraCommand <workdir> <command=status|up|down>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_cmd="$2"

  local _k8s_yaml="${_k8s_workdir}/${K8S_YAML}"
  if [ ! -f "$_k8s_yaml" ]; then
    return
  fi

  local _k8s_yaml_s
  _k8s_yaml_s=$(cat "$_k8s_yaml")
  _k8s_yaml_s=$(k8sRenderTemplate "$_k8s_workdir" "$_k8s_yaml_s")

  if ! YqIsNotEmptyArray "$_k8s_cmd" -s "$_k8s_yaml_s"; then
    return
  fi

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  local _k8s_status_run
  while IFS= read -r _k8s_status_run || [ -n "$_k8s_status_run" ]; do
    case "$_k8s_status_run" in
      crictl\ *|ctr\ *|kubectl\ *)
        _k8s_status_run="$_k8s_cmd_prefix $_k8s_status_run"
      ;;
    esac
    Debug "$_k8s_status_run"
    eval $_k8s_status_run
  done < <(echo "$_k8s_yaml_s" | yq -r ".${_k8s_cmd}[]" 2>/dev/null)
}
export k8sExtraStatus
readonly k8sExtraStatus