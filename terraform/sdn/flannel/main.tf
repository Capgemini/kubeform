# Render network part of cloud-init
resource "template_file" "flannel" {
  template = "${file("${path.module}/flannel.tpl")}"
}

output "cloud_config" {
  value = "${template_file.flannel.rendered}"
}
