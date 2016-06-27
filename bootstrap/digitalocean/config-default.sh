#!/bin/bash

export TF_VAR_region=${TF_VAR_region:-lon1}
export TF_VAR_do_token=${TF_VAR_do_token:?"Need to set TF_VAR_do_token non-empty"}

export ANSIBLE_SSH_ARGS="-F ${APOLLO_ROOT}/terraform/${KUBEFORM_PROVIDER}/ssh.config -i ${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}/id_rsa -q"
export APOLLO_ansible_ssh_user=core
