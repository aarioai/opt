#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-lib.sh" ]; then . ./k8s-lib.sh; else . /opt/k8s/lib/k8s-lib.sh; fi

export REGISTRIES_YAML
readonly REGISTRIES_YAML='/etc/rancher/k3s/registries.yaml'

# 获取本机服务，如 https://127.0.0.1:6443
k3sClusterServe(){
  k3s kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
}
export k3sClusterServe
readonly k3sClusterServe

k3sContextCluster(){
  Usage $# -le 1 'k3sContextCluster [context=current-context]'
  local _k3s_ctx="${1:-}"
  if [ -z "$_k3s_ctx" ]; then
    _k3s_ctx=$(kubectl config current-context)
  fi
  k3s kubectl config view -o jsonpath="{.contexts[?(@.name=='$_k3s_ctx')].context.cluster}"
}
export k8sContextCluster
readonly k8sContextCluster

k3sRenewKubeconfig(){
  Usage $# 3 4 'k3sRenewKubeconfig <secret_name> <username> <kubeconfig_file=./dashboard-kubeconfig.yaml> [namespace=kubernetes-dashboard]'
  local _k3s_secret="$1"
  local _k3s_user="$2"
  local _k3s_file="$3"
  local _k3s_namespace="${4:-kubernetes-dashboard}"

  local _k3s_server
  local _k3s_current_ctx
  local _k3s_cluster
  local _k3s_context
  local _k3s_crt
  local _k3s_user_token
  _k3s_server=$(k3sClusterServe)
  _k3s_current_ctx=$(k3s kubectl config current-context)
  _k3s_cluster=$(k3sContextCluster "$_k3s_current_ctx")
  _k3s_context="kubeconfig-${_k3s_current_ctx}"  # 基于当前 context 生成
  _k3s_crt=$(k3s kubectl get secret "$_k3s_secret" -n "$_k3s_namespace" -o jsonpath='{.data.ca\.crt}')
  _k3s_user_token=$(k3s kubectl get secret "$_k3s_secret" -n "$_k3s_namespace" -o jsonpath='{.data.token}' | base64 --decode)

  if [ -f "$_k3s_file" ]; then
    $SUDO cp -f "$_k3s_file" "${_k3s_file}.bak"
    $SUDO rm -f "$_k3s_file"
  fi

  cat > "$_k3s_file" << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $_k3s_crt
    server: $_k3s_server
  name: $_k3s_cluster
contexts:
- context:
    cluster: $_k3s_cluster
    user: $_k3s_user
    namespace: $_k3s_namespace
  name: $_k3s_context
current-context: $_k3s_context
kind: Config
preferences: {}
users:
- name: $_k3s_user
  user:
    token: $_k3s_user_token
EOF
  $SUDO chmod 644 "$_k3s_file"
  Info "kubeconfig $_k3s_file generated"
}
export k8sGenerateKubeconfig
readonly k8sGenerateKubeconfig



# 获取 PVC 状态
k3sPvcStatus(){
  Usage $# -eq 2 'k3sPvcStatus <namespace> <pvc name>'
  local _k3s_namespace="$1"
  local _k3s_name="$2"
  Info "get pvc status => namespace: $_k3s_namespace, pvc_name: $_k3s_name"

  local ok=0

  local i
  for i in {1..30}; do
    local PVC_STATUS
    PVC_STATUS=$(kubectl get pvc "$_k3s_name" -n "$_k3s_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true || echo "Pending")
    if [ "$PVC_STATUS" = "Bound" ]; then
      ok=1
      break
    fi
    Debug "binding PVC (${_k3s_name} @${_k3s_namespace})... ($i/30)"
    sleep 2
  done

  if [ "$ok" -eq 0 ]; then
    $SUDO k3s kubectl describe pvc "$_k3s_name" -n "$_k3s_namespace"
    Panic "bind PVC (${_k3s_name} @${_k3s_namespace}) failed"
  fi
}
export k3sPvcStatus
readonly k3sPvcStatus

k3sStatus(){
  Usage $# -eq 3 'k3sStatus <namespace> <selector> <container_name>'
  local _k3s_namespace="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"

  Heading "[SERVICE] kubectl get service -n $_k3s_namespace -l $_k3s_selector -o wide"
  $SUDO k3s kubectl get service -n "$_k3s_namespace" -l "$_k3s_selector" -o wide

  Heading "[POD] kubectl get pods -n $_k3s_namespace -l $_k3s_selector"
  $SUDO k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector"

  Heading "[CONTAINER] crictl ps -a --name $_k3s_container"
  $SUDO k3s crictl ps -a --name "$_k3s_container"
}
export k3sStatus
readonly k3sStatus

# K3S 启动之后，查看容器状态
k3sWaitReady(){
  Usage $# -eq 3 'k3sWaitReady <namespace> <selector> <container_name>'
  local _k3s_namespace="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"

#  if [ -n "$_k3s_ingress" ]; then
#    Heading "[INGRESS] kubectl get ingressroute -A -n $_k3s_namespace"
#    $SUDO k3s kubectl get ingressroute -A -n "$_k3s_namespace"
#  fi

  Heading "[SERVICE] kubectl get service -n $_k3s_namespace -l $_k3s_selector -o wide"
  $SUDO k3s kubectl get service -n "$_k3s_namespace" -l "$_k3s_selector" -o wide

  Heading "kubectl wait --for=condition=Ready pod -n $_k3s_namespace -l $_k3s_selector --timeout=180s"
  if ! $SUDO k3s kubectl wait --for=condition=Ready pod -n "$_k3s_namespace" -l "$_k3s_selector" --timeout=180s 2>/dev/null; then
    k3sLogs "$_k3s_namespace" "$_k3s_selector" "$_k3s_container"
    return 1
  fi

  Heading "[POD] kubectl get pods -n $_k3s_namespace -l $_k3s_selector"
  $SUDO k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector"

  Heading "[CONTAINER] crictl ps -a --name $_k3s_container"
  $SUDO k3s crictl ps -a --name "$_k3s_container"

#  Heading "[IMAGE] crictl images | grep $_k3s_image"
#  $SUDO crictl images | grep "$_k3s_image"
}
export k3sWaitReady
readonly k3sWaitReady

k3sDetectGlobalYaml(){
  local _k3s_workdir="${1:-.}"
  local _k3s_paths=("${_k3s_workdir}" "${_k3s_workdir}/.." "${_k3s_workdir}/../..")
  local _k3s_path
  for _k3s_path in "${_k3s_paths[@]}"; do
    local _k3s_abs_path
    _k3s_abs_path=$(realpath -e "$_k3s_path" 2>/dev/null || realpath "$_k3s_path")
    local _k3s_ns
    _k3s_ns="$(FindFileByExt "$_k3s_abs_path" global yml yaml)"
    if [ -f "$_k3s_ns" ]; then
      printf '%s' "$_k3s_ns"
      return 0
    fi
  done
  return 1
}
export k3sDetectGlobalYaml
readonly k3sDetectGlobalYaml

k3sDetectNamespaceYaml(){
  local _k3s_workdir="${1:-.}"
  local _k3s_paths=("${_k3s_workdir}" "${_k3s_workdir}/.." "${_k3s_workdir}/../..")
  local _k3s_path
  for _k3s_path in "${_k3s_paths[@]}"; do
    local _k3s_abs_path
    _k3s_abs_path=$(realpath -e "$_k3s_path" 2>/dev/null || realpath "$_k3s_path")
    local _k3s_ns
    _k3s_ns="$(FindFileByExt "$_k3s_abs_path" namespace yml yaml 2>/dev/null)"
    if [ -f "$_k3s_ns" ]; then
      printf '%s' "$_k3s_ns"
      return 0
    fi
  done
  return 1
}
export k3sDetectNamespaceYaml
readonly k3sDetectNamespaceYaml

k3sTryApply(){
  Usage $# -eq 1 'k3sTryApply <yml_path>'
  local _k3s_workdir
  local _k3s_base
  local _k3s_yaml
  _k3s_workdir="$(dirname "$1")"
  _k3s_base="$(Filename "$1")"
  _k3s_yaml="$(FindFileByExt "$_k3s_workdir" "$_k3s_base" yml yaml)"
  if [ ! -f "$_k3s_yaml" ]; then
    return 0
  fi

  Debug "kubectl apply -f $(LastN 3 '/' "$_k3s_yaml")"
  $SUDO k3s kubectl apply -f "$_k3s_yaml"
}
export k3sTryApply
readonly k3sTryApply

k3sTryDelete(){
  Usage $# -eq 1 'k3sTryApply <yml_path>'
  local _k3s_workdir
  local _k3s_base
  local _k3s_yaml
  _k3s_workdir="$(dirname "$1")"
  _k3s_base="$(Filename "$1")"
  _k3s_yaml="$(FindFileByExt "$_k3s_workdir" "$_k3s_base" yml yaml)"
  if [ ! -f "$_k3s_yaml" ]; then
    return 0
  fi

  local _k3s_namespace
  _k3s_namespace="$(yq -r '.metadata.namespace' "$_k3s_yaml" | sed -n '1p;q')"
  if [ -z "$_k3s_namespace" ] || [ "$_k3s_namespace" = 'null' ]; then
    if [ "$(basename "$_k3s_yaml")" == "$K8S_UP_YAML" ]; then
      return 0
    fi
    PanicD "not found .metadata.namespace" "配置缺少.metadata.namespace"
  fi

  Debug "kubectl delete -n $_k3s_namespace -f $(LastN 3 '/' "$_k3s_yaml")"
  $SUDO k3s kubectl delete -n "$_k3s_namespace" -f "$_k3s_yaml" --ignore-not-found=true
}
export k3sTryDelete
readonly k3sTryDelete

k3sTryApplyGlobal(){
  Usage $# -eq 1 'k3sTryApplyGlobal <dir>'
  local _k3s_workdir="$1"
  k3sTryApply "$(k3sDetectGlobalYaml "$_k3s_workdir")"
  k3sTryApply "$(k3sDetectNamespaceYaml "$_k3s_workdir")"
}
export k3sTryApplyGlobal
readonly k3sTryApplyGlobal

_k3sConvertTmpl(){
  Usage $# -eq 2 '_k3sConvertTmpl <tmpl> <data_dir>'
  local _k3s_tmpl="$1"
  PanicIfNotFile "$_k3s_tmpl"

  # 下面 trap 需要用到全局变量，因此不能使用 local
  _k3s_global_tmpl_temp=$(mktemp)
  trap 'rm -f "$_k3s_global_tmpl_temp"' EXIT
  trap 'rm -f "$_k3s_global_tmpl_temp"; exit 1' INT TERM

  cat "$_k3s_tmpl" > "$_k3s_global_tmpl_temp"

  local _k3s_tmpl_tag
  MatchedLines "$_k3s_global_tmpl_temp" '@data/' | while IFS= read -r _k3s_tmpl_tag; do
    if [ -n "$_k3s_tmpl_tag" ]; then
      ReplaceYamlConfig "$_k3s_global_tmpl_temp" "$_k3s_global_tmpl_temp" "$_k3s_tmpl_tag"
    fi
  done

  local _k3s_dst
  _k3s_dst="${_k3s_tmpl%.tmpl}.yaml"
  rm -f "$_k3s_dst"
  mv "$_k3s_global_tmpl_temp" "$_k3s_dst"
  Info "convert $(LastN 3 '/' "$_k3s_tmpl") => $(LastN 3 '/' "$_k3s_dst")"
}
export _k3sConvertTmpl
readonly _k3sConvertTmpl

k3sConvertTmpl(){
  Usage $# -eq 1 'k3sConvertTmpl <dir>'
  local _k3s_tmpl
  for _k3s_tmpl in "$1"/*.tmpl; do
    # 必须要判断，当不存在 .tmpl 文件时，_k3s_tmpl 就成为 xxxx/*.tmpl 了
    if [ -f "$_k3s_tmpl" ]; then
      _k3sConvertTmpl "$_k3s_tmpl" "$1/data"
    fi
  done
}
export k3sConvertTmpl
readonly k3sConvertTmpl

# 自动构建
k3sBuild(){
  Usage $# -eq 1 'k3sBuild <dir>'
  local _k3s_workdir="$1"

  Debug "workdir: $_k3s_workdir"

  k3sConvertTmpl "$_k3s_workdir"

  # 虽然构建会自动下载，但是下载有时候会很慢，导致部署流程很慢。安全起见，预先下载
  k8sAutoPullImages "$_k3s_workdir"

  k3sTryApplyGlobal "$_k3s_workdir"

  # global -> namespace -> config -> pvc -> role -> secret -> serv -> service -> web
  k3sTryApply "${_k3s_workdir}/config"
  k3sTryApply "${_k3s_workdir}/pvc"
  k3sTryApply "${_k3s_workdir}/role"
  k3sTryApply "${_k3s_workdir}/secret"

  # up.yaml => $K8S_UP_YAML
  local _k3s_regex='.*/\(global\|namespace\|config\|pvc\|role\|secret\|serv\|service\|up\|web\)\.\(yml\|yaml\)'
  local _k3s_yaml
  find "$_k3s_workdir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) ! -regex "$_k3s_regex" -print0 | while IFS= read -r -d '' _k3s_yaml; do
    k3sTryApply "$_k3s_yaml"
  done
  k3sTryApply "${_k3s_workdir}/serv"
  k3sTryApply "${_k3s_workdir}/service"
  k3sTryApply "${_k3s_workdir}/web"
}
export k3sBuild
readonly k3sBuild

# 移除安装，但是保留 pvc、 namespace、tls secret
k3sDown(){
  Usage $# -ge 1 'k3sDown <dir> [mute]'
  local _k3s_workdir="$1"
  local _k3s_mute="${2:-}"
  Info "delete $_k3s_workdir $_k3s_mute"

  local _k3s_d
  _k3s_d="$(LastN 2 '/' "$_k3s_workdir")"
  local _k3s_regex='.*/\(global\|namespace\|pvc\)\.\(yml\|yaml\)'
  local _k3s_yaml

  find "$_k3s_workdir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) ! -regex "$_k3s_regex" -print0 | while IFS= read -r -d '' _k3s_yaml; do
    k3sTryDelete "$_k3s_yaml"
  done


  if [ -z "$_k3s_mute" ]; then
    local _k3s_en
    local _k3s_cn
    _k3s_en='global, pvc and namespace were not deleted. Use purge  or destroy for complete cleanup'
    _k3s_cn='global, pvc and namespace 被保留下来，删除需使用 purge或 destroy 指令'
    NoticeD "$_k3s_en" "$_k3s_cn"
  fi

  k8sRmiNoneImages
}
export k3sDown
readonly k3sDown

k3sTryDeletePV(){
  Usage $# -eq 3 'k3sTryDeletePV <namespace> <serv> <selector>'
  local _k3s_namespace="$1"
  local _k3s_serv="${2#statefulset/}"     # 移除 statefulset/ 开头
  local _k3s_selector="$3"

  if k3s kubectl get statefulset "$_k3s_serv" -n "$_k3s_namespace" &>/dev/null; then
    Debug "k3s kubectl delete statefulset $_k3s_serv --cascade=orphan -n $_k3s_namespace"
    k3s kubectl delete statefulset "$_k3s_serv" --cascade=orphan -n "$_k3s_namespace" >/dev/null 2>&1 || true
  fi
  if k3s kubectl get pvc -l "$_k3s_selector" -n "$_k3s_namespace" --no-headers 2>/dev/null | grep -q .; then
    Debug "k3s kubectl delete pvc -l $_k3s_selector -n $_k3s_namespace"
    k3s kubectl delete pvc -l "$_k3s_selector" -n "$_k3s_namespace" --ignore-not-found=true
  fi
  local _k3s_counter=0
  local _k3s_timeout=60

  while [ $_k3s_counter -lt $_k3s_timeout ]; do
    if ! k3s kubectl get pvc -l "$_k3s_selector" -n "$_k3s_namespace" --no-headers >/dev/null 2>&1; then
      break
    fi
    _k3s_counter=$((_k3s_counter + 2))
    sleep 2
  done

  Debug 'k3s kubectl get pv'
  k3s kubectl get pv
}
export k3sTryDeletePV
readonly k3sTryDeletePV

# down + 移除 PVC
k3sPurge(){
  Usage $# -eq 4 'k3sPurge <dir> <namespace> <serv> <selector>'
  local _k3s_workdir="$1"
  local _k3s_namespace="$2"
  local _k3s_serv="$3"
  local _k3s_selector="$4"

  local _k3s_d
  _k3s_d="$(LastN 2 '/' "$_k3s_workdir")"
  local _k3s_confirm
  _k3s_confirm="$(Dict "[DANGEROUS] delete pvc ($_k3s_d)?" "[危险] 确定删除 PVC ($_k3s_d)？")"
  if ! Confirm "$_k3s_confirm"; then return 0; fi

  k3sDown "$_k3s_workdir" mute
  k3sTryDelete "$_k3s_workdir/pvc"

  if StrIn 'statefulset/' "$_k3s_serv"; then
    k3sTryDeletePV "$_k3s_namespace" "$_k3s_serv" "$_k3s_selector"
  fi

  local _k3s_en
  local _k3s_cn
  _k3s_en='global and namespace were not deleted. Use destroy (k3sDestroy) for complete cleanup'
  _k3s_cn='global 和 namespace 通常与其他服务共享，删除需使用 destroy (k3sDestroy) 指令'
  NoticeD "$_k3s_en" "$_k3s_cn"
}
export k3sPurge
readonly k3sPurge

k3sDestroy(){
  local _k3s_namespace="$1"
  local _k3s_confirm_en="[DANGEROUS] destroy all services/pods/containers with namespace $_k3s_namespace?"
  local _k3s_confirm_cn="[危险] namespace $_k3s_namespace 可能包含其他服务，确定销毁该namespace下所有 services/pods/containers？"
  if ! ConfirmD "$_k3s_confirm_en" "$_k3s_confirm_cn"; then
    return 0
  fi
  Warn "kubectl delete namespace $_k3s_namespace"
  $SUDO k3s kubectl delete namespace "$_k3s_namespace" -v=6
}
export k3sDestroy
readonly k3sDestroy

# 进入正在运行的容器
k3sNsenter(){
  Usage $# -ge 2 'k3sNsenter <namespace> <selector> [container] [command=sh] [command args]... '
  local _k3s_namespace="$1"
  local _k3s_selector="$2"
  local _k3s_container="${3:-}"
  local _k3s_ns_cmd="${4:-"sh"}"

  shift 4 2>/dev/null || shift $#
  local _k3s_ns_args=("$@")

  local _k3s_pod
  _k3s_pod=$(k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector" -o jsonpath='{.items[0].metadata.name}')
  if [ -z "$_k3s_pod" ]; then
    return 1
  fi
  local _k3s_args=(-it "$_k3s_pod" -n "$_k3s_namespace")
  if [ -n "$_k3s_container" ]; then
    _k3s_args+=(-c "$_k3s_container")
  fi

  if [ "$_k3s_ns_cmd" != 'sh' ]; then
    # shellcheck disable=SC2086    # 不要加引号
    k3s kubectl exec "${_k3s_args[@]}" -- $_k3s_ns_cmd "${_k3s_ns_args[@]}"
    return $?
  fi

  # 优先使用 /bin/bash
  if k3s kubectl exec "${_k3s_args[@]}" -- /bin/bash -i 2>/dev/null; then
    return 0
  fi

  # fallback to run /bin/sh
  k3s kubectl exec "${_k3s_args[@]}" -- /bin/sh -i
}
export k3sNsenter
readonly k3sNsenter

k3sDetectNamespace(){
  Usage $# 1 2 'k3sDetectNamespace <workdir> [with_panic=]'
  local _k3s_workdir="$1"
  local _k3s_with_panic="${2:-}"
  local _k3s_ns

  _k3s_ns="$(k3sDetectNamespaceYaml "$_k3s_workdir" 2>/dev/null || true)"
  declare _k3s_namespace
  if [ -n "$_k3s_ns" ]; then
    _k3s_namespace="$(kubectl apply -f "$_k3s_ns" --dry-run=client -o jsonpath='{range .items[?(@.kind=="Namespace")]}{.metadata.name}{end}' 2>/dev/null || true)"
    if [ -n "$_k3s_namespace" ]; then
      printf '%s' "$_k3s_namespace"
      return 0
    fi
  fi

  for _k3s_yaml in "$_k3s_workdir"/*.yaml "$_k3s_workdir"/*.yml; do
    [ -f "$_k3s_yaml" ] || continue
    if [ -n "$K8S_UP_YAML" ] && [ "$(basename "$_k3s_yaml")" = "$K8S_UP_YAML" ]; then
      continue
    fi

    _k3s_namespace="$(kubectl apply -f "$_k3s_yaml" --dry-run=client -o jsonpath='{.metadata.namespace}' 2>/dev/null || true)"
    if [ -n "$_k3s_namespace" ]; then
      printf '%s' "$_k3s_namespace"
      return 0
    fi
  done

  if [ "$_k3s_with_panic" = "WITH_PANIC" ] || [ "$_k3s_with_panic" = "$WITH_PANIC" ]; then
    PanicD "No namespace detected. No namespace.yaml or global.yaml found in nearby $_k3s_workdir."   \
            "没有检测到 namespace。没有检测到${_k3s_workdir}相近目录的namespace.yaml 或 global.yaml"
  fi
}
export k3sDetectNamespace
readonly k3sDetectNamespace

_k3s_cmd_list(){
  local _k3s_here
  _k3s_here=$(basename "$1")
  local _k3s_sub_cmd="$2"
  local _k3s_h
  _k3s_h="$(ToPlaceholder "$_k3s_here")"
  local _k3s_here_n
  _k3s_here_n=${#_k3s_here}
  local _k3s_u1="Usage: $_k3s_here build|rebuild|status|restart|delete|purge"
  local _k3s_u2="       $_k3s_h ns|nsenter [command=$_k3s_sub_cmd]"
  local _k3s_n
  _k3s_n=$(Max "${#_k3s_u1}" "${#_k3s_u2}")
  local _k3s_u1_p
  local _k3s_u2_p
  _k3s_u1_p=$(StrRepeat $((_k3s_n - ${#_k3s_u1})))
  _k3s_u2_p=$(StrRepeat $((_k3s_n - ${#_k3s_u2})))

  local _k3s_cmd_n
  _k3s_cmd_n=${#_k3s_sub_cmd}
  local _k3s_ap
  _k3s_ap=$(StrRepeat "$_k3s_n" '-')
  local _k3s_c
  _k3s_c=$(ToPlaceholder "$_k3s_n")
  local _k3s_a="----${_k3s_ap}"
  echo "+${_k3s_a}+"
  printf "|  ${_CYAN_}%s${_NC_}  %s|\n" "$_k3s_u1" "$_k3s_u1_p"
  printf "|  ${_CYAN_}%s${_NC_}  %s|\n" "$_k3s_u2" "$_k3s_u2_p"
  printf "|  ${_CYAN_}       %s pull <name|image> [source]${_NC_}               %s|\n" "$_k3s_h" "$_k3s_c"
  printf "|  ${_CYAN_}       %s logs [container name]${_NC_}                    %s|\n" "$_k3s_h" "$_k3s_c"
  printf "|  ${_CYAN_}       %s curl [flag] <cluster_url>${_NC_}                %s|\n" "$_k3s_h" "$_k3s_c"
  printf "|  ${_CYAN_}       %s run <td> [command=/bin/sh]${_NC_}            %s|\n" "$_k3s_h" "$_k3s_c"
  echo "+${_k3s_a}+"
  echo "|  E.g. : $_k3s_here ns|nsenter sh                            $_k3s_c|"
  echo "|         $_k3s_h pull redis:mirror visible                $_k3s_c|"
  echo "|         $_k3s_h pull redis:latest docker.io              $_k3s_c|"
  echo "|         $_k3s_h pull docker.io/rancher/mirrored-pause    $_k3s_c|"
  echo "|         $_k3s_h curl http://cluster.local:15672/api      $_k3s_c|"
  echo "+${_k3s_a}+"
}

k3sUp(){
  Usage $# 3 4 'k3sUp <dir> <selector> <container> [namespace=auto detect]'
  local _k3s_workdir="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"
  local _k3s_namespace="${4:-}"

  if [ -z "$_k3s_namespace" ]; then
    _k3s_namespace=$(k3sDetectNamespace "$_k3s_workdir" WITH_PANIC)
  fi

  k3sBuild "$_k3s_workdir"
  k3sWaitReady "$_k3s_namespace" "$_k3s_selector" "$_k3s_container"
}
export k3sUp
readonly k3sUp

_k3s_rebuild(){
  local _k3s_workdir="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"
  k3sDown "$_k3s_workdir"
  k3sUp "$_k3s_workdir"  "$_k3s_selector" "$_k3s_container"
}

k3sErrorLog(){
  Debug "$SUDO journalctl -u k3s | grep error | tail -10"
  $SUDO journalctl -u k3s | grep error | tail -10
}
export k3sErrorLog
readonly k3sErrorLog

k3sLogs(){
  Usage $# 3 4 'k3sLogs <namespace> <selector> <container_name> [container|pod]'
  local _k3s_namespace="$1"
  local _k3s_selector="$2"
  local _k3s_container_name="$3"
  local _k3s_id="${4:-}"

  if [ -z "$_k3s_id" ]; then
    Debug "kubectl logs -n $_k3s_namespace -l $_k3s_selector -f"
    if $SUDO k3s kubectl logs -n "$_k3s_namespace" -l "$_k3s_selector"; then
      local _k3s_err
      _k3s_err=$($SUDO k3s kubectl logs -n "$_k3s_namespace" -l "$_k3s_selector" 2>&1)
      if [ "$_k3s_err" != "No resources found in $_k3s_namespace namespace." ]; then
        return 0
      fi
      k3sErrorLog
    fi

    _k3s_id=$($SUDO k3s crictl ps -a --name "$_k3s_container_name" --quiet)
    if [ -n "$_k3s_id" ]; then
      Debug "crictl logs $_k3s_id (container name: $_k3s_container_name)"
      if $SUDO k3s crictl logs "$_k3s_id" 2>/dev/null; then
        return 0
      fi
    fi
    Error "container $_k3s_container_name is dead"
    local _k3s_pod
    _k3s_pod=$(k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector" -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$_k3s_pod" ]; then
      Debug "try: kubectl describe pod -n $_k3s_namespace -l $_k3s_selector"
      k3sErrorLog
      return 1
    fi
    Debug "kubectl describe pod $_k3s_pod -n $_k3s_namespace"
    $SUDO k3s kubectl describe pod "$_k3s_pod" -n "$_k3s_namespace"
    local _k3s_error
    _k3s_error="$($SUDO k3s kubectl describe pod "$_k3s_pod" -n "$_k3s_namespace" | grep -Ei "Error|Failed|Warning" )"
    if [ -n "$_k3s_error" ]; then echo ''; Panic "${_k3s_error}"; fi

  elif [ "$_k3s_id" = 'pod' ]; then
    Debug "k3s kubectl describe pod -n $_k3s_namespace -l $_k3s_selector"
    $SUDO k3s kubectl describe pod -n "$_k3s_namespace" -l "$_k3s_selector"
  else
    Debug "crictl logs $_k3s_id"
    $SUDO k3s crictl logs "$_k3s_id"   # 失败容器重启，名称会变
  fi
}
export k3sLogs
readonly k3sLogs

k3sRestart(){
  Usage $# -eq 2 'k3sRestart <namespace> <set>'
  local _k3s_namespace="$1"
  local _k3s_serv="$2"
  Debug "kubectl rollout restart $_k3s_serv -n $_k3s_namespace"
  $SUDO k3s kubectl rollout restart "$_k3s_serv" -n "$_k3s_namespace"
}
export k3sRestart
readonly k3sRestart

k3sDeleteTestPod(){
  Usage $# -le 1 'k3sDeleteTestPod [namespace]'
  local _k3s_namespace="${1:-}"

  if [ -n "$_k3s_namespace" ]; then
    if [ -n "$($SUDO k3s kubectl get pod "$K8S_TEST_POD" -n "$_k3s_namespace" --ignore-not-found -o name)" ]; then
      Debug "kubectl delete pod $K8S_TEST_POD -n $_k3s_namespace --ignore-not-found"
      $SUDO k3s kubectl delete pod "$K8S_TEST_POD" -n "$_k3s_namespace" --ignore-not-found
    fi
  fi

  if [ -n "$($SUDO k3s kubectl get pod "$K8S_TEST_POD" --ignore-not-found -o name)" ]; then
    Debug "kubectl delete pod $K8S_TEST_POD --ignore-not-found"
    $SUDO k3s kubectl delete pod "$K8S_TEST_POD" --ignore-not-found
  fi
}
export k3sDeleteTestPod
readonly k3sDeleteTestPod

k3sTestRun(){
  Usage $# 1 4 'k3sTestRun <image> [interact|bash] [namespace]  [bash=/bin/sh]'
  local _k3s_image="$1"
  local _k3s_interact="${2:-}"
  local _k3s_namespace="${3:-}"
  local _k3s_bash=${4:-/bin/sh}

  if [ "$_k3s_interact" == '/bin/bash' ] || [ "$_k3s_interact" == '/bin/sh' ]; then
    _k3s_bash="$_k3s_interact"
    _k3s_interact=''
  fi

  k3sDeleteTestPod "$_k3s_namespace"

  local _k3s_ns=''
  if [ -n "$_k3s_namespace" ]; then
    _k3s_ns="-n $_k3s_namespace"
  fi

  # --rm -it 需要交互，因此不适合脚本。但是输出的时候，方便复制后交互操作
  HeadingD '[Run below:]' '[依次运行下面：]'
  Highlight "  1. sudo kubectl run $K8S_TEST_POD ${_k3s_ns} --image=$_k3s_image --restart=Never --rm -it -- $_k3s_bash"
  if [ -n "$_k3s_interact" ]; then Highlight "  2. $_k3s_interact"; fi
}
export k3sTestRun
readonly k3sTestRun

# 1. 同命名空间访问    curl http://<service_name>:15672/api/overview
# 2. 跨命名空间访问    curl http://<service_name>.<namespace>:15672/api/overview
# 3. 全限定域名访问    curl http://<service_name>.<namespace>.svc.cluster.local:15672/api/overview
k3sCurl(){
  local _k3s_flag=''
  local _k3s_url=""
  local _k3s_namespace=''

  case $# in
    1) _k3s_url="$1" ;;                 # k3sCurl <url>
    2)
      if [ -z "$1" ]; then
        _k3s_url="$2"               # k3sCurl '' <url>
      elif [ -z "$2" ]; then
        _k3s_url="$1"               # k3sCurl <url> ''
      elif [ "${1:0:1}" = '-' ]; then
        _k3s_flag="$1"              # k3sCurl <flag> <url>
        _k3s_url="$2"
      else
        _k3s_url="$1"               # k3sCurl <url> <namespace>
        _k3s_namespace="$2"
      fi
      ;;
    3)
      _k3s_flag="$1"                  # k3sCurl <flag> <url> <namespace>
      _k3s_url="$2"
      _k3s_namespace="$3"
      ;;
    *)
      PanicUsage 'k3sCurl [flag] <cluster_url> [namespace]'
      ;;
  esac

  k3sTestRun 'curlimages/curl' "curl $_k3s_flag $_k3s_url" "$_k3s_namespace"
}
export k3sCurl
readonly k3sCurl


k3sCreateTlsSecret(){
  Usage $# 9 11 "k3sCreateTlsSecret <namespace> <dir> <secret_name> <common_name> <cert_dir> <tls_san> <tls_sub> <privkey_filename=$CERT_KEY_FILE> <cert_filename=$CERT_FILE> [cert_days=$CERT_CSR_FILE] [generate_leaf_cert_if_nx=0]"
  _k3s_namespace="$1"
  _k3s_workdir="$2"
  _k3s_secret="$3"
  _k3s_common_name="$4"
  _k3s_cert_dir="$5"
  _k3s_tls_san="$6"
  _k3s_tls_sub="$7"
  _k3s_privkey_filename="${8:-"$CERT_KEY_FILE"}"
  _k3s_cert_filename="${9:-"$CERT_FILE"}"
  _k3s_cert_days=${10:-"$CERT_CSR_FILE"}
  _k3s_generate_leaf_cert_if_nx=${11:-0}

  k3sTryApplyGlobal "$_k3s_workdir"
  Info "cert dir: $_k3s_cert_dir"
  if [ ! -f "$_k3s_cert_dir/$_k3s_cert_filename" ]; then
    if ! Yes "$_k3s_generate_leaf_cert_if_nx"; then
      ErrorD "missing cert files in $_k3s_cert_dir" "$_k3s_cert_dir 文件夹下缺少证书文件"
      return 1
    fi

    Info "GenerateLeafCert $_k3s_common_name $_k3s_cert_dir $_k3s_tls_san $_k3s_tls_sub $_k3s_privkey_filename $_k3s_cert_filename $_k3s_cert_days"
    if ! GenerateLeafCert "$_k3s_common_name" "$_k3s_cert_dir" "$_k3s_tls_san" "$_k3s_tls_sub" "$_k3s_privkey_filename" "$_k3s_cert_filename" "$_k3s_cert_days" >/dev/null 2>&1; then
      ErrorD "create leaf certificate failed" "创建自签名证书失败"
      return 1
    fi
  fi
  local _k3s_privkey="$_k3s_cert_dir/$_k3s_privkey_filename"
  local _k3s_cert="$_k3s_cert_dir/$_k3s_cert_filename"
  k8sCreateTlsSecret "$_k3s_namespace" "$_k3s_secret" "$_k3s_privkey" "$_k3s_cert"
}
export k3sCreateTlsSecret
readonly k3sCreateTlsSecret

k3sDeleteSecret(){
  Usage $# -eq 2 'k3sDeleteSecret <namespace> <service>'
  _k3s_ns="$1"
  _k3s_service="$2"
  if $SUDO k3s kubectl get secret "$_k3s_service" -n "$_k3s_ns" >/dev/null 2>&1; then
    Debug "k3s kubectl delete secret $_k3s_service -n $_k3s_ns --ignore-not-found=true"
    $SUDO k3s kubectl delete secret "$_k3s_service" -n "$_k3s_ns" --ignore-not-found=true
  fi
}
export k3sDeleteSecret
readonly k3sDeleteSecret
