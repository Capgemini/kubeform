variable "do_token" {}
variable "organization" { default = "kubeform" }
variable "region" { default = "lon1" }
variable "masters" { default = "3" }
variable "workers" { default = "1" }
variable "edge-routers" { default = "1" }
variable "master_instance_type" { default = "512mb" }
variable "worker_instance_type" { default = "512mb" }
variable "edge-router_instance_type" { default = "512mb" }
variable "etcd_discovery_url_file" { default = "etcd_discovery_url.txt" }

variable "coreos_image" { default = "coreos-stable" }

# Provider
provider "digitalocean" {
  token = "${var.do_token}"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "digitalocean_ssh_key" "default" {
  name       = "${var.organization}"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

# Export ssh key so we can login with core@instance -i id_rsa
resource "null_resource" "keys" {
  depends_on = ["tls_private_key.ssh"]

  provisioner "local-exec" {
    command = "echo '${tls_private_key.ssh.private_key_pem}' > ${path.module}/id_rsa && chmod 600 ${path.module}/id_rsa"
  }
}

# Generate an etcd URL for the cluster
resource "template_file" "etcd_discovery_url" {
  template = "/dev/null"
  provisioner "local-exec" {
    command = "curl https://discovery.etcd.io/new?size=${var.masters} > ${var.etcd_discovery_url_file}"
  }
  # This will regenerate the discovery URL if the cluster size changes
  vars {
    size = "${var.masters}"
  }
}

module "ca" {
  source            = "github.com/tamsky/tf_tls/ca"
  organization      = "${var.organization}"
  ca_count          = "${var.masters + var.workers + var.edge-routers}"
  deploy_ssh_hosts  = "${concat(digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  ssh_user          = "core"
  ssh_private_key   = "${tls_private_key.ssh.private_key_pem}"
}

module "etcd_cert" {
  source             = "../certs/etcd"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
}

module "kube_master_certs" {
  source                = "github.com/tamsky/tf_tls/kubernetes/master"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses          = "${compact(digitalocean_droplet.master.*.ipv4_address)}"
  deploy_ssh_hosts      = "${compact(digitalocean_droplet.master.*.ipv4_address)}"
  dns_names             = ["test"]
  master_count          = "${var.masters}"
  validity_period_hours = "8760"
  early_renewal_hours   = "720"
  ssh_user              = "core"
  ssh_private_key       = "${tls_private_key.ssh.private_key_pem}"
}

module "kube_kubelet_certs" {
  source                = "github.com/tamsky/tf_tls/kubernetes/kubelet"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses          = "${concat( digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  deploy_ssh_hosts      = "${concat( digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  kubelet_count         = "${var.masters + var.workers + var.edge-routers}"
  validity_period_hours = "8760"
  early_renewal_hours   = "720"
  ssh_user              = "core"
  ssh_private_key       = "${tls_private_key.ssh.private_key_pem}"
}

module "kube_admin_cert" {
  source                = "github.com/tamsky/tf_tls/kubernetes/admin"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  kubectl_server_ip     = "${digitalocean_droplet.master.0.ipv4_address}"
}

module "docker_daemon_certs" {
  source                = "github.com/tamsky/tf_tls/docker/daemon"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses_list     = "${concat(digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  deploy_ssh_hosts      = "${concat(digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  docker_daemon_count   = "${var.masters + var.workers + var.edge-routers}"
  private_key           = "${tls_private_key.ssh.private_key_pem}"
  validity_period_hours = 8760
  early_renewal_hours   = 720
  user                  = "core"
}

module "docker_client_certs" {
  source                = "github.com/tamsky/tf_tls/docker/client"
  ca_cert_pem           = "${module.ca.ca_cert_pem}"
  ca_private_key_pem    = "${module.ca.ca_private_key_pem}"
  ip_addresses_list     = "${concat(digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  deploy_ssh_hosts      = "${concat(digitalocean_droplet.edge-router.*.ipv4_address, concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
  docker_client_count   = "${var.masters + var.workers + var.edge-routers}"
  private_key           = "${tls_private_key.ssh.private_key_pem}"
  validity_period_hours = 8760
  early_renewal_hours   = 720
  user                  = "core"
}

resource "template_file" "master_cloud_init" {
  template   = "master-cloud-config.yml.tpl"
  depends_on = ["template_file.etcd_discovery_url"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, "\n", "\\n")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, "\n", "\\n")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, "\n", "\\n")}"
  }
}

resource "template_file" "worker_cloud_init" {
  template   = "worker-cloud-config.yml.tpl"
  depends_on = ["template_file.etcd_discovery_url"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, "\n", "\\n")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, "\n", "\\n")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, "\n", "\\n")}"
  }
}

resource "template_file" "edge-router_cloud_init" {
  template   = "edge-router-cloud-config.yml.tpl"
  depends_on = ["template_file.etcd_discovery_url"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, "\n", "\\n")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, "\n", "\\n")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, "\n", "\\n")}"
  }
}

# Masters
resource "digitalocean_droplet" "master" {
  image              = "${var.coreos_image}"
  region             = "${var.region}"
  count              = "${var.masters}"
  name               = "kube-master-${count.index}"
  size               = "${var.master_instance_type}"
  private_networking = true
  user_data          = "${template_file.master_cloud_init.rendered}"
  ssh_keys = [
    "${digitalocean_ssh_key.default.id}"
  ]

  # Do some early bootstrapping of the CoreOS machines. This will install
  # python and pip so we can use as the ansible_python_interpreter in our playbooks
  connection {
    user                = "core"
    private_key         = "${tls_private_key.ssh.private_key_pem}"
  }
  provisioner "file" {
    source      = "../scripts/coreos"
    destination = "/tmp"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod -R +x /tmp/coreos",
      "/tmp/coreos/bootstrap.sh",
      "~/bin/python /tmp/coreos/get-pip.py",
      "sudo mv /tmp/coreos/runner ~/bin/pip && sudo chmod 0755 ~/bin/pip",
      "sudo rm -rf /tmp/coreos"
    ]
  }
}

# Workers
resource "digitalocean_droplet" "worker" {
  image              = "${var.coreos_image}"
  region             = "${var.region}"
  count              = "${var.workers}"
  name               = "kube-worker-${count.index}"
  size               = "${var.worker_instance_type}"
  private_networking = true
  user_data          = "${template_file.worker_cloud_init.rendered}"
  ssh_keys = [
    "${digitalocean_ssh_key.default.id}"
  ]
  # Do some early bootstrapping of the CoreOS machines. This will install
  # python and pip so we can use as the ansible_python_interpreter in our playbooks
  connection {
    user                = "core"
    private_key         = "${tls_private_key.ssh.private_key_pem}"
  }
  provisioner "file" {
    source      = "../scripts/coreos"
    destination = "/tmp"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod -R +x /tmp/coreos",
      "/tmp/coreos/bootstrap.sh",
      "~/bin/python /tmp/coreos/get-pip.py",
      "sudo mv /tmp/coreos/runner ~/bin/pip && sudo chmod 0755 ~/bin/pip",
      "sudo rm -rf /tmp/coreos"
    ]
  }
}

# Edge-routers
resource "digitalocean_droplet" "edge-router" {
  image              = "${var.coreos_image}"
  region             = "${var.region}"
  count              = "${var.edge-routers}"
  name               = "kube-edge-router-${count.index}"
  size               = "${var.edge-router_instance_type}"
  private_networking = true
  user_data          = "${template_file.edge-router_cloud_init.rendered}"
  ssh_keys = [
    "${digitalocean_ssh_key.default.id}"
  ]
  # Do some early bootstrapping of the CoreOS machines. This will install
  # python and pip so we can use as the ansible_python_interpreter in our playbooks
  connection {
    user                = "core"
    private_key         = "${tls_private_key.ssh.private_key_pem}"
  }
  provisioner "file" {
    source      = "../scripts/coreos"
    destination = "/tmp"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod -R +x /tmp/coreos",
      "/tmp/coreos/bootstrap.sh",
      "~/bin/python /tmp/coreos/get-pip.py",
      "sudo mv /tmp/coreos/runner ~/bin/pip && sudo chmod 0755 ~/bin/pip",
      "sudo rm -rf /tmp/coreos"
    ]
  }
}

# Outputs
output "master_ips" {
  value = "${join(",", digitalocean_droplet.master.*.ipv4_address)}"
}
output "worker_ips" {
  value = "${join(",", digitalocean_droplet.worker.*.ipv4_address)}"
}
output "edge-router_ips" {
  value = "${join(",", digitalocean_droplet.edge-router.*.ipv4_address)}"
}
