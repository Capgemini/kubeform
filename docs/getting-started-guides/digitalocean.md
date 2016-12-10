# Getting started on Digitalocean

The cluster is provisioned in separate stages as follows:

* [Terraform](https://terraform.io) to provision the cluster instances, security groups, firewalls, cloud infrastructure and security (SSL) certificates.
* [Ansible](https://ansible.com) to configure the cluster, including installing Kubernetes, addons and platform level configuration (files, directories etc...)

## Prerequisites

1. You need a Digitalocean account. Visit [https://cloud.digitalocean.com/registrations/new](https://cloud.digitalocean.com/registrations/new) to get started
2. You need to have installed and configured Terraform (>= 0.7.13 recommended). Visit [https://www.terraform.io/intro/getting-started/install.html](https://www.terraform.io/intro/getting-started/install.html) to get started.
3. You need to have [Python](https://www.python.org/) >= 2.7.5 installed along with [pip](https://pip.pypa.io/en/latest/installing.html).
4. Kubectl installed in and your PATH:

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.3/bin/linux/amd64/kubectl
```

On an OS X workstation, replace linux in the URL above with darwin:

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.3/bin/darwin/amd64/kubectl
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
export TF_VAR_do_token=$DO_API_TOKEN
export TF_VAR_STATE_ROOT=/tmp/kubeform/terraform/digitalocean
```

### Get terraform dependencies

```
cd /tmp/kubeform/terraform/digitalocean
terraform get
```

### Provision the cluster infrastructure

```
terraform apply
```

### Configure the cluster

To install the role dependencies for Ansible execute:

```
cd /tmp/kubeform
ansible-galaxy install -r requirements.yml
```

Ensure that an ssh server is running on port 22 on your development machine.

To run the Ansible playbook (to configure the cluster):

```
ansible-playbook -u core --private-key=/tmp/kubeform/terraform/digitalocean/id_rsa --inventory-file=inventory site.yml
```

This will run the playbook (using the credentials output by terraform and the terraform state as a dynamic inventory).

###?| Log in

Once you're set up, you can log into the dashboard by running:

```
kubectl proxy
```

and visiting the following URL [http://localhost:8001/ui](http://localhost:8001/ui)

## Cluster Destroy

```
cd /tmp/kubeform/terraform/digitalocean
terraform destroy
```
