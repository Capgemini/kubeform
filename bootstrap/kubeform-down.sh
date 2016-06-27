#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

KUBEFORM_ROOT=$(dirname "${BASH_SOURCE}")/..
source "${KUBEFORM_ROOT}/bootstrap/kubeform-env.sh"
source "${KUBEFORM_ROOT}/bootstrap/common.sh"
source "${KUBEFORM_ROOT}/bootstrap/${KUBEFORM_PROVIDER}/util.sh"

echo "Bringing down cluster using provider: $KUBEFORM_PROVIDER"

verify_prereqs
kubeform_down

echo "Done"
