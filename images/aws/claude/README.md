To login

```
aws ecr get-login-password --region <Region> | docker login --username AWS --password-stdin <AccountId>.dkr.ecr.<Region>.amazonaws.com
```

Commands to run

Alpine

```
docker build --platform=linux/amd64 -f Dockerfile.alpine -t <AccountId>.dkr.ecr.<Region>.amazonaws.com/claude-ws:alpine-3.22 --no-cache .
docker push <AccountId>.dkr.ecr.<Region>.amazonaws.com/claude-ws:alpine-3.22
```

Noble

```
docker build --platform=linux/amd64 -f Dockerfile.noble -t <AccountId>.dkr.ecr.<Region>.amazonaws.com/claude-ws:ubuntu-noble --no-cache .
docker push <AccountId>.dkr.ecr.<Region>.amazonaws.com/claude-ws:ubuntu-noble
```
