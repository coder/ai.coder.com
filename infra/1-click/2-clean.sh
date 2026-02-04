#!/usr/bin/env bash

set -ae -o pipefail

source coder.env

AWS_AZS="${CODER_AWS_AZS:-[\"a\",\"c\"]}"

AWS_PROFILE="${CODER_AWS_PROFILE:-default}"
AWS_REGION="${CODER_AWS_REGION:-us-east-2}"
DOMAIN_NAME="${CODER_DOMAIN_NAME:-}"
LICENSE="${CODER_LICENSE:-}"

USE_EXTERN_DNS="${CODER_USE_EXTERN_DNS:-true}"

USE_R53="${CODER_USE_R53:-true}"

USE_CF="${CODER_USE_CF:-false}"
CF_TOKEN="${CODER_CF_TOKEN:-}"
CF_EMAIL="${CODER_CF_EMAIL:-}"

SET_REC_USE_R53=false; ! $USE_EXTERN_DNS && $USE_R53 && SET_REC_USE_R53=true
SET_REC_USE_CF=false; ! $USE_EXTERN_DNS && $USE_CF && SET_REC_USE_CF=true

CODER_DB_USERNAME="${CODER_DB_USERNAME:-coder}"
CODER_DB_PASSWORD="${CODER_DB_PASSWORD:-th1s1sn0tas3cur3pass0wrd}"

GRAFANA_DB_USERNAME="${CODER_GRAFANA_DB_PASSWORD:-grafana}"
GRAFANA_DB_PASSWORD="${CODER_GRAFANA_DB_PASSWORD:-th1s1sn0tas3cur3pass0wrd}"

CODER_USERNAME="${CODER_USERNAME:-admin}"
CODER_EMAIL="${CODER_EMAIL:-admin@coder.com}"
CODER_PASSWORD="${CODER_PASSWORD:-Th1s1sN0TS3CuR3!!}"

echo "Change directory into '2-coder'."
cd 2-coder
terraform plan -destroy -out=tf.plan \
    -var profile=$AWS_PROFILE \
    -var region=$AWS_REGION \
    -var domain_name=$DOMAIN_NAME \
    -var coder_license=$LICENSE \
    -var coder_admin_email=$CODER_EMAIL \
    -var coder_admin_password=$CODER_PASSWORD
terraform apply tf.plan
cd ../

echo "Change directory into '1-setup'."
cd 1-setup
terraform plan -destroy -out=tf.plan \
    -var profile=$AWS_PROFILE \
    -var region=$AWS_REGION \
    -var domain_name=$DOMAIN_NAME \
    -var azs="$AWS_AZS" \
    -var coder_license=$LICENSE \
    -var coder_username=$CODER_DB_USERNAME \
    -var coder_password=$CODER_DB_PASSWORD \
    -var coder_admin_email=$CODER_EMAIL \
    -var coder_admin_username=$CODER_USERNAME \
    -var coder_admin_password=$CODER_PASSWORD \
    -var auto_set_record="{\"use_cf\":\"$SET_REC_USE_CF\",\"cf_token\":\"$CF_TOKEN\",\"use_r53\":\"$SET_REC_USE_R53\"}" \
    -var cf_config="{\"enabled\":\"$USE_CF\",\"email\":\"$CF_EMAIL\"}" \
    -var r53_config="{\"enabled\":\"$USE_R53\"}"
terraform apply tf.plan
cd ../

echo "Change directory into '0-infra'."
cd 0-infra
terraform plan -destroy -out=tf.plan \
    -var profile=$AWS_PROFILE \
    -var region=$AWS_REGION \
    -var domain_name=$DOMAIN_NAME \
    -var azs="$AWS_AZS" \
    -var coder_username=$CODER_DB_USERNAME \
    -var coder_password=$CODER_DB_PASSWORD \
    -var grafana_username=$GRAFANA_DB_USERNAME \
    -var grafana_password=$GRAFANA_DB_PASSWORD \
    -var use_ext_dns=$USE_EXTERN_DNS \
    -var cf_config="{\"enabled\":\"$USE_CF\",\"email\":\"$CF_EMAIL\",\"token\":\"$CF_TOKEN\"}" \
    -var r53_config="{\"enabled\":\"$USE_R53\"}"
terraform apply tf.plan
cd ../