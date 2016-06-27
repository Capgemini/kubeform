#!/bin/bash

# Set the default provider of Kubeform cluster to know where to load provider-specific scripts
# You can override the default provider by exporting the KUBEFORM_PROVIDER
# variable in your bashrc
KUBEFORM_PROVIDER=${KUBEFORM_PROVIDER:-aws/public-cloud}
# change global log level of components, set KUBEFORM_LOG to any value to enable
KUBEFORM_LOG=${KUBEFORM_LOG:-}
ANSIBLE_LOG=${ANSIBLE_LOG:-}

# Overrides default folder in Terraform.py inventory.
export TF_VAR_STATE_ROOT="${KUBEFORM_ROOT}/terraform/${KUBEFORM_PROVIDER}"

# Some useful colors.
if [[ -z "${color_start-}" ]]; then
  export color_start="\033["
  export color_red="${color_start}0;31m"
  export color_yellow="${color_start}0;33m"
  export color_green="${color_start}0;32m"
  export color_norm="${color_start}0m"
fi

# Change logging levels of called components at a global level
# if unset allow for existing selective logging of components
case "${KUBEFORM_LOG}" in
  "")
    # Do nothing in this instance
  ;;
  0)
    # Force minimal logging
    echo "Forcing reduction of component logging"
    export TF_LOG=
    export ANSIBLE_LOG=
  ;;
  1)
    export TF_LOG=1
    export ANSIBLE_LOG="-v"
  ;;
  *)
    export TF_LOG=${KUBEFORM_LOG}
    export ANSIBLE_LOG="-vvvv"
  ;;
esac
