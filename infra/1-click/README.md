# Coder 1-Click

The following project an opinonated deployment of Coder on AWS EKS. It is not intended to be used in production, but to quickly try out any new Coder features.

This will create the following resources:

- Networking
  - 1 AWS VPC with public and private subnets
  - AWS NAT Gateway
  - Security Groups
  - Elastic IPs (for Grafana, Coder Server, and Proxy load balancers)
- Compute
  - AWS EKS Cluster (with AutoMode enabled)
  - Karpenter for dynamic node provisioning
  - EC2 nodes (managed by Karpenter NodePools)
- Storage
  - AWS S3 Bucket (for Loki logs)
  - 2 AWS RDS PostgreSQL Databases (Coder and Grafana)
  - AWS EBS volumes (via EBS CSI Driver)
- DNS
  - AWS Route53 DNS Records (A records for Grafana, Coder Server, and Proxy)
  - AWS ACM SSL Certificates (for Grafana, Coder Server, and Proxy with wildcard support)
- IAM
  - IAM User with Bedrock access (for AI features)
  - IAM Roles for EKS, Karpenter, and cluster addons
- K8s Addons
  - CoreDNS, VPC CNI, Kube-proxy (EKS managed)
  - Metrics Server
  - AWS Load Balancer Controller
  - AWS EBS CSI Driver
  - Karpenter
- K8s Apps
  - Coder Server
  - Coder Proxy (only when Coder license is added)
  - Coder Provisioner (only when Coder license is added)
  - Coder Logstream
  - Monitoring Stack for Coder (Grafana, Loki, Prometheus)

## Requirements

Deploying this will take 20-30 minutes to setup everything (AWS resources, K8s Addons, DNS resolution, and Coder). Cleaning is ~20 min. The below items are required to run this:

### OSS
- [Terraform >= v1.14.1](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [Terragrunt (>= v0.78.0)](https://terragrunt.gruntwork.io/docs/getting-started/install/)
- [AWS CLI (>= v2.33.23)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [AWS Account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html)
- [AWS Bedrock/Anthropic Agreement Completed](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html).
- [AWS Route53 Domain](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html#domain-register-procedure-section)

### Enterprise
- Same OSS requirements.
- An [Enterprise Coder License](https://coder.com/docs/admin/licensing).

# Getting Started

1. Create or acquire an AWS account
2. Login as a user with AdministratorAccess
3. Setup your local machine to have an [AWS profile](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html). 
  - When running `aws configure`, this will automatically setup a `default` profile for you. 
  - If using `aws configure sso` you must manually set the profile name to `default`. Afterwards, you can login with `aws sso login`
  - If using `aws login` follow this [thread](https://github.com/hashicorp/terraform-provider-aws/issues/45316) to see the fix.

4. Purchase/Register a domain in Route53 and tie it to a public zone. When purchasing, it'll create a zone in a few minutes, wait for this. If using an existing domain, cleanup any conflicting A/AAAA/CNAME/TXT records.

5. Fill the `coder.env` file with the following environment variables:

```env
CODER_AWS_PROFILE=default # (Change profile if needed)
CODER_AWS_REGION=us-east-2 # (Change region if needed)
CODER_DOMAIN_NAME=put.your.domain.here.com
CODER_LICENSE=abcde1234..... # (Optional)
```

> [!IMPORTANT] 
> Upon creating the initial deployment, DO NOT CHANGE THE DOMAIN. Clean up first, then recreate it. The entire infrastructure depends on the name.

6. Initialize the project:

```bash
./0-init.sh
```

7. Finally, deploy:

```bash
./1-apply.sh
```

## Logging In

1. On your browser, go to "https://put.your.domain.here.com"
2. Enter the below login details (if you didn't override it):

```
Email: admin@coder.com
Password: Th1s1sN0TS3CuR3!!
```

3. You're done!

## Cleaning Up

1. [Delete all Coder workspaces](https://coder.com/docs/user-guides/workspace-lifecycle#deleting-workspaces).

2. Run this script to tear down the deployment:

```bash
./2-clean.sh
```

## Advanced Configuration

### Using a Remote State

You can enable the deployment to store your terraform state remotely if you need to interact with this outside your local desktop.

This is useful if you plan on running this deployment within an ephemeral environment and need to persist it's state.

Otherwise, if you're running this on your laptop or on a machine that persists state, then feel free to keep the state local.

If using a remote state, then follow this to setup the S3 backend: https://spacelift.io/blog/terraform-s3-backend#how-to-create-a-terraform-s3-backend

Follow this link if you need more details on Terraform's S3 backend: https://developer.hashicorp.com/terraform/language/backend/s3

Once the AWS S3 Bucket is setup, set the following environment variables on your `coder.env` file:

```
CODER_TF_USE_REMOTE_STATE=true
CODER_TF_BACKEND_AWS_BUCKET_NAME=<Your AWS S3 Bucket>
CODER_TF_BACKEND_AWS_REGION=<Your AWS S3 Bucket's Region>
```

### Changing the Coder Version

There's no rolling back in Coder, only updating forward. If you need to change the Coder version, change the following environment variable:

```
CODER_VERSION=<Your Coder Version>
```

Make sure that the version is ALWAYS greater than the previous.

# Troubleshooting

- When logging in to AWS you might run into issues such as: `An error occurred (InvalidRequestException)`. Make sure that:
  - Your spelling is correct.
  - The correct region for your SSO Start URL is set.
  - You're consuming the correct SSO URL.

- When initializing the project, and if you ran `aws login`, you might run into: `Error: failed to refresh cached credentials, no EC2 IMDS role found`.
  - View this [thread]((https://github.com/hashicorp/terraform-provider-aws/issues/45316)) to see how to workaround this. Otherwise, try the other options to login (manually setting the profile/credentials, or use AWS SSO).

- To verify the state of the infrastructure, visit the AWS Console and look at the pages of following AWS services that this solution deploys/manages:
  - EC2
  - VPC (NAT Gateway, Subnets, Security Groups, EIPs)
  - RDS (Database, Snapshots, and SubnetGroups)
  - EKS
  - Route53
  - CloudWatch Logs
  - Bedrock

- To verify the cluster state, run `aws eks update-kubeconfig --name <ClusterName> --region <YourRegion> --profile <YourProfile>` and execute kubectl commands.

- To verify the cluster addons, inspect the status/logs of the following cluster addons:
  - vpc-cni
  - coredns
  - metrics-server
  - karpenter
  - aws-load-balancer-controller (lb-ctrl)
  - aws-ebs-csi (ebs-ctrl)

- To verify the status of resources tied to CRDs, you can inspect the following:
  - Service (check the aws-load-balancer-controller deployment for logs)
  - PersistentVolumeClaim (check the ebs-csi deployment for logs)
  - NodePool (EKS AutoMode + Karpenter)
  - EC2NodeClass (Karpenter)
  - NodeClass (EKS AutoMode)


- Be careful with running this deployment multiple times in succession. You may be getting rate-limited by AWS.

- If the deployment fails on "data.external.first-user", then you might be running into:
  - DNS hasn't propagated yet (you may need to re-run this after waiting a few more minutes)
  - Domain name records not set properly. Check Route53 for your domain to see if the A record was properly set to the correct IP.
  - Local DNS may not also be refreshed yet either (i.e. curl may fail, but browser still accessible)
  - Load Balancer health checks may be failing (i.e. Availability Zone is temporarily unavailable, or Coder failed to start.)

- EKS Addons may fail installation due to "taking too long". Try re-running the deployment script to verify if changes have finished applying