static_cloudfront_site
==
Dead-simple way to get a bucket hosted via CloudFront with TLS enabled, complete with CloudFront's recommended origin access controls. 

Prerequisites
--
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) must be installed
* A public Route 53 hosted zone for the domain (or a parent of it) must already exist

Usage
--

```bash
# example.com + www.example.com, certificate issued and DNS-validated automatically
./create.sh example.com

# a host inside an existing zone (finds the example.com zone, no www), e.g. a file CDN
./create.sh cdn.example.com --random-bucket --root-object "" --geo-block RU,CN

# bring your own certificate (must be in us-east-1, CloudFront restriction)
./create.sh example.com arn:aws:acm:us-east-1:123456789012:certificate/...
```

Run `./create.sh` with no arguments for all options. Re-running it for the same domain updates the existing stack, always keeping its bucket. The bucket name and distribution ID are printed at the end (stack outputs `BucketName` and `DistributionId`).

Every response carries CloudFront's managed security headers (HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, ...), so upload objects with correct `Content-Type`s. The bucket is retained when the stack is deleted.

Without a certificate ARN, `certificate.yml` is deployed as `<stack>-certificate` in us-east-1 first, and its validation records are written to the hosted zone. The site stack goes in the CLI's default region.
