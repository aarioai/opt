#!/bin/bash
set -euo pipefail

# Require: nerdctl + helm

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-yq.sh" ]; then . ../../aa/lib/aa-posix-yq.sh; else . /opt/aa/lib/aa-posix-yq.sh; fi

export K8S_TEST_POD
readonly K8S_TEST_POD='aa-temp-test'

export K8S_ENV_YAML
readonly K8S_ENV_YAML='._env.yaml'

export K8S_GLOBAL_YAML
readonly K8S_GLOBAL_YAML='global.yaml'



k8sRmiNoneImages(){
  Debug "nerdctl image prune -f $*"
  $SUDO nerdctl image prune -f "$@"
}
export k8sRmiNoneImages
readonly k8sRmiNoneImages