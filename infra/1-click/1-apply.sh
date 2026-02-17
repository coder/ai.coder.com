#!/usr/bin/env bash

set -ae -o pipefail

source coder.env

terragrunt run --all --non-interactive apply