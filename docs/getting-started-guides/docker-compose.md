# Getting started locally with Docker Compose

## Prerequisites

1. [Docker for Mac](https://beta.docker.com/) or [Docker Toolbox for Windows](https://docs.docker.com/engine/installation/windows/) or [Docker Toolbox for OSX](https://docs.docker.com/engine/installation/mac/) depending on your platform.

## Cluster Turnup

### Download Kubeform (install from source at head)
```
git clone https://github.com/Capgemini/kubeform.git /tmp/kubeform
cd /tmp/kubeform

```

To start up the Docker containers execute:

```
KUBERNETES_VERSION=1.2.4 docker-compose up -d
```

replace with the relevant Kubernetes version.

###?| Troubleshooting

When working with Docker for mac on OSX, you may find that you need to replace two lines in the docker-compose.yml with the following:

```
      - /private/var/lib/docker/:/var/lib/docker:ro
      - /private/var/lib/kubelet/:/var/lib/kubelet:rw/
```

## Cluster Destroy

```
cd /tmp/kubeform/
docker-compose stop && docker-compose rm
```
