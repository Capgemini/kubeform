module "master_amitype" {
  source        = "github.com/terraform-community-modules/tf_aws_virttype"
  instance_type = "${var.master_instance_type}"
}

module "master_ami" {
  source   = "github.com/terraform-community-modules/tf_aws_coreos_ami"
  region   = "${var.region}"
  channel  = "${var.coreos_channel}"
  virttype = "${module.master_amitype.prefer_hvm}"
}

data "template_file" "master_cloud_init" {
  template   = "${file("master-cloud-config.yml.tpl")}"
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

resource "aws_instance" "master" {
  instance_type        = "${var.master_instance_type}"
  ami                  = "${module.master_ami.ami_id}"
  iam_instance_profile = "${module.iam.master_profile_name}"
  count                = "${var.masters}"
  key_name             = "${module.aws-keypair.keypair_name}"
  subnet_id            = "${element(split(",", module.public_subnet.subnet_ids), count.index)}"
  source_dest_check    = false
  security_groups      = ["${module.sg-default.security_group_id}"]
  user_data            = "${data.template_file.master_cloud_init.rendered}"
  tags = {
    Name   = "kube-master-${count.index}"
    role   = "masters"
    region = "${var.region}"
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

module "master_elb" {
  source             = "../elb"
  security_groups    = "${module.sg-default.security_group_id}"
  instances          = "${compact(aws_instance.master.*.id)}"
  subnets            = "${compact(split(",", module.public_subnet.subnet_ids))}"
}

output "master_ips" {
  value = "${join(",", aws_instance.master.*.public_ip)}"
}
output "master_elb_hostname" {
  value = "${module.master_elb.elb_dns_name}"
}
