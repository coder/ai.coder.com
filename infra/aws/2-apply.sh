#!/usr/bin/env bash

set -ae -o pipefail

source coder.env

echo $@

TG_ARGS=()
TF_ARGS=()

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    TF_ARGS=("$@")
    break
  fi

  TG_ARGS+=("$1")
  shift
done

terragrunt run --all \
  --config root.hcl \
  "${TG_ARGS[@]}" \
  -- \
  apply \
  "${TF_ARGS[@]}"