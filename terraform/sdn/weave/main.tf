# Render network part of cloud-init
resource "template_file" "weave" {
  template = "${file("${path.module}/weave.tpl")}"
}

output "cloud_config" {
  value = "${template_file.weave.rendered}"
}
