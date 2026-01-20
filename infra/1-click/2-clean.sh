#!/usr/bin/env bash

set -ae -o pipefail

##
# Set this block to 2-coder for cleaning when ready
##

AWS_PROFILE="${CODER_AWS_PROFILE:-default}"
DOMAIN_NAME="${CODER_DOMAIN_NAME:-}"
LICENSE="${CODER_LICENSE:-}"

echo "Change directory into '1-setup'."
cd 1-setup
terraform plan -destroy -out=tf.plan \
    -var profile=$AWS_PROFILE \
    -var domain_name=$DOMAIN_NAME \
    -var coder_license=$LICENSE
terraform apply tf.plan
cd ../

echo "Change directory into '0-infra'."
cd 0-infra
terraform plan -destroy -out=tf.plan \
    -var profile=$AWS_PROFILE \
    -var domain_name=$DOMAIN_NAME
terraform apply tf.plan
cd ../