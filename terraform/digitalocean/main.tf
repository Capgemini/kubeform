variable "do_token" {}
variable "organization" { default = "kubeform" }
variable "region" { default = "lon1" }
variable "masters" { default = "3" }
variable "workers" { default = "1" }
variable "master_instance_type" { default = "512mb" }
variable "worker_instance_type" { default = "512mb" }
variable "etcd_discovery_url_file" { default = "etcd_discovery_url.txt" }
variable "sdn" { default = "flannel" }

/*
  we need to use at least beta because we need rkt version 0.15.0+ to run the
  kubelet wrapper script.
  See https://coreos.com/kubernetes/docs/latest/kubelet-wrapper.html
*/
variable "coreos_image" { default = "coreos-alpha" }

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
  source      = "../certs/ca"

  organization = "${var.organization}"
}

module "etcd_cert" {
  source             = "../certs/etcd"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
}

module "apiserver_certs" {
  source             = "../certs/kubernetes/apiserver"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
  ip_addresses       = "${join(",", digitalocean_droplet.master.*.ipv4_address)}"
  master_count       = "${var.masters}"
}

module "worker_certs" {
  source             = "../certs/kubernetes/worker"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
  ip_addresses       = "${join(",", digitalocean_droplet.worker.*.ipv4_address)}"
  worker_count       = "${var.workers}"
}

module "admin_cert" {
  source             = "../certs/kubernetes/admin"
  ca_cert_pem        = "${module.ca.ca_cert_pem}"
  ca_private_key_pem = "${module.ca.ca_private_key_pem}"
}

module "sdn" {
  source  = "../sdn"
  peers   = "${join(" ", concat(digitalocean_droplet.master.*.ipv4_address, digitalocean_droplet.worker.*.ipv4_address))}"
}

resource "template_file" "master_cloud_init" {
  template   = "master-cloud-config.yml.tpl"
  depends_on = ["template_file.etcd_discovery_url", "module.sdn"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, \"\n\", \"\\n\")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, \"\n\", \"\\n\")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, \"\n\", \"\\n\")}"
    kubernetes_ca      = "${replace(module.ca.ca_cert_pem, \"\n\", \"\\n\")}"
    sdn                = "${sdn.${var.sdn}.cloud_config}"
  }
}

resource "template_file" "worker_cloud_init" {
  template   = "worker-cloud-config.yml.tpl"
  depends_on = ["template_file.etcd_discovery_url"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, \"\n\", \"\\n\")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, \"\n\", \"\\n\")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, \"\n\", \"\\n\")}"
    kubernetes_ca      = "${replace(module.ca.ca_cert_pem, \"\n\", \"\\n\")}"
    sdn                = "${sdn.${var.sdn}.cloud_config}"
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

# Generate certificates for the master apiserver and push them into the instances
resource "null_resource" "configure-master-certs" {
  depends_on = ["digitalocean_droplet.master"]
  count      = "${var.masters}"

  # Changes to the number of masters triggers the provisioner again across
  # all instances.
  triggers {
    master_instances      = "${var.masters}"
    apiserver_private_key = "${module.apiserver_certs.private_key}"
    apiserver_certs_pem   = "${element(split(",", module.apiserver_certs.cert_pems), count.index)}"
  }

  connection {
    user         = "core"
    private_key  = "${tls_private_key.ssh.private_key_pem}"
    host         = "${element(digitalocean_droplet.master.*.ipv4_address, count.index)}"
  }
  provisioner "remote-exec" {
    inline = [
      "echo '${module.apiserver_certs.private_key}' | sudo tee /etc/kubernetes/ssl/apiserver-key.pem",
      "echo '${element(split(",", module.apiserver_certs.cert_pems), count.index)}' | sudo tee /etc/kubernetes/ssl/apiserver.pem",
      "sudo chmod 600 /etc/kubernetes/ssl/apiserver-key.pem",
      "sudo chmod 644 /etc/kubernetes/ssl/apiserver.pem"
    ]
  }
}

# Generate a cert for each worker machine and push it into the instances
resource "null_resource" "configure-worker-certs" {
  depends_on = ["digitalocean_droplet.worker"]
  count      = "${var.workers}"

  # Changes to the number of workers triggers the provisioner again across
  # all instances.
  triggers {
    worker_instances   = "${var.workers}"
    worker_private_key = "${module.worker_certs.private_key}"
    worker_certs_pem   = "${element(split(",", module.worker_certs.cert_pems), count.index)}"
  }

  connection {
    user         = "core"
    private_key  = "${tls_private_key.ssh.private_key_pem}"
    host         = "${element(digitalocean_droplet.worker.*.ipv4_address, count.index)}"
  }
  provisioner "remote-exec" {
    inline = [
      "echo '${module.worker_certs.private_key}' | sudo tee /etc/kubernetes/ssl/worker-key.pem",
      "echo '${element(split(",", module.worker_certs.cert_pems), count.index)}' | sudo tee /etc/kubernetes/ssl/worker.pem",
      "sudo chmod 600 /etc/kubernetes/ssl/worker-key.pem",
      "sudo chmod 644 /etc/kubernetes/ssl/worker.pem"
    ]
  }
}

# kubectl config
resource "null_resource" "kubectl-cfg" {
  depends_on = ["digitalocean_droplet.master"]

  triggers {
    ca_pem            = "${module.ca.ca_cert_pem}"
    admin_private_key = "${module.admin_cert.private_key}"
    admin_certs_pem   = "${module.admin_cert.cert_pem}"
  }

  # export certificates for kubectl
  provisioner "local-exec" {
    command = "echo '${module.ca.ca_cert_pem}' | tee ${path.module}/ca.pem && chmod 644 ${path.module}/ca.pem"
  }
  provisioner "local-exec" {
    command = "echo '${module.admin_cert.cert_pem}' | tee ${path.module}/admin.pem && chmod 644 ${path.module}/admin.pem"
  }
  provisioner "local-exec" {
    command = "echo '${module.admin_cert.private_key}' | tee ${path.module}/admin-key.pem && chmod 600 ${path.module}/admin-key.pem"
  }

  # setup kubectl
  provisioner "local-exec" {
    command = "kubectl config set-cluster default-cluster --server=https://${digitalocean_droplet.master.0.ipv4_address} --certificate-authority=${path.module}/ca.pem"
  }
  provisioner "local-exec" {
    command = "kubectl config set-credentials default-admin --certificate-authority=${path.module}/ca.pem --client-key=${path.module}/admin-key.pem --client-certificate=${path.module}/admin.pem"
  }
  provisioner "local-exec" {
    command = "kubectl config set-context default-system --cluster=default-cluster --user=default-admin"
  }
  provisioner "local-exec" {
    command = "kubectl config use-context default-system"
  }
}

# Outputs
output "master_ips" {
  value = "${join(",", digitalocean_droplet.master.*.ipv4_address)}"
}
output "worker_ips" {
  value = "${join(",", digitalocean_droplet.worker.*.ipv4_address)}"
}
