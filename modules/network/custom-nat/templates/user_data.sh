#!/bin/sh
# Exit on error, undefined variables, and pipe failures because configuration failures should stop execution
set -euo pipefail

# Truncate config file, exit if fails
: > /etc/fck-nat.conf || exit 1
echo "eni_id=${TERRAFORM_ENI_ID}" >> /etc/fck-nat.conf
echo "eip_id=${TERRAFORM_EIP_ID}" >> /etc/fck-nat.conf
echo "cwagent_enabled=${TERRAFORM_CWAGENT_ENABLED}" >> /etc/fck-nat.conf
echo "cwagent_cfg_param_name=${TERRAFORM_CWAGENT_CFG_PARAM_NAME}" >> /etc/fck-nat.conf

# Restart service and exit with error code if it fails
service fck-nat restart || exit 1
