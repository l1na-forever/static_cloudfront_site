#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ./create.sh DOMAIN [CERTIFICATE_ARN] [options]

  --cert ARN              us-east-1 ACM certificate to use (default: issue one with certificate.yml)
  --zone NAME             Route 53 zone for the records (default: closest existing zone enclosing DOMAIN)
  --subdomain NAME        extra subdomain to serve, "" for none (default: "www" at a zone apex, none otherwise)
  --bucket NAME           bucket name (default: DOMAIN)
  --random-bucket         give the bucket a random name
                          (an existing stack always keeps its current bucket)
  --root-object NAME      default root object, "" to disable (default: index.html)
  --not-found-page PATH   page for missing objects, e.g. /404.html (default: none)
  --geo-block CC,CC       countries to deny, e.g. RU,CN (default: none)
  --tls POLICY            minimum viewer TLS policy (default: TLSv1.2_2021)
  --stack-name NAME       site stack name (default: www-<first label> for a zone apex, www-<domain-with-dashes> otherwise)
EOF
  exit 1
}

[[ $# -ge 1 && "$1" != -* ]] || usage
DOMAIN_NAME="$1"
shift
CERTIFICATE_ARN=""
if [[ $# -ge 1 && "$1" == arn:* ]]; then
  CERTIFICATE_ARN="$1"
  shift
fi

ZONE=""
SUBDOMAIN=""
SUBDOMAIN_SET=false
BUCKET_NAME=""
RANDOM_BUCKET=false
ROOT_OBJECT="index.html"
NOT_FOUND_PAGE=""
GEO_BLOCK=""
TLS_POLICY="TLSv1.2_2021"
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --random-bucket) RANDOM_BUCKET=true; shift; continue ;;
  esac
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --cert) CERTIFICATE_ARN="$2" ;;
    --zone) ZONE="${2%.}" ;;
    --subdomain) SUBDOMAIN="$2"; SUBDOMAIN_SET=true ;;
    --bucket) BUCKET_NAME="$2" ;;
    --root-object) ROOT_OBJECT="$2" ;;
    --not-found-page) NOT_FOUND_PAGE="$2" ;;
    --geo-block) GEO_BLOCK="$2" ;;
    --tls) TLS_POLICY="$2" ;;
    --stack-name) STACK_NAME="$2" ;;
    *) usage ;;
  esac
  shift 2
done

if [[ "$RANDOM_BUCKET" == true && -n "$BUCKET_NAME" ]]; then
  echo "--bucket and --random-bucket are mutually exclusive" >&2
  exit 1
fi

# Prints the ID of the public hosted zone named exactly $1, or nothing.
zone_id() {
  aws route53 list-hosted-zones-by-name --dns-name "$1" --max-items 10 \
    --query "HostedZones[?Name=='$1.' && Config.PrivateZone==\`false\`].Id | [0]" --output text \
    | sed -e 's|^/hostedzone/||' -e '/^None$/d'
}

ZONE_ID=""
if [[ -n "$ZONE" ]]; then
  ZONE_ID=$(zone_id "$ZONE")
else
  candidate="$DOMAIN_NAME"
  while [[ "$candidate" == *.* ]]; do
    ZONE_ID=$(zone_id "$candidate")
    if [[ -n "$ZONE_ID" ]]; then
      ZONE="$candidate"
      break
    fi
    candidate="${candidate#*.}"
  done
fi
if [[ -z "$ZONE_ID" ]]; then
  echo "No public Route 53 hosted zone found for $DOMAIN_NAME${ZONE:+ (looked for $ZONE)}" >&2
  exit 1
fi

HOSTED_ZONE_NAME=""
if [[ "$ZONE" == "$DOMAIN_NAME" ]]; then
  [[ "$SUBDOMAIN_SET" == true ]] || SUBDOMAIN="www"
  # e.g. www-example; kept for stacks created before hosts inside zones were supported
  [[ -n "$STACK_NAME" ]] || STACK_NAME=$(echo "www-$DOMAIN_NAME" | cut -f 1 -d '.')
else
  HOSTED_ZONE_NAME="$ZONE"
  [[ -n "$STACK_NAME" ]] || STACK_NAME="www-${DOMAIN_NAME//./-}"
fi

# A different name on an existing stack would replace (and orphan) its bucket, so keep the current one.
EXISTING_BUCKET=$(aws cloudformation describe-stack-resource --stack-name "$STACK_NAME" \
  --logical-resource-id StaticFilesBucket --query 'StackResourceDetail.PhysicalResourceId' \
  --output text 2>/dev/null || true)
if [[ -n "$EXISTING_BUCKET" ]]; then
  if [[ -n "$BUCKET_NAME" && "$BUCKET_NAME" != "$EXISTING_BUCKET" ]]; then
    echo "Stack $STACK_NAME already uses bucket $EXISTING_BUCKET; refusing to replace it with $BUCKET_NAME" >&2
    exit 1
  fi
  echo "Stack $STACK_NAME exists; keeping its bucket $EXISTING_BUCKET"
  BUCKET_NAME="$EXISTING_BUCKET"
elif [[ "$RANDOM_BUCKET" == true ]]; then
  BUCKET_NAME=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
fi

cd "$(dirname "$0")"

if [[ -z "$CERTIFICATE_ARN" ]]; then
  CERT_STACK_NAME="$STACK_NAME-certificate"
  echo "Issuing a certificate for $DOMAIN_NAME${SUBDOMAIN:+ and $SUBDOMAIN.$DOMAIN_NAME} (us-east-1 stack $CERT_STACK_NAME)"
  aws cloudformation deploy --region us-east-1 --stack-name "$CERT_STACK_NAME" \
    --template-file certificate.yml --no-fail-on-empty-changeset \
    --parameter-overrides "DomainName=$DOMAIN_NAME" "Subdomain=$SUBDOMAIN" "HostedZoneId=$ZONE_ID"
  CERTIFICATE_ARN=$(aws cloudformation describe-stacks --region us-east-1 --stack-name "$CERT_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CertificateArn'].OutputValue" --output text)
fi

echo "Deploying $DOMAIN_NAME (stack $STACK_NAME, zone $ZONE)"
aws cloudformation deploy --stack-name "$STACK_NAME" \
  --template-file static_cloudfront_site.yml --no-fail-on-empty-changeset \
  --parameter-overrides \
    "DomainName=$DOMAIN_NAME" \
    "DomainCertificateArn=$CERTIFICATE_ARN" \
    "HostedZoneName=$HOSTED_ZONE_NAME" \
    "Subdomain=$SUBDOMAIN" \
    "BucketName=$BUCKET_NAME" \
    "DefaultRootObject=$ROOT_OBJECT" \
    "NotFoundPage=$NOT_FOUND_PAGE" \
    "GeoBlockedCountries=$GEO_BLOCK" \
    "MinimumProtocolVersion=$TLS_POLICY"

aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --output table
