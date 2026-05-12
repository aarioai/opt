#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-base.sh" ]; then . ./k8s-base.sh; else . /opt/k8s/lib/k8s-base.sh; fi

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

  return 0
  PanicIfEmpty "$K8S_GENERATED_PREFIX" 'K8S_GENERATED_PREFIX'
  Debug "rm -f ${_k8s_workdir}/templates/${K8S_GENERATED_PREFIX}*"
  rm -f "${_k8s_workdir}/templates/${K8S_GENERATED_PREFIX}"*
}
export k8sClearWorkDir
readonly k8sClearWorkDir

k8sProbeName(){
  Usage $# -eq 1 'k8sProbeName <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  YqGet '.name' -f "${_k8s_workdir}/${K8S_CHART_YAML}" WITH_PANIC
}
export k8sProbeName
readonly k8sProbeName

k8sRenderTemplate(){
  Usage $# -eq 2 'k8sRenderTemplate <workdir> <value_with_pattern>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_value="$2"

  declare -A _k8s_vars

  while IFS= read -r _k8s_yaml_line || [ -n "$_k8s_yaml_line" ]; do
    # Match standard "{{ .Var }}" or "{{ .Var }}-key", i.e. helm template with quotes
    while [[ $_k8s_yaml_line =~ \{\{[[:space:]]*([^}]+)[[:space:]]*\}\} ]]; do
      local _k8s_var
      _k8s_var=$(Trim "${BASH_REMATCH[1]}")
      _k8s_vars["$_k8s_var"]=1
      _k8s_yaml_line="${_k8s_yaml_line#*"${BASH_REMATCH[0]}"}"
    done

    # Match {? {.Var: ''} : ''}, i.e. helm template without quotes
    while [[ $_k8s_yaml_line =~ \{\?[[:space:]]*\{[[:space:]]*([^:]+):[[:space:]]*'' ]]; do
      local _k8s_var
      _k8s_var=$(Trim "${BASH_REMATCH[1]}")
      _k8s_vars["${BASH_REMATCH[1]}"]=1
      _k8s_yaml_line="${_k8s_yaml_line#*"${BASH_REMATCH[0]}"}"
    done
  done <<< "$_k8s_value"

  local _k8s_chart_yaml="${_k8s_workdir}/${K8S_CHART_YAML}"
  local _k8s_env_yaml=''
  local _k8s_values=''

  local _k8s_safe_sed_sep
  local _k8s_real_value
  local _k8s_pattern
  for _k8s_var in  "${!_k8s_vars[@]}"; do
    case "$_k8s_var" in
      ".Chart."*)
        _k8s_real_value="${_k8s_var#.Chart.}";
        _k8s_real_value="${_k8s_real_value,}"   # convert first character to lowercase
        _k8s_real_value=$(YqGet ".${_k8s_real_value}" -f "$_k8s_chart_yaml" WITH_PANIC)
        ;;
      ".Env."*)
        if [ -z "$_k8s_env_yaml" ]; then _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_workdir" WITH_PANIC); fi
        _k8s_real_value="${_k8s_var#.Env.}";
        _k8s_real_value="${_k8s_real_value,}"   # convert first character to lowercase
        _k8s_real_value=$(YqGet ".${_k8s_real_value}" -f "$_k8s_env_yaml" WITH_PANIC)
        ;;
      ".Values."*)
        if [ -z "$_k8s_values" ]; then _k8s_values=$(k8sProbeValues "$_k8s_workdir"); fi
        _k8s_real_value="${_k8s_var#.Values.}";
        _k8s_real_value="${_k8s_real_value,}"   # convert first character to lowercase
        _k8s_real_value=$(YqGet ".${_k8s_real_value}" -s "$_k8s_values" WITH_PANIC)
        ;;
      *) PanicD "invalid template pattern $_k8s_var" "错误的模板变量$_k8s_var" ;;
    esac
    _k8s_safe_sed_sep=$(SafeSedSeparator "{}${_k8s_var}${_k8s_real_value}")
    # Handle "{{ .Var }}"
    _k8s_pattern="s${_k8s_safe_sed_sep}\\{\\{[[:space:]]*${_k8s_var}[[:space:]]*\\}\\}${_k8s_safe_sed_sep}${_k8s_real_value}${_k8s_safe_sed_sep}g"
    _k8s_value=$(printf '%s' "$_k8s_value" | sed -E "$_k8s_pattern")
    # Handle {? {.Var: ''} : ''}, i.e. helm template without quotes
    _k8s_pattern="s${_k8s_safe_sed_sep}\\{\?[[:space:]]*\\{[[:space:]]*${_k8s_var}[[:space:]]*\:[[:space:]]*''\\}[[:space:]]*\:[[:space:]]*''[[:space:]]*\\}${_k8s_safe_sed_sep}${_k8s_real_value}${_k8s_safe_sed_sep}g"
    _k8s_value=$(printf '%s' "$_k8s_value" | sed -E "$_k8s_pattern")
  done

  printf '%s' "$_k8s_value"
}
export k8sRenderTemplate
readonly k8sRenderTemplate

k8sRenderConfigmap(){
  Usage $# 3 4 'k8sRenderConfigmap <env> <configmap_file> <dst_dir> [cat_then_delete=|-d]'
  local _k8s_env="$1"
  local _k8s_configmap_file="$2"
  local _k8s_temp_dst="$3"
  local _k8s_cat_then_delete="${4:-}"
  PanicIfNotFile "$_k8s_configmap_file"

  if [ "$_k8s_temp_dst" = '-d' ]; then
    _k8s_temp_dst=''
    _k8s_cat_then_delete='-d'
  fi

  local _k8s_temp_dir
  _k8s_temp_dir=$(AbsDir "$_k8s_configmap_file")
  local _k8s_configmap_filename
  _k8s_configmap_filename=$(basename "$_k8s_configmap_file")
  _k8s_temp_dst="${_k8s_temp_dst}/${K8S_GENERATED_PREFIX}${_k8s_configmap_filename}"

  # 下面 trap 需要用到全局变量，因此不能使用 local
  _k8s_g_tempdir=$(mktemp -d) || PanicMktemp
  trap 'rm -rf "$_k8s_g_tempdir" 2>/dev/null' EXIT
  trap 'rm -rf "$_k8s_g_tempdir" 2>/dev/null; return 1' INT TERM

  _k8s_g_temp="${_k8s_g_tempdir}/$(basename "$_k8s_configmap_file")"
  _k8s_g_temp_include="${_k8s_g_temp}-configmap.yaml"
  cat "$_k8s_configmap_file" > "$_k8s_g_temp"

  local _k8s_include_tag
  local _k8s_include_path
  local _k8s_include_env_path
    local _k8s_include_abs
    local _k8s_include_env_abs

  while IFS= read -r _k8s_include_tag || [ -n "$_k8s_include_tag" ]; do
    [ -n "$_k8s_include_tag" ] || continue
    _k8s_include_path="${_k8s_include_tag#@}"   # trim @
    _k8s_include_env_path="${_k8s_include_path%.*}-${_k8s_env}.${_k8s_include_path##*.}"
    _k8s_include_abs="${_k8s_temp_dir}/${_k8s_include_path}"
    _k8s_include_env_abs="${_k8s_temp_dir}/${_k8s_include_env_path}"
    if [ ! -f "$_k8s_include_abs" ] && [ ! -f "$_k8s_include_env_abs" ]; then
      PanicD "missing configmap $_k8s_include_tag" "缺少 configmap $_k8s_include_tag"
    fi

    CopyOrTouchOrPanic "$_k8s_include_abs" "$_k8s_g_temp_include"

    if [ -f "$_k8s_include_env_abs" ]; then
      InfoD "merge #$_k8s_include_env_path into #$_k8s_include_path" "合并 $_k8s_include_env_path 到 $_k8s_include_path"
      WriteFileOrSudo "$LF" '->>' "$_k8s_g_temp_include"
      CatOrPanic "$_k8s_include_env_abs" '->>' "$_k8s_g_temp_include"
      WriteFileOrSudo "$LF" '->>' "$_k8s_g_temp_include"
    fi

    ReplaceYamlConfig "$_k8s_g_temp" "$_k8s_g_temp" "$_k8s_include_tag" "$_k8s_g_temp_include"
  done < <(MatchedLines "$_k8s_g_temp" "$K8S_INCLUDE_PREFIX")

  if [ "$_k8s_cat_then_delete" = '-d' ]; then
    Lowlight "# Generated $_k8s_temp_dst"
    CatOrPanic "$_k8s_g_temp"
  else
    chmod a+r "$_k8s_g_temp"
    MoveOrPanic "$_k8s_g_temp" "$_k8s_temp_dst"
    Debug "convert $(LastN 2 '/' "$_k8s_configmap_file") => $(LastN 2 '/' "$_k8s_temp_dst")"
  fi
  rm -rf "$_k8s_g_tempdir"
}
export k8sRenderConfigmap
readonly k8sRenderConfigmap

k8sGetValue(){
  Usage $# -ge 4 'k8sGetValue <workdir> <key> <-f|-s> <yaml|str>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_yq_key="$2"
  local _k8s_yq_type="$3"
  local _k8s_yq_input="$4"

  local _k8s_value
  _k8s_value=$(YqGet "$_k8s_yq_key" "$_k8s_yq_type" "$_k8s_yq_input" WITH_PANIC)
  k8sRenderTemplate "$_k8s_workdir" "$_k8s_value"
}
export k8sGetValue
readonly k8sGetValue

k8sProbeEnv(){
  Usage $# -ge 1 'k8sProbeEnv <workdir> [-v]'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"
  local _k8s_verbose="${2:-}"

  local _k8s_env_yaml
  _k8s_env_yaml=$(k8sProbeEnvYaml "$_k8s_workdir" WITH_PANIC)

  if [ "$_k8s_verbose" != '-v' ]; then
    YqGet ".env" -f "$_k8s_env_yaml" WITH_PANIC
    return 0
  fi
  Lowlight "# $_k8s_env_yaml"
  cat "$_k8s_env_yaml"
  echo ''
}
export k8sProbeEnv
readonly k8sProbeEnv


k8sProbeNamespace(){
  Usage $# -eq 1 'k8sProbeNamespace <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_global_yaml
  _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_workdir" WITH_PANIC)
  local _k8s_namespace
  _k8s_namespace=$(yq 'select(.kind == "Namespace") | .metadata.name' "$_k8s_global_yaml")
  _k8s_namespace=$(k8sRenderTemplate "$_k8s_workdir" "$_k8s_namespace")
  PanicIfEmpty "$_k8s_namespace" "<Namespace.metadata.name> $_k8s_global_yaml"
  printf '%s' "$_k8s_namespace"
}
export k8sProbeNamespace
readonly k8sProbeNamespace

k8sUpNamespaceNx(){
  Usage $# -eq 1 'k8sUpNamespaceNx <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")

  local _k8s_cmd_prefix
  _k8s_cmd_prefix=$(k8sKubectlPrefix)

  if $_k8s_cmd_prefix kubectl get namespace "$_k8s_namespace" &>/dev/null; then
    return
  fi

  local _k8s_global_yaml
  _k8s_global_yaml=$(k8sProbeGlobalYaml "$_k8s_workdir" WITH_PANIC)

  Debug "kubectl apply -f $(LastN 3 '/' "$_k8s_global_yaml")"
  k8sRenderTemplate "$_k8s_workdir" "$(<"$_k8s_global_yaml")" | $_k8s_cmd_prefix kubectl apply -f -
}
export k8sUpNamespaceNx
readonly k8sUpNamespaceNx

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

k8sProbeValues(){
  Usage $# -eq 1 'k8sProbeValues <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_values_yaml="${_k8s_workdir}/${K8S_VALUES_YAML_NAME}.yaml"
  local _k8s_env
  _k8s_env=$(k8sProbeEnv "$_k8s_workdir")
  local _k8s_values_override_yaml="$_k8s_workdir/${K8S_VALUES_YAML_NAME}-${_k8s_env}.yaml"
  if [ ! -f "$_k8s_values_override_yaml" ]; then
    cat "$_k8s_values_yaml"
    return 0
  fi
  local _k8s_values
  _k8s_values=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$_k8s_values_yaml" "$_k8s_values_override_yaml")

  # Try append .hostname
  local _k8s_hostname
  if command -v hostname >/dev/null 2>&1; then
    _k8s_hostname=$(hostname)
  fi
  local _k8s_values_hostname
  _k8s_values_hostname=$(YqGet '.hostname' -s "$_k8s_values")
  if [ -n "$_k8s_hostname" ] && [ -n "$_k8s_values_hostname" ] && [ "$_k8s_hostname" != "$_k8s_values_hostname" ]; then
    WarnD ".Values.hostname=$_k8s_values_hostname is not same as real hostname: $_k8s_hostname" \
      ".Values.hostname=$_k8s_values_hostname 跟主机hostname（$_k8s_hostname）不一致"
  fi

  if [ -z "$_k8s_values_hostname" ] && [ -n "$_k8s_hostname" ] ; then
    _k8s_values="hostname: ${_k8s_hostname}${LF}${_k8s_values}"
  fi

  # Try append .namespace
  local _k8s_namespace
  _k8s_namespace=$(k8sProbeNamespace "$_k8s_workdir")
  local _k8s_values_namespace
  _k8s_values_namespace=$(YqGet '.namespace' -s "$_k8s_values")
  if [ -z "$_k8s_namespace" ] && [ -z "$_k8s_values_namespace" ]; then
    PanicD 'missing namespace' '缺少 namespace'
  fi
  if [ -z "$_k8s_values_namespace" ]; then
    _k8s_values="namespace: ${_k8s_namespace}${LF}${_k8s_values}"
  fi

  echo "$_k8s_values"
}
export k8sProbeValues
readonly k8sProbeValues

k8sProbeSetName(){
  Usage $# -eq 1 'k8sProbeSetName <workdir>'
  local _k8s_workdir
  _k8s_workdir="$(k8sWorkDir "$1")"

  local _k8s_set_yaml="${_k8s_workdir}/${K8S_SET_YAML_REL}"
  PanicIfNotFile "$_k8s_set_yaml"
  local _k8s_kind
  _k8s_kind=$(YqGet '.kind' -f "$_k8s_set_yaml" WITH_PANIC)
  local _k8s_set
  _k8s_set=$(k8sGetValue "$_k8s_workdir" '.metadata.name' -f "$_k8s_set_yaml")
  printf '%s' "${_k8s_kind,,}/${_k8s_set}"
}
export k8sProbeLogs
readonly k8sProbeLogs

k8sValuesExistsTLS(){
  Usage $# -eq 1 'k8sValuesExistsTLS <values>'
  local _k8s_values
  _k8s_values="$(AbsDir "$1")"

  YqIsNotEmptyArray ".${K8S_TLS_TAG}" -s "$_k8s_values"
}
export k8sValuesExistsTLS
readonly k8sValuesExistsTLS

