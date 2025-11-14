To login to the ECR Registry with Docker:

```
aws ecr get-login-password --region <Region> --profile demo-coder | docker login --username AWS --password-stdin <AccountId>.dkr.ecr.<Region>.amazonaws.com
```

To build and push an image:

```
docker build -t <AccountId>.dkr.ecr.<Region>.amazonaws.com/example:latest
docker push <AccountId>.dkr.ecr.<Region>.amazonaws.com/example:latest
```
