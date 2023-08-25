static_cloudformation_site
==
Dead-simple way to get a bucket hosted via CloudFront with TLS enabled, complete with CloudFront's recommended origin access controls. 

Prerequisites
--
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) must be installed
* A certificate must be [requested with ACM](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html) in the **us-east-1 region** (CloudFront restriction) for the domain name being hosted

Usage
--

```bash
./create.sh domainname.com get_an_acm_cert_from_us_east_1_and_put_the_arn_here
```

