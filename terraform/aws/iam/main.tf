# master
resource "aws_iam_role" "master_role" {
  name               = "master_role"
  path               = "/"
  assume_role_policy = "${file("${path.module}/master-role.json")}"
}

resource "aws_iam_role_policy" "master_policy" {
  name   = "master_policy"
  role   = "${aws_iam_role.master_role.id}"
  policy = "${file("${path.module}/master-policy.json")}"
}

resource "aws_iam_instance_profile" "master_profile" {
  name  = "master_profile"
  roles = ["${aws_iam_role.master_role.name}"]
}

# worker
resource "aws_iam_role" "worker_role" {
  name               = "worker_role"
  path               = "/"
  assume_role_policy = "${file("${path.module}/worker-role.json")}"
}

resource "aws_iam_role_policy" "worker_policy" {
  name   = "worker_policy"
  role   = "${aws_iam_role.worker_role.id}"
  policy = "${file("${path.module}/worker-policy.json")}"
}

resource "aws_iam_instance_profile" "worker_profile" {
  name  = "worker_profile"
  roles = ["${aws_iam_role.worker_role.name}"]
}

# edge-router
resource "aws_iam_role" "edge-router_role" {
  name               = "edge-router_role"
  path               = "/"
  assume_role_policy = "${file("${path.module}/edge-router-role.json")}"
}

resource "aws_iam_role_policy" "edge-router_policy" {
  name   = "edge-router_policy"
  role   = "${aws_iam_role.edge-router_role.id}"
  policy = "${file("${path.module}/edge-router-policy.json")}"
}

resource "aws_iam_instance_profile" "edge-router_profile" {
  name  = "edge-router_profile"
  roles = ["${aws_iam_role.edge-router_role.name}"]
}

# outputs
output "master_profile_name" {
  value = "${aws_iam_instance_profile.master_profile.name}"
}
output "worker_profile_name" {
  value = "${aws_iam_instance_profile.worker_profile.name}"
}
output "edge-router_profile_name" {
  value = "${aws_iam_instance_profile.edge-router_profile.name}"
}
