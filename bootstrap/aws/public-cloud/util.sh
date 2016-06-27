#!/bin/bash

# Use the config file specified in $KUBEFORM_CONFIG_FILE, or default to
# config-default.sh.

ansible_ssh_config() {
  pushd "${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}"
    cat <<EOF > ssh.config
  Host *
    StrictHostKeyChecking  no
    ServerAliveInterval    120
    ControlMaster          auto
    ControlPath            ~/.ssh/mux-%r@%h:%p
    ControlPersist         30m
    User                   core
    UserKnownHostsFile     /dev/null
EOF
  popd
}

get_master_url() {
  local KUBEFORM_kube_apiserver_vip=''

  pushd "${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}" > /dev/null
    KUBEFORM_kube_apiserver_vip="terraform output master_elb_hostname"
  popd > /dev/null

  echo "${KUBEFORM_kube_apiserver_vip}"
}

kubeform_down() {
  pushd "${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}"
    terraform destroy -var "access_key=${TF_VAR_access_key}" \
      -var "secret_key=${TF_VAR_secret_key}" \
      -var "region=${TF_VAR_region}"
    > ${TF_VAR_etcd_discovery_url_file:-etcd_discovery_url.txt}
  popd
}

