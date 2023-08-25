#!/bin/bash
set -e

DOMAIN_NAME="$1"
CERTIFICATE_ARN="$2"
STACK_NAME=$(echo "www-$DOMAIN_NAME" | cut -f 1 -d '.')

if [[ -z "$DOMAIN_NAME" || -z "$CERTIFICATE_ARN" ]]; then
  echo "Usage: ./create.sh example.com arn:aws:us-east-1:acm_cert"
  exit 1
fi

aws cloudformation create-stack --stack-name "$STACK_NAME" --template-body file://static_cloudfront_site.yml --parameters ParameterKey=DomainName,ParameterValue=$DOMAIN_NAME ParameterKey=DomainCertificateArn,ParameterValue=$CERTIFICATE_ARN
