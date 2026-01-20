> [!IMPORTANT] 
> This deployment will take around 30min ~ 1hr to setup everything (AWS resources, K8s Addons, and Coder)

# Getting Started

1. Create a new AWS account
2. Login as a user with AdministratorAccess
3. Setup your local machine to have an [AWS profile](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-files.html)

>[!NOTE] 
> When running `aws login` or `aws configure`, this will automatically setup a `default` profile for you.

4. [Purchase/Register](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html#domain-register-procedure-section) a domain in Route53 and tie it to a public hosted zone.

> [!IMPORTANT] 
> When purchasing, it creates a hosted zone in a few minutes, wait for this. AND, if using an existing domain/zone, cleanup any A/AAAA/CNAME/TXT records.

5. Fill the `coder.env` file with the following environment variables:

```.env
CODER_AWS_PROFILE=<AWS Profile Name>
CODER_DOMAIN_NAME=<Route53 Domain Name>
CODER_LICENSE=<Coder License Key> (Optional)
```

6. Run `./0-initialize.sh`
7. Run `set -a && source coder.env && set +a && ./1-plan-n-deploy.sh`
8. Run `set -a && source coder.env && set +a && ./2-clean.sh`

# Logging In

1. On your browser, go to "https://<Your Domain>"
2. Enter the following login details (if you didn't override it):

```
Email: admin@coder.com
Password: Th1s1sN0TS3CuR3!!
```

3. You're done!

# Troubleshooting

- To verify the state of the infrastructure, visit the AWS Console and look at the pages of following AWS services that this solution deploys/manages:
    - EC2
    - VPC
    - RDS
    - EKS
    - Secrets Manager
    - Route53

- To verify the state of the Cluster, you can run `aws eks update-kubeconfig --name <ClusterName> --region <YourRegion> --profile <YourProfile>` and execute kubectl commands.

- To verify the state of Cluster addons, you can inspect the following and review their status/logs within the cluster:
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
