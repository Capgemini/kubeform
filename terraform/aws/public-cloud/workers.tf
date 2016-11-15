module "worker_amitype" {
  source        = "github.com/terraform-community-modules/tf_aws_virttype"
  instance_type = "${var.worker_instance_type}"
}

module "worker_ami" {
  source   = "github.com/terraform-community-modules/tf_aws_coreos_ami"
  region   = "${var.region}"
  channel  = "${var.coreos_channel}"
  virttype = "${module.worker_amitype.prefer_hvm}"
}

data "template_file" "worker_cloud_init" {
  template   = "${file("worker-cloud-config.yml.tpl")}"
  depends_on = ["null_resource.etcd_discovery_url"]
  vars {
    etcd_discovery_url = "${file(var.etcd_discovery_url_file)}"
    size               = "${var.masters}"
    region             = "${var.region}"
    etcd_ca            = "${replace(module.ca.ca_cert_pem, "\n", "\\n")}"
    etcd_cert          = "${replace(module.etcd_cert.etcd_cert_pem, "\n", "\\n")}"
    etcd_key           = "${replace(module.etcd_cert.etcd_private_key, "\n", "\\n")}"
  }
}

resource "aws_instance" "worker" {
  instance_type        = "${var.worker_instance_type}"
  ami                  = "${module.worker_ami.ami_id}"
  iam_instance_profile = "${module.iam.worker_profile_name}"
  count                = "${var.workers}"
  key_name             = "${module.aws-keypair.keypair_name}"
  subnet_id            = "${element(split(",", module.public_subnet.subnet_ids), count.index)}"
  source_dest_check    = false
  security_groups      = ["${module.sg-default.security_group_id}"]
  depends_on           = ["aws_instance.master"]
  user_data            = "${data.template_file.worker_cloud_init.rendered}"
  tags = {
    Name   = "kube-worker-${count.index}"
    role   = "workers"
    region = "${var.region}"
  }
  ebs_block_device {
    device_name           = "/dev/xvdb"
    volume_size           = "${var.worker_ebs_volume_size}"
    delete_on_termination = true
  }
  connection {
    user                = "core"
    private_key         = "${tls_private_key.ssh.private_key_pem}"
  }
  provisioner "file" {
    source      = "../../scripts/coreos"
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

output "worker_ips" {
  value = "${join(",", aws_instance.worker.*.public_ip)}"
}
