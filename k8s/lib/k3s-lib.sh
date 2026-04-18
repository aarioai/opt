#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./k8s-lib.sh" ]; then . ./k8s-lib.sh; else . /opt/k8s/lib/k8s-lib.sh; fi

export REGISTRIES_YAML
readonly REGISTRIES_YAML='/etc/rancher/k3s/registries.yaml'

K3S_NAMESPACE=${K3S_NAMESPACE:-}

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
    sudo cp -f "$_k3s_file" "${_k3s_file}.bak"
    sudo rm -f "$_k3s_file"
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
  sudo chmod 644 "$_k3s_file"
  Info "kubeconfig $_k3s_file generated"
}
export k8sGenerateKubeconfig
readonly k8sGenerateKubeconfig

# 删除所有未使用的<none>镜像
k3sRmiNoneImages(){
  Info "rmi <non> images"
  local _k3s_unused_images
  _k3s_unused_images=$(sudo k3s crictl images | grep '<none>' | awk '{print $3}')
  local image
  for image in $_k3s_unused_images; do
    # 检查是否有容器使用这个镜像
    if ! sudo k3s crictl ps -q | xargs -r sudo k3s crictl inspect 2>/dev/null | grep -q "$image"; then
      Info "sudo k3s crictl rmi $image"
      sudo k3s crictl rmi "$image" 2>/dev/null || true
    fi
  done
}
export k3sRmiNoneImages
readonly k3sRmiNoneImages

_k3sPull(){
  local _k3s_image="$1"

  if [ -f "$REGISTRIES_YAML" ] && Install yq; then
    case "$_k3s_image" in
      "$K8S_ALIYUN_HOST"/*)
        local _k3s_username
        local _k3s_password
        _k3s_username=$(yq -e -r ".configs.\"$K8S_ALIYUN_HOST\".auth.username" "$REGISTRIES_YAML")
        _k3s_password=$(yq -e -r ".configs.\"$K8S_ALIYUN_HOST\".auth.password" "$REGISTRIES_YAML")
        if [ -n "$_k3s_username" ] && [ -n "$_k3s_password" ]; then
          Info "sudo k3s ctr images pull --print-chainid --local --user $_k3s_username:<password> $_k3s_image"
          if k3s ctr images pull --print-chainid --local --user "$_k3s_username:$_k3s_password" "$_k3s_image"; then
            return 0
          fi
        fi
      ;;
    esac
  fi

  Info "sudo k3s crictl pull $_k3s_image"
  local _k3s_hightlight_en
  local _k3s_hightlight_cn
  _k3s_hightlight_en="Slow? Try:${LF}${TAB4}k3s ctr images pull --print-chainid --local --user <username>:<password> $_k3s_image"
  _k3s_hightlight_cn="拉取慢？手动拉更快：${LF}${TAB4}k3s ctr images pull --print-chainid --local --user <username>:<password> $_k3s_image"
  HighlightD "$_k3s_hightlight_en" "$_k3s_hightlight_cn"
  sudo k3s crictl pull "$_k3s_image"
}
export _k3sPull
readonly _k3sPull

k3sPullImage(){
  local _k3s_pullimage_usage
  _k3s_pullimage_usage=$(cat << EOF
k3sPullImage <name|image> [source=docker.io|natived|coff|worked]
Example:
  k3sPullImage docker.io/library/redis:latest
  k3sPullImage redis:latest                   ==>  docker.io/library/redis:latest
  k3sPullImage rancher/mirrored-pause:3.6     ==>  docker.io/rancher/mirrored-pause:3.6
  k3sPullImage redis:mirror natived           ==>  $K8S_ALIYUN_HOST/natived/redis:mirror
EOF
)
  Usage $# 1 2 "$_k3s_pullimage_usage"
  local _k3s_image="$1"
  local _k3s_source="${2:-docker.io}"

  if [ -z "$_k3s_image" ] || WordIn "$_k3s_image" '-h -help --help'; then
    PanicUsage "$_k3s_pullimage_usage"
  fi

  case "$_k3s_source" in
    -h|-help|--help) PanicUsage "$_k3s_pullimage_usage" ;;
    'docker.io') _k3sPull "$_k3s_image" ;;
    *) _k3sPull "$K8S_ALIYUN_HOST/$_k3s_source/$_k3s_image" ;;
  esac
}
export k3sPullImage
readonly k3sPullImage

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
    PVC_STATUS=$(kubectl get pvc "$_k3s_name" -n "$_k3s_namespace" -o jsonpath='{.status.phase}' 2> /dev/null || true || echo "Pending")
    if [ "$PVC_STATUS" = "Bound" ]; then
      ok=1
      break
    fi
    Debug "binding PVC (${_k3s_name} @${_k3s_namespace})... ($i/30)"
    sleep 2
  done

  if [ "$ok" -eq 0 ]; then
    sudo k3s kubectl describe pvc "$_k3s_name" -n "$_k3s_namespace"
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

  Heading "[SERVICE] sudo k3s kubectl get service -n $_k3s_namespace -l $_k3s_selector -o wide"
  sudo k3s kubectl get service -n "$_k3s_namespace" -l "$_k3s_selector" -o wide

  Heading "[POD] sudo kubectl get pods -n $_k3s_namespace -l $_k3s_selector"
  sudo k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector"

  Heading "[CONTAINER] sudo k3s crictl ps -a --name $_k3s_container"
  sudo k3s crictl ps -a --name "$_k3s_container"
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
#    Heading "[INGRESS] sudo k3s kubectl get ingressroute -A -n $_k3s_namespace"
#    sudo k3s kubectl get ingressroute -A -n "$_k3s_namespace"
#  fi

  Heading "[SERVICE] sudo k3s kubectl get service -n $_k3s_namespace -l $_k3s_selector -o wide"
  sudo k3s kubectl get service -n "$_k3s_namespace" -l "$_k3s_selector" -o wide

  Heading "sudo k3s kubectl wait --for=condition=Ready pod -n $_k3s_namespace -l $_k3s_selector --timeout=180s"
  if ! sudo k3s kubectl wait --for=condition=Ready pod -n "$_k3s_namespace" -l "$_k3s_selector" --timeout=180s 2>/dev/null; then
    k3sLogs "$K3S_NAMESPACE" "$_k3s_selector" "$_k3s_container"
    return 1
  fi

  Heading "[POD] sudo kubectl get pods -n $_k3s_namespace -l $_k3s_selector"
  k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector"

  Heading "[CONTAINER] sudo k3s crictl ps -a --name $_k3s_container"
  sudo k3s crictl ps -a --name "$_k3s_container"

#  Heading "[IMAGE] sudo k3s crictl images | grep $_k3s_image"
#  sudo k3s crictl images | grep "$_k3s_image"
}
export k3sWaitReady
readonly k3sWaitReady

k3sDetectGlobalYaml(){
  local _k3s_dir="${1:-.}"
  local _k3s_paths=("${_k3s_dir}" "${_k3s_dir}/.." "${_k3s_dir}/../..")
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
  local _k3s_dir="${1:-.}"
  local _k3s_paths=("${_k3s_dir}" "${_k3s_dir}/.." "${_k3s_dir}/../..")
  local _k3s_path
  for _k3s_path in "${_k3s_paths[@]}"; do
    local _k3s_abs_path
    _k3s_abs_path=$(realpath -e "$_k3s_path" 2>/dev/null || realpath "$_k3s_path")
    local _k3s_ns
    _k3s_ns="$(FindFileByExt "$_k3s_abs_path" namespace yml yaml)"
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
  local _k3s_dir
  local _k3s_base
  local _k3s_yaml
  _k3s_dir="$(dirname "$1")"
  _k3s_base="$(Filename "$1")"
  _k3s_yaml="$(FindFileByExt "$_k3s_dir" "$_k3s_base" yml yaml)"
  if [ ! -f "$_k3s_yaml" ]; then
    return 0
  fi

  Info "sudo k3s kubectl apply -f $(LastN 3 '/' "$_k3s_yaml")"
  sudo k3s kubectl apply -f "$_k3s_yaml"
}
export k3sTryApply
readonly k3sTryApply

k3sTryDelete(){
  Usage $# -eq 1 'k3sTryApply <yml_path>'
  local _k3s_dir
  local _k3s_base
  local _k3s_yaml
  _k3s_dir="$(dirname "$1")"
  _k3s_base="$(Filename "$1")"
  _k3s_yaml="$(FindFileByExt "$_k3s_dir" "$_k3s_base" yml yaml)"
  if [ ! -f "$_k3s_yaml" ]; then
    return 0
  fi

  Install yq

  local _k3s_namespace
  _k3s_namespace="$(yq -e -r '.metadata.namespace' "$_k3s_yaml" | head -1)"
  if [ -z "$_k3s_namespace" ] || [ "$_k3s_namespace" = 'null' ]; then
    Notice "miss matching namespace, using 'default': yq -e -r '.metadata.namespace' $_k3s_yaml | head -1"
    _k3s_namespace='default'
  fi

  Info "sudo k3s kubectl delete -n $_k3s_namespace -f $(LastN 3 '/' "$_k3s_yaml")"
  sudo k3s kubectl delete -n "$_k3s_namespace" -f "$_k3s_yaml" --ignore-not-found=true
}
export k3sTryDelete
readonly k3sTryDelete

k3sPullImageSources(){
  local _k3s_dir="$1"
  local _k3s_yaml
  find "$_k3s_dir" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r _k3s_yaml; do
    local _k3s_image
    _k3s_image="$(kubectl apply -f "$_k3s_yaml" --dry-run=client -o jsonpath="{..containers[*].image}")"
    if [ -n "$_k3s_image" ]; then
      k3sPullImage "$_k3s_image"
    fi
  done
}
export k3sPullImageSources
readonly k3sPullImageSources

k3sTryApplyGlobal(){
  Usage $# -eq 1 'k3sTryApplyGlobal <dir>'
  local _k3s_dir="$1"
  k3sTryApply "$(k3sDetectGlobalYaml "$_k3s_dir")"
  k3sTryApply "$(k3sDetectNamespaceYaml "$_k3s_dir")"
}
export k3sTryApplyGlobal
readonly k3sTryApplyGlobal

_k3sConvertTmpl(){
  Usage $# -eq 2 '_k3sConvertTmpl <tmpl> <data_dir>'
  local _k3s_tmpl="$1"
  PanicIfNotFile "$_k3s_tmpl"

  # 下面 trap 需要用到全局变量，因此不能使用 local
  _k3s_global_tmpl_temp=$(mktemp)
  trap 'rm -f "$_k3s_global_tmpl_temp"' EXIT # 临时文件，退出后自动删除
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
  local _k3s_dir="$1"

  Info "build $_k3s_dir"

  k3sConvertTmpl "$_k3s_dir"

  # 虽然构建会自动下载，但是下载有时候会很慢，导致部署流程很慢。安全起见，预先下载
  k3sPullImageSources "$_k3s_dir"
  k3sTryApplyGlobal "$_k3s_dir"

  # global -> namespace -> config -> pvc -> role -> secret -> serv -> service -> web
  k3sTryApply "${_k3s_dir}/config"
  k3sTryApply "${_k3s_dir}/pvc"
  k3sTryApply "${_k3s_dir}/role"
  k3sTryApply "${_k3s_dir}/secret"

  local _k3s_regex='.*/\(global\|namespace\|config\|pvc\|role\|secret\|serv\|service\|web\)\.\(yml\|yaml\)'
  local _k3s_yaml
  find "$_k3s_dir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) ! -regex "$_k3s_regex" -print0 | while IFS= read -r -d '' _k3s_yaml; do
    k3sTryApply "$_k3s_yaml"
  done
  k3sTryApply "${_k3s_dir}/serv"
  k3sTryApply "${_k3s_dir}/service"
  k3sTryApply "${_k3s_dir}/web"
}
export k3sBuild
readonly k3sBuild

# 移除安装，但是保留 pvc 和 namespace
k3sDelete(){
  Usage $# -ge 1 'k3sDelete <dir> [mute]'
  local _k3s_dir="$1"
  local _k3s_mute="${2:-}"
  Info "delete $_k3s_dir $_k3s_mute"

  local _k3s_d
  _k3s_d="$(LastN 2 '/' "$_k3s_dir")"
  local _k3s_regex='.*/\(global\|namespace\|pvc\)\.\(yml\|yaml\)'
  local _k3s_yaml

  find "$_k3s_dir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) ! -regex "$_k3s_regex" -print0 | while IFS= read -r -d '' _k3s_yaml; do
    k3sTryDelete "$_k3s_yaml"
  done
  if [ -z "$_k3s_mute" ]; then
    local _k3s_en
    local _k3s_cn
    _k3s_en='global, pvc and namespace were not deleted. Use purge (k3sPurge) or destroy (k3sDestroy) for complete cleanup'
    _k3s_cn='global, pvc and namespace 被保留下来，删除需使用 purge (k3sPurge) 或 destroy (k3sDestroy) 指令'
    NoticeD "$_k3s_en" "$_k3s_cn"
  fi
  k3sRmiNoneImages
}
export k3sDelete
readonly k3sDelete

k3sTryDeletePV(){
  Usage $# -eq 3 'k3sTryDeletePV <namespace> <serv> <selector>'
  local _k3s_namespace="$1"
  local _k3s_serv="${2#statefulset/}"     # 移除 statefulset/ 开头
  local _k3s_selector="$3"

  Info "k3s kubectl delete statefulset $_k3s_serv --cascade=orphan -n $_k3s_namespace"
  k3s kubectl delete statefulset "$_k3s_serv" --cascade=orphan -n "$_k3s_namespace" >/dev/null 2>&1 || true

  Info "k3s kubectl delete pvc -l $_k3s_selector -n $_k3s_namespace"
  k3s kubectl delete pvc -l "$_k3s_selector" -n "$_k3s_namespace"

  local _k3s_counter=0
  local _k3s_timeout=60

  while [ $_k3s_counter -lt $_k3s_timeout ]; do
    if ! k3s kubectl get pvc -l "$_k3s_selector" -n "$_k3s_namespace" --no-headers >/dev/null 2>&1; then
      break
    fi
    _k3s_counter=$((_k3s_counter + 2))
    sleep 2
  done

  Info 'k3s kubectl get pv'
  k3s kubectl get pv
}
export k3sTryDeletePV
readonly k3sTryDeletePV

k3sPurge(){
  Usage $# -eq 4 'k3sPurge <dir> <namespace> <serv> <selector>'
  local _k3s_dir="$1"
  local _k3s_namespace="$2"
  local _k3s_serv="$3"
  local _k3s_selector="$4"

  local _k3s_d
  _k3s_d="$(LastN 2 '/' "$_k3s_dir")"
  local _k3s_confirm
  _k3s_confirm="$(Dict "[DANGEROUS] delete pvc ($_k3s_d)?" "[危险] 确定删除 PVC ($_k3s_d)？")"
  if ! Confirm "$_k3s_confirm"; then return 0; fi

  k3sDelete "$_k3s_dir" mute
  k3sTryDelete "$_k3s_dir/pvc"

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
  Warn "sudo k3s kubectl delete namespace $_k3s_namespace"
  sudo k3s kubectl delete namespace "$_k3s_namespace"
}
export k3sDestroy
readonly k3sDestroy

# 进入正在运行的容器
k3sNsenter(){
  Usage $# 4 5 'k3sNsenter <command> <command args> <namespace> <selector> [container]'
  local _k3s_ns_cmd="${1:-sh}"
  local _k3s_ns_args="$2"
  local _k3s_namespace="$3"
  local _k3s_selector="$4"
  local _k3s_container="${5:-}"

  local _k3s_pod
  _k3s_pod=$(sudo k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector" -o jsonpath='{.items[0].metadata.name}')
  if [ -z "$_k3s_pod" ]; then
    return 1
  fi
  local _k3s_args=(-it "$_k3s_pod" -n "$_k3s_namespace")
  if [ -n "$_k3s_container" ]; then
    _k3s_args+=(-c "$_k3s_container")
  fi

  if [ "$_k3s_ns_cmd" != 'sh' ]; then
    # shellcheck disable=SC2086    # 不要加引号
    sudo k3s kubectl exec "${_k3s_args[@]}" -- $_k3s_ns_cmd $_k3s_ns_args
    return 0
  fi

  # 优先使用 /bin/bash
  if sudo k3s kubectl exec "${_k3s_args[@]}" -- /bin/bash 2>/dev/null; then
    return 0
  fi
  sudo k3s kubectl exec "${_k3s_args[@]}" -- /bin/sh
}
export k3sNsenter
readonly k3sNsenter

k3sDetectNamespace(){
  local _k3s_dir="$1"
  local _k3s_ns
  _k3s_ns="$(k3sDetectNamespaceYaml "$_k3s_dir" 2>/dev/null || true)"
  local _k3s_namespace
  if [ -n "$_k3s_ns" ]; then
    _k3s_namespace="$(kubectl apply -f "$_k3s_ns" --dry-run=client -o jsonpath='{range .items[?(@.kind=="Namespace")]}{.metadata.name}{end}')"
    if [ -n "$_k3s_namespace" ]; then
      printf '%s' "$_k3s_namespace"
      return
    fi
  fi

  local _k3s_yaml
  find "$_k3s_dir" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r _k3s_yaml; do
    _k3s_namespace="$(kubectl apply -f "$_k3s_yaml" --dry-run=client -o jsonpath="{.metadata.namespace}")"
    if [ -n "$_k3s_namespace" ]; then
      printf '%s' "$_k3s_namespace"
      return
    fi
  done
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
  echo "|         $_k3s_h pull redis:mirror natived                $_k3s_c|"
  echo "|         $_k3s_h pull redis:latest docker.io              $_k3s_c|"
  echo "|         $_k3s_h pull docker.io/rancher/mirrored-pause    $_k3s_c|"
  echo "|         $_k3s_h curl http://cluster.local:15672/api      $_k3s_c|"
  echo "+${_k3s_a}+"
}

_k3s_build(){
  local _k3s_script="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"
  local _k3s_dir
  _k3s_dir="$(AbsDir "$_k3s_script")"
  k3sBuild "$_k3s_dir"
  k3sWaitReady "$K3S_NAMESPACE"  "$_k3s_selector" "$_k3s_container"
}

_k3s_rebuild(){
  local _k3s_script="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"
  local _k3s_dir
  _k3s_dir="$(AbsDir "$_k3s_script")"
  k3sDelete "$_k3s_dir"
  _k3s_build "$_k3s_script"  "$_k3s_selector" "$_k3s_container"
}

k3sErrorLog(){
  Info 'sudo journalctl -u k3s | grep error | tail -10'
  sudo journalctl -u k3s | grep error | tail -10
}
export k3sErrorLog
readonly k3sErrorLog

k3sLogs(){
  Usage $# 3 4 'k3sLogs <namespace> <selector> <container> [container_id|pod_id]'
  local _k3s_namespace="$1"
  local _k3s_selector="$2"
  local _k3s_container="$3"
  local _k3s_id="${4:-}"

  if [ -z "$_k3s_id" ]; then
    Info "sudo k3s kubectl logs -n $_k3s_namespace -l $_k3s_selector -f"
    if sudo k3s kubectl logs -n "$_k3s_namespace" -l "$_k3s_selector"; then
      local _k3s_err
      _k3s_err=$(sudo k3s kubectl logs -n "$_k3s_namespace" -l "$_k3s_selector" 2>&1)
      Notice "$_k3s_err"
      if [ "$_k3s_err" != "No resources found in $_k3s_namespace namespace." ]; then
        return 0
      fi
      k3sErrorLog
    fi

    _k3s_id=$(sudo k3s crictl ps -a --name "$_k3s_container" --quiet)
    if [ -n "$_k3s_id" ]; then
      Info "sudo k3s crictl logs $_k3s_id"
      if sudo k3s crictl logs "$_k3s_id" 2>/dev/null; then
        return 0
      fi
    fi
    Error "container $_k3s_container is dead"
    local _k3s_pod
    _k3s_pod=$(sudo k3s kubectl get pods -n "$_k3s_namespace" -l "$_k3s_selector" -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$_k3s_pod" ]; then
      Info "try: kubectl describe pod -n $_k3s_namespace -l $_k3s_selector"
      k3sErrorLog
      return 1
    fi
    Info "sudo k3s kubectl describe pod $_k3s_pod -n $_k3s_namespace"
    sudo k3s kubectl describe pod "$_k3s_pod" -n "$_k3s_namespace"
    local _k3s_error
    _k3s_error="$(sudo k3s kubectl describe pod "$_k3s_pod" -n "$_k3s_namespace" | grep -Ei "Error|Failed|Warning" )"
    if [ -n "$_k3s_error" ]; then echo ''; Panic "${_k3s_error}"; fi

  elif [ "$_k3s_id" = 'pod' ]; then
    Info "k3s kubectl describe pod -n $_k3s_namespace -l $_k3s_selector"
    sudo k3s kubectl describe pod -n "$_k3s_namespace" -l "$_k3s_selector"
  else
    Info "sudo k3s crictl logs $_k3s_id"
    sudo k3s crictl logs "$_k3s_id"   # 失败容器重启，名称会变
  fi
}
export k3sLogs
readonly k3sLogs

k3sRestart(){
  Usage $# -eq 2 'k3sRestart <namespace> <set>'
  local _k3s_namespace="$1"
  local _k3s_serv="$2"
  Info "sudo k3s kubectl rollout restart $_k3s_serv -n $_k3s_namespace"
  sudo k3s kubectl rollout restart "$_k3s_serv" -n "$_k3s_namespace"
}
export k3sRestart
readonly k3sRestart

k3sRunIt(){
  Usage $# 1 4 'k3sRunIt <td> [interact|bash] [namespace]  [bash=/bin/sh]'
  local _k3s_image="$1"
  local _k3s_interact="${2:-}"
  local _k3s_namespace="${3:-}"
  local _k3s_bash=${4:-/bin/sh}

  if [ "$_k3s_interact" == '/bin/bash' ] || [ "$_k3s_interact" == '/bin/sh' ]; then
    _k3s_bash="$_k3s_interact"
    _k3s_interact=''
  fi
  k3sPullImage "$_k3s_image"

  local _k3s_ns=''
  if [ -n "$_k3s_namespace" ]; then
    Info "sudo k3s kubectl delete pod $K8S_TEST_POD -n $_k3s_namespace --ignore-not-found"
    sudo k3s kubectl delete pod "$K8S_TEST_POD" -n "$_k3s_namespace" --ignore-not-found
    _k3s_ns="-n $_k3s_namespace"
  else
    sudo k3s kubectl delete pod "$K8S_TEST_POD" --ignore-not-found
  fi

  # --rm -it 需要交互，因此不适合脚本。但是输出的时候，方便复制后交互操作
  HeadingD '[Run below:]' '[依次运行下面：]'
  Highlight "  1. sudo k3s kubectl run $K8S_TEST_POD $_k3s_ns --image=$_k3s_image --restart=Never --rm -it -- $_k3s_bash"
  if [ -n "$_k3s_interact" ]; then Highlight "  2. $_k3s_interact"; fi
}
export k3sRunIt
readonly k3sRunIt

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

  k3sRunIt 'curlimages/curl' "curl $_k3s_flag $_k3s_url" "$_k3s_namespace"
}
export k3sCurl
readonly k3sCurl

k3sCommands(){
  local _k8s_usage
  _k8s_usage=$(cat << EOF
1. k3sCommands <script> <command> <sub command> <sub command arg> <serv> <selector> <container>
2. k3sCommands - <tls_service> <domain> <tls_alt> [expire_days=365]  ==> create tls service
EOF
)
  Usage $# 7 11 "$_k8s_usage"
  local _k3s_script="$1"
  local _k3s_cmd="$2"
  local _k3s_sub_cmd="$3"
  local _k3s_sub_cmd_arg="$4"
  local _k3s_serv="$5"
  local _k3s_selector="$6"
  local _k3s_container="$7"

  # Handling TLS
  local _k3s_with_tls=0
  local _k3s_tls_service=''
  local _k3s_domain=''
  local _k3s_tls_alt=''
  local _k3s_expire_days=''
  if [ $# -gt 7 ]; then
    Usage $# 10 11 "$_k8s_usage"
    _k3s_with_tls=1
    _k3s_tls_service="$8"
    _k3s_domain="$9"
    _k3s_tls_alt="${10}"
    _k3s_expire_days="${11:-365}"
  fi

  local _k3s_dir
  _k3s_dir="$(AbsDir "$_k3s_script")"
  K3S_NAMESPACE="$(k3sDetectNamespace "$_k3s_dir")"
  if [ -z "$K3S_NAMESPACE" ]; then
    PanicD 'no namespace detected' '没有检测到namespace'
  fi
  _k3s_create_tls(){
    if [ "$_k3s_with_tls" -eq 1 ]; then
      k3sTryApplyGlobal "$_k3s_dir"
      k8sCreateBeijingTLS "$K3S_NAMESPACE" "$_k3s_tls_service" "$_k3s_domain" "$_k3s_tls_alt" "$_k3s_expire_days"
    fi
  }
  _k3s_delete_tls(){
    if [ "$_k3s_with_tls" -eq 1 ]; then
      Info "k3s kubectl delete secret $_k3s_tls_service -n $K3S_NAMESPACE"
      k3s kubectl delete secret "$_k3s_tls_service" -n "$K3S_NAMESPACE" --ignore-not-found=true
    fi
  }

  case "$_k3s_cmd" in
    'build')
      _k3s_create_tls
      _k3s_build "$_k3s_script" "$_k3s_selector" "$_k3s_container"
      ;;
    'rebuild')
      _k3s_delete_tls
      _k3s_create_tls
      _k3s_rebuild "$_k3s_script"  "$_k3s_selector" "$_k3s_container"
      ;;
    'status') k3sStatus "$K3S_NAMESPACE" "$_k3s_selector" "$_k3s_container" ;;
    'restart') k3sRestart "$K3S_NAMESPACE" "$_k3s_serv";;
    'delete')
      _k3s_delete_tls
      k3sDelete "$_k3s_dir"
      ;;
    'purge')
      _k3s_delete_tls
      k3sPurge "$_k3s_dir" "$K3S_NAMESPACE" "$_k3s_serv" "$_k3s_selector"
      ;;
    'destroy') k3sDestroy "$K3S_NAMESPACE" ;;
    'ns'|'nsenter') k3sNsenter "$_k3s_sub_cmd" "$_k3s_sub_cmd_arg" "$K3S_NAMESPACE" "$_k3s_selector" "$_k3s_container" ;;
    'logs') k3sLogs "$K3S_NAMESPACE" "$_k3s_selector" "$_k3s_container" "$_k3s_sub_cmd" ;;
    'pull') k3sPullImage "$_k3s_sub_cmd" "$_k3s_sub_cmd_arg" ;;
    'curl') k3sCurl "$_k3s_sub_cmd" "$_k3s_sub_cmd_arg" "$K3S_NAMESPACE" ;;
    'run') k3sRunIt "$_k3s_sub_cmd" "$_k3s_sub_cmd_arg" "$K3S_NAMESPACE" ;;
    *)  _k3s_cmd_list "$0" "$_k3s_sub_cmd";;
  esac
}
export k3sCommands
readonly k3sCommands