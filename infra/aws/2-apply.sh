#!/usr/bin/env bash

set -ae -o pipefail

source coder.env

echo $@

terragrunt run --all --non-interactive --config root.hcl $@ apply 