#!/bin/bash

# Util functions cloud reusable.
KUBEFORM_ROOT=$(dirname "${BASH_SOURCE}")/..
DEFAULT_CONFIG="${KUBEFORM_ROOT}/bootstrap/${KUBEFORM_PROVIDER}/${KUBEFORM_CONFIG_FILE-"config-default.sh"}"
KUBEFORM_INVENTORY="${KUBEFORM_INVENTORY-inventory}"
KUBEFORM_PLAYBOOK="${KUBEFORM_PLAYBOOK-site.yml}"

if [ -f "${DEFAULT_CONFIG}" ]; then
  source "${DEFAULT_CONFIG}"
fi

verify_prereqs() {
  if [[ "$(which terraform)" == "" ]]; then
    echo -e "${color_red}Can't find terraform in PATH, please fix and retry.${color_norm}"
    exit 1
  fi

  check_terraform_version

  if [[ "$(which ansible-playbook)" == "" ]]; then
    echo -e "${color_red}Can't find ansible-playbook in PATH, please fix and retry.${color_norm}"
    exit 1
  fi
  if [[ "$(which python)" == "" ]]; then
    echo -e "${color_red}Can't find python in PATH, please fix and retry.${color_norm}"
    exit 1
  fi
}

check_terraform_version() {
  local IFS='.'
  local current_version_string="${2:-$( terraform --version | awk 'NR==1 {print $2}' )}"
  local requirement_version_string=${1:-0.6.14}
  local -a current_version=( ${current_version_string#'v'} )
  local -a requirement_version=( ${requirement_version_string} )
  local n diff
  local result=0

  for (( n=0; n<${#requirement_version[@]}; n+=1 )); do
    diff=$((current_version[n]-requirement_version[n]))
    if [ $diff -ne 0 ] ; then
      [ $diff -le 0 ] && result=1 || result=0
      break
    fi

  done

  echo "You are running Terraform ${current_version_string}..."
  if [ $result -eq 1 ]; then
    echo -e "${color_red}Terraform >= ${requirement_version_string} is required, please fix and retry.${color_norm}"
    exit 1
  fi
}

get_kubeform_variables() {
  local plugin_namespace=${1:-"KUBEFORM_"}
  local -a var_list=()
  local IFS=$'\n'

  for env_var in $( env | grep "${plugin_namespace}" ); do
    # This deletes shortest match of $substring from front of $string. ${string#substring}
    var_value=${env_var#${plugin_namespace}}

    var=$( echo "${var_value}" | awk -F = '{ print $1 }' )
    value=${var_value#*=}
    var_list+=( "${var}='${value}'" )
  done
  echo "${var_list[@]}"
}

kubeform_launch() {
  if [ "$@" ]; then
    eval $@
  else
    get_terraform_modules
    terraform_apply
    run_if_exist "ansible_ssh_config"
    ansible_playbook_run
    run_if_exist "set_vpn"
  fi
}

run_if_exist() {
  if [ "$(type -t "${1}")" = function ]; then
    $1
  fi
}

ansible_playbook_run() {
  pushd "${KUBEFORM_ROOT}"
    install_contributed_roles
    ansible-playbook --inventory-file="${KUBEFORM_ROOT}/${KUBEFORM_INVENTORY}" \
    --tags "${ANSIBLE_TAGS:-all}" \
    ${ANSIBLE_LOG} --extra-vars "$( get_kubeform_variables  KUBEFORM_)" \
    ${ANSIBLE_EXARGS:-} \
    ${KUBEFORM_PLAYBOOK}
  popd
}

install_contributed_roles() {
  pushd "${KUBEFORM_ROOT}"
    ansible-galaxy install --force -r requirements.yml
  popd
}

get_terraform_modules() {
  pushd "${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}"
    # Downloads terraform modules.
    terraform get

    # Make any dependencies
    if ls -1 .terraform/modules/*/Makefile >/dev/null 2>&1; then
      for dir in .terraform/modules/*/Makefile;
      do
        make -C $(/usr/bin/dirname $dir)
      done
    fi
  popd
}

terraform_apply() {
  pushd "${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}"
    terraform apply
  popd
}

# Helper function to get the fist octet of an IPv4 address.
get_network_identifier() {
  ip="$1"
  echo $(echo $ip | tr "." " " | awk '{ print $1 }')
}
