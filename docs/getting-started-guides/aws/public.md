# Getting started on AWS

The cluster is provisioned in separate stages as follows:

* [Terraform](https://terraform.io) to provision the cluster instances, security groups, firewalls, cloud infrastructure and security (SSL) certificates.
* [Ansible](https://ansible.com) to configure the cluster, including installing Kubernetes, addons and platform level configuration (files, directories etc...)

## Prerequisites

1. You need an AWS account. Visit [http://aws.amazon.com](http://aws.amazon.com) to get started
2. You need an AWS [instance profile and role](http://docs.aws.amazon.com/IAM/latest/UserGuide/instance-profiles.html) with EC2 full access.
3. You need to have installed and configured Terraform (>= 0.6.16 recommended). Visit [https://www.terraform.io/intro/getting-started/install.html](https://www.terraform.io/intro/getting-started/install.html) to get started.
4. You need to have [Python](https://www.python.org/) >= 2.7.5 installed along with [pip](https://pip.pypa.io/en/latest/installing.html).
5. Kubectl installed in and your PATH:

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.4/bin/linux/amd64/kubectl
```

On an OS X workstation, replace linux in the URL above with darwin:

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.4/bin/darwin/amd64/kubectl
```
After downloading the binary, ensure it is executable and move it into your PATH:

```
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl
```

## Cluster Turnup

### Download Kubeform (install from source at head)
```
git clone https://github.com/Capgemini/kubeform.git /tmp/kubeform
cd /tmp/kubeform
pip install -r requirements.txt
```

### Set config

Configuration can be set via environment variables. As a minimum you will need to set these environment variables:

```
export TF_VAR_access_key=$AWS_ACCESS_KEY_ID
export TF_VAR_secret_key=$AWS_SECRET_ACCESS_KEY
export TF_VAR_STATE_ROOT=/tmp/kubeform/terraform/aws/public-cloud
```

### Get terraform dependencies

```
cd /tmp/kubeform/terraform/aws/public-cloud
terraform get
for i in $(ls .terraform/modules/*/Makefile); do i=$(dirname $i); make -C $i; done
```

### Provision the cluster infrastructure

```
rm -f etcd_discovery_url.txt && terraform apply -target=null_resource.etcd_discovery_url
terraform apply
```

### Configure the cluster

To install the role dependencies for Ansible execute:

```
cd /tmp/kubeform
ansible-galaxy install -r requirements.yml
```

To run the Ansible playbook (to configure the cluster):

```
ansible-playbook -u core --ssh-common-args="-i /tmp/kubeform/terraform/aws/public-cloud/id_rsa -q" --inventory-file=inventory site.yml -e kube_apiserver_vip=$(cd /tmp/kubeform/terraform/aws/public-cloud && terraform output master_elb_hostname)
```

This will run the playbook (using the credentials output by terraform and the terraform state as a dynamic inventory) and inject the AWS ELB (for the master API servers) address as a variable ```kube_apiserver_vip```.

## Cluster Destroy

```
cd /tmp/kubeform/terraform/aws/public-cloud
terraform destroy
```
