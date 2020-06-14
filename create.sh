#!/bin/bash
DOMAIN_NAME=$1
STACK_NAME=$(echo "$DOMAIN_NAME" | cut -f 1 -d '.')

if [ -z "$DOMAIN_NAME" ]; then
  echo "Usage: ./create.sh example.com"
  exit 1
fi

aws cloudformation create-stack --stack-name "$STACK_NAME" --template-body file://static_cloudfront_site.yml --parameters ParameterKey=DomainName,ParameterValue=$DOMAIN_NAME