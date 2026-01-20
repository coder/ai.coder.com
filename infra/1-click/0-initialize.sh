#!/usr/bin/env bash

set -e -o pipefail

echo "Change directory into '0-infra'."
cd 0-infra
terraform init
cd ../

echo "Change directory into '1-setup'."
cd 1-setup
terraform init
cd ../

echo "Change directory into '2-coder'."
cd 2-coder
terraform init
cd ../