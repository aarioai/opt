#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-lib.sh" ]; then . ../../aa/lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

K8S_TEST_POD='run-test'
export K8S_TEST_POD
readonly K8S_TEST_POD



k8sCreateTLS(){
  local _k8s_usage
  _k8s_usage=$(cat << EOF
k8sCreateTLS <namespace> <service_name> <domain> <subj> <alt> [expire_days=365] [save_to=/etc/cert/<domain>]
Example:
    k8sCreateTLS dev-infra authelia-tls 'authn.x.x' '/C=CN/ST=Beijing/L=Beijing/O=LAN/CN=authn.x.x' 'DNS:authn.x.x,IP:192.168.0.250,IP:127.0.0.1' 30
    k8sCreateTLS dev-infra authelia-tls 'authn.x.x' '/C=CN/ST=Beijing/L=Beijing/O=LAN/CN=authn.x.x' 'DNS:authn.x.x,DNS:authn.com,IP:192.168.0.250,IP:127.0.0.1'
EOF
)
  Usage $# 5 7 "$_k8s_usage"
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_domain="$3"
  local _k8s_subj="$4"
  local _k8s_alt="$5"
  local _k8s_expire_days="${6:-365}"
  local _k8s_dir="${7:-"/etc/cert/$_k8s_domain"}"

  if ! IsInt "$_k8s_expire_days"; then PanicUsage "$_k8s_usage"; fi

  ChmodOrMkdir 755 "$_k8s_dir"            # 进入目录，需要 x 权限

  local _k8s_content="${_k8s_subj}${TAB4}${_k8s_alt}"
  local _k8s_today
  _k8s_today=$(date +'%Y-%m-%d')
  local _k8s_expire="$_k8s_today + $_k8s_expire_days days"        # date -d "$_k8s_expire" +%Y-%m-%d

  if [ ! -d "$_k8s_dir" ]; then
    # 生成自签名证书（支持 IP 和域名）
    Info "sudo openssl req -x509 -nodes -days $_k8s_expire_days -newkey rsa:2048  -keyout $_k8s_dir/privkey.pem -out $_k8s_dir/fullchain.pem -subj $_k8s_subj -addext subjectAltName=$_k8s_alt"
    if ! sudo openssl req -x509 -nodes -days "$_k8s_expire_days" -newkey rsa:2048 \
      -keyout "$_k8s_dir/privkey.pem" -out "$_k8s_dir/fullchain.pem" \
      -subj "$_k8s_subj" -addext "subjectAltName=$_k8s_alt" >/dev/null; then
      PanicD "Generate $_k8s_domain TLS certs failed" "生成 $_k8s_domain 的TLS证书失败"
    fi

    sudo chmod 644 "$_k8s_dir"/*

    # 验证 crt
    Info "sudo openssl x509 -in $_k8s_dir/fullchain.pem -text -noout"
    if ! sudo openssl x509 -in "$_k8s_dir/fullchain.pem" -text -noout >/dev/null; then
      sudo rm -rf "$_k8s_dir"
      PanicD "Verify $_k8s_domain TLS certs failed" "验证 $_k8s_domain 的TLS证书失败"
    fi

    echo "$_k8s_content" | sudo tee "${_k8s_dir}/content.txt" > /dev/null
    echo "$_k8s_expire" | sudo tee "${_k8s_dir}/expire.txt" > /dev/null
    echo "$(Now)${TAB4}${_k8s_content}${TAB4}+${_k8s_expire_days} days" | sudo tee "${_k8s_dir}/change.log" > /dev/null
    sudo chmod 644 "$_k8s_dir"/*
  else
    Notice "available tls certs already exist in $_k8s_dir"
  fi

  privkey_file=$(DetectPrivateKeyPemFile "$_k8s_dir")
  cert_file=$(DetectCertPemFile "$_k8s_dir")

  if [ ! -f "$privkey_file" ] && [ ! -f "$cert_file" ]; then
    ls -al "$_k8s_dir"
    PanicD "no detected private key file or cert file in $_k8s_dir" "${_k8s_dir}目录里没有检测到私钥或证书文件"
  fi

  # 创建 Kubernetes TLS Secret
  sudo kubectl create secret tls "$_k8s_service" -n "$_k8s_namespace" --cert="$_k8s_dir/fullchain.pem" --key="$_k8s_dir/privkey.pem"

  # 验证 Secret
  Info "sudo kubectl get secret $_k8s_service -n $_k8s_namespace -o yaml"
  if ! sudo kubectl get secret "$_k8s_service" -n "$_k8s_namespace" -o yaml >/dev/null; then
    PanicD "Verify $_k8s_domain kubectl secret failed" "验证 $_k8s_domain kubectl secret 失败"
  fi
}
export createTLS
readonly createTLS

k8sCreateBeijingTLS(){
  local _k8s_usage
  _k8s_usage=$(cat << EOF
k8sCreateBeijingTLS <namespace> <service_name> <domain> <alt> [expire_days=365]
Example:
    k8sCreateBeijingTLS dev-infra authelia-tls 'authn.x.x' 'DNS:authn.x.x,IP:192.168.0.250,IP:127.0.0.1' 30
    k8sCreateBeijingTLS dev-infra authelia-tls 'authn.x.x' 'DNS:authn.x.x,DNS:authn.com,IP:192.168.0.250,IP:127.0.0.1'
EOF
)
  Usage $# 4 5 "$_k8s_usage"
  local _k8s_namespace="$1"
  local _k8s_service="$2"
  local _k8s_domain="$3"
  local _k8s_alt="$4"
  local _k8s_expire_days="${5:-365}"

  k8sCreateTLS "$_k8s_namespace" "$_k8s_service" "$_k8s_domain" "/C=CN/ST=Beijing/L=Beijing/O=LAN/CN=$_k8s_domain" "$_k8s_alt" "$_k8s_expire_days"
}
export k8sCreateBeijingTLS
readonly k8sCreateBeijingTLS

k8sRmiNoneImages(){
  Info "sudo nerdctl image prune -f"
  sudo nerdctl image prune -f
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages