#!/bin/bash

export TF_VAR_access_key=${TF_VAR_access_key:?"Need to set TF_VAR_access_key non-empty"}
export TF_VAR_secret_key=${TF_VAR_secret_key:?"Need to set TF_VAR_secret_key non-empty"}

export ANSIBLE_SSH_ARGS="-F ${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}/ssh.config -q"
export TF_VAR_region=${TF_VAR_region:-eu-west-1}
export KUBEFORM_ansible_ssh_user=core
