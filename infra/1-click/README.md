# Requirements

- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [AWS Account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html) + [CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Domain in Route53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html#domain-register-procedure-section)
- [AWS Bedrock + Anthropic Agreement Completed](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)

> [!IMPORTANT] 
> Deploying will take around ~30min to setup everything (AWS resources, K8s Addons, DNS resolution, and Coder).
> Cleaning up will take ~20 minutes.

# Getting Started

1. Create or use an AWS account
2. Login as a user with AdministratorAccess
3. Setup your local machine to have an [AWS profile](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)

>[!NOTE] 
> When running `aws login` or `aws configure`, this will automatically setup a `default` profile for you.

4. Purchase/Register a domain in Route53 and tie it to a public hosted zone.

> [!IMPORTANT] 
> When purchasing, it creates a hosted zone in a few minutes, wait for this. AND, if using an existing domain/zone, cleanup any conflicting A/AAAA/CNAME/TXT records.

5. Fill the `coder.env` file with the following environment variables:

```env
CODER_AWS_PROFILE=default (Change profile if needed)
CODER_AWS_REGION=us-east-2 (Change region if needed)
CODER_DOMAIN_NAME=put.your.domain.here.com
CODER_LICENSE=abcde1234..... (Optional)
```

6. Initialize the project by running:

```bash
./0-initialize.sh
```

7. Finally, deploy by running:

```bash
set -a && source coder.env && set +a && ./1-plan-n-deploy.sh
```

# Logging In

1. On your browser, go to "https://put.your.domain.here.com"
2. Enter the following login details (if you didn't override it):

```
Email: admin@coder.com
Password: Th1s1sN0TS3CuR3!!
```

3. You're done!

# Cleaning Up

1. Just run:

```bash
set -a && source coder.env && set +a && ./2-clean.sh
```

# Troubleshooting

- To verify the state of the infrastructure, visit the AWS Console and look at the pages of following AWS services that this solution deploys/manages:
    - EC2
    - VPC
    - RDS (Database, Snapshots, and SubnetGroups)
    - EKS
    - Secrets Manager
    - Route53
    - SSM Parameters
    - CloudWatch Logs
    - Bedrock

- To verify the cluster state, run `aws eks update-kubeconfig --name <ClusterName> --region <YourRegion> --profile <YourProfile>` and execute kubectl commands.

- To verify the cluster addons, inspect the status/logs of the following cluster addons:
    - vpc-cni
    - coredns
    - metrics-server
    - cert-manager
    - karpenter
    - aws-load-balancer-controller (lb-ctrl)
    - aws-ebs-csi (ebs-ctrl)
    - external-dns
    - external-secrets

- To verify the status of resources tied to CRDs, you can inspect the following:
    - Service (check the aws-load-balancer-controller deployment for logs)
    - ClusterIssuer
    - Certificate
    - CertificateRequests
    - Order
    - ClusterSecretStore
    - ExternalSecrets
    - PushSecrets
    - NodePool
    - EC2NodeClass


- Be careful with running this deployment multiple times in succession. You may be getting rate-limited, either by:
    - AWS (for spamming resource creation)
    - Let's Encrypt's CA (for spamming certificate signing requests)

- If the deployment fails on "data.external.first-user", then you might be running into:
    - DNS hasn't propagated yet (you may need to re-run this after waiting a few more minutes)
    - Domain name records not set properly. Check Route53 for your domain to see if the K8s "external-dns" addon had properly set the domain to your LoadBalancer
    - Local DNS may not also be refreshed yet either (i.e. curl may fail, but browser still accessible)

- EKS Addons may fail installation due to "taking too long". Try re-running the deployment script to verify if changes have finished applying
