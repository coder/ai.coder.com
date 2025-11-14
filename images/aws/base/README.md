To login

```
aws ecr get-login-password --region <Region> --profile demo-coder | docker login --username AWS --password-stdin <AccountID>.dkr.ecr.<Region>.amazonaws.com
```

Commands to run

Alpine

```
docker build --platform=linux/amd64 -f Dockerfile.alpine -t <AccountID>.dkr.ecr.<Region>.amazonaws.com/base-ws:alpine-3.22 --no-cache .
docker push <AccountID>.dkr.ecr.<Region>.amazonaws.com/base-ws:alpine-3.22
```

Noble

```
docker build --platform=linux/amd64 -f Dockerfile.noble -t <AccountID>.dkr.ecr.<Region>.amazonaws.com/base-ws:ubuntu-noble --no-cache .
docker push <AccountID>.dkr.ecr.<Region>.amazonaws.com/base-ws:ubuntu-noble
```
