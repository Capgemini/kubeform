variable "access_key" {}
variable "secret_key" {}
variable "organization" { default = "kubeform" }
variable "region" { default = "eu-west-1" }
variable "availability_zones" { default = "eu-west-1a,eu-west-1b,eu-west-1c" }
variable "coreos_channel" { default = "alpha" }
variable "etcd_discovery_url_file" { default = "etcd_discovery_url.txt" }
variable "masters" { default = "3" }
variable "master_instance_type" { default = "m3.medium" }
variable "workers" { default = "1" }
variable "worker_instance_type" { default = "m3.medium" }
variable "worker_ebs_volume_size" { default = "30" }
variable "edge-routers" { default = "1" }
variable "edge-router_instance_type" { default = "m3.medium" }
variable "edge-router_ebs_volume_size" { default = "30" }
variable "vpc_cidr_block" { default = "10.0.0.0/16" }

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_vpc" "default" {
  cidr_block           = "${var.vpc_cidr_block}"
  enable_dns_support   = true
  enable_dns_hostnames = true
  lifecycle {
    create_before_destroy = true
  }
}

# ssh keypair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

# Export ssh key so we can login with core@instance -i id_rsa
resource "null_resource" "keys" {
  depends_on = ["tls_private_key.ssh"]

  provisioner "local-exec" {
    command = "echo '${tls_private_key.ssh.private_key_pem}' > ${path.module}/id_rsa && chmod 600 ${path.module}/id_rsa"
  }
}

module "aws-keypair" {
  source     = "../keypair"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

# certificates
module "ca" {
  source            = "github.com/Capgemini/tf_tls/ca"
  organization      = "${var.organization}"
  ca_count          = "${var.masters + var.workers + var.edge-routers}"
  deploy_ssh_hosts  = "${concat(aws_instance.edge-router.*.public_ip, concat(aws_instance.master.*.public_ip, aws_instance.worker.*.public_ip))}"
  ssh_user          = "core"
  ssh_private_key   = "${tls_private_key.ssh.private_key_pem}"
}

module "etcd_cert" {
  source             = "github.com/Capgemini/tf_tls/etcd"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
}

module "kube_master_certs" {
  source                = "github.com/Capgemini/tf_tls/kubernetes/master"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses          = "${concat(aws_instance.master.*.private_ip, aws_instance.master.*.public_ip)}"
  dns_names             = "${compact(module.master_elb.elb_dns_name)}"
  deploy_ssh_hosts      = "${compact(aws_instance.master.*.public_ip)}"
  master_count          = "${var.masters}"
  validity_period_hours = "8760"
  early_renewal_hours   = "720"
  ssh_user              = "core"
  ssh_private_key       = "${tls_private_key.ssh.private_key_pem}"
}

module "kube_kubelet_certs" {
  source                = "github.com/Capgemini/tf_tls/kubernetes/kubelet"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses          = "${concat(aws_instance.edge-router.*.private_ip, concat(aws_instance.master.*.private_ip, aws_instance.worker.*.private_ip))}"
  deploy_ssh_hosts      = "${concat(aws_instance.edge-router.*.public_ip, concat(aws_instance.master.*.public_ip, aws_instance.worker.*.public_ip))}"
  kubelet_count         = "${var.masters + var.workers + var.edge-routers}"
  validity_period_hours = "8760"
  early_renewal_hours   = "720"
  ssh_user              = "core"
  ssh_private_key       = "${tls_private_key.ssh.private_key_pem}"
}

module "kube_admin_cert" {
  source                = "github.com/Capgemini/tf_tls/kubernetes/admin"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  kubectl_server_ip     = "${module.master_elb.elb_dns_name}"
}

module "docker_daemon_certs" {
  source                = "github.com/Capgemini/tf_tls/docker/daemon"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses_list     = "${concat(aws_instance.edge-router.*.private_ip, concat(aws_instance.master.*.private_ip, aws_instance.worker.*.private_ip))}"
  deploy_ssh_hosts      = "${concat(aws_instance.edge-router.*.public_ip, concat(aws_instance.master.*.public_ip, aws_instance.worker.*.public_ip))}"
  docker_daemon_count   = "${var.masters + var.workers + var.edge-routers}"
  private_key           = "${tls_private_key.ssh.private_key_pem}"
  validity_period_hours = 8760
  early_renewal_hours   = 720
  user                  = "core"
}

module "docker_client_certs" {
  source                = "github.com/Capgemini/tf_tls/docker/client"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses_list     = "${concat(aws_instance.edge-router.*.private_ip, concat(aws_instance.master.*.private_ip, aws_instance.worker.*.private_ip))}"
  deploy_ssh_hosts      = "${concat(aws_instance.edge-router.*.public_ip, concat(aws_instance.master.*.public_ip, aws_instance.worker.*.public_ip))}"
  docker_client_count   = "${var.masters + var.workers + var.edge-routers}"
  private_key           = "${tls_private_key.ssh.private_key_pem}"
  validity_period_hours = 8760
  early_renewal_hours   = 720
  user                  = "core"
}

# internet gateway
module "igw" {
  source = "github.com/terraform-community-modules/tf_aws_igw"
  name   = "public"
  vpc_id = "${aws_vpc.default.id}"
}

# public subnets
module "public_subnet" {
  source = "github.com/terraform-community-modules/tf_aws_public_subnet?ref=b7659c06cba6a545b83f569bc73560b266e6c9c1"
  name   = "public"
  cidrs  = "10.0.1.0/24,10.0.2.0/24,10.0.3.0/24"
  azs    = "${var.availability_zones}"
  vpc_id = "${aws_vpc.default.id}"
  igw_id = "${module.igw.igw_id}"
}

# security group to allow all traffic in and out of the instances
module "sg-default" {
  source = "../sg-all-traffic"
  vpc_id = "${aws_vpc.default.id}"
}

# IAM
module "iam" {
  source = "../iam"
}

# Generate an etcd URL for the cluster
resource "null_resource" "etcd_discovery_url" {
    provisioner "local-exec" {
        command = "curl -s https://discovery.etcd.io/new?size=${var.masters} > ${var.etcd_discovery_url_file}"
    }

    # This will regenerate the discovery URL if the cluster size changes
    triggers {
        size = "${var.masters}"
    }
}
