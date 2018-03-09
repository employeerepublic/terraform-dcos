# Private agent instance deploy
resource "aws_instance" "storage" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "${module.aws-tested-oses.user}"

    # The connection will use the local SSH agent for authentication.
  }

  root_block_device {
    volume_size = "${var.aws_storage_instance_disk_size}"
    volume_type = "gp2"
  }

  # /var/log
  ebs_block_device {
    device_name = "/dev/sde"
    volume_type = "gp2"
    volume_size = "20"
    encrypted = "true"
  }

  # /home/centos
  ebs_block_device {
    device_name = "/dev/sdi"
    volume_type = "gp2"
    volume_size = "50"
    encrypted = "true"
  }

  count = "${var.num_of_storage_instances}"
  instance_type = "${var.aws_storage_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.agent.name}"

  ebs_optimized = "true"

  tags {
   owner = "${coalesce(var.owner, data.external.whoami.result["owner"])}"
   expiration = "${var.expiration}"
   Name =  "${data.template_file.cluster-name.rendered}-storage-${count.index + 1}"
   cluster = "${data.template_file.cluster-name.rendered}"
   KubernetesCluster = "${var.kubernetes_cluster}"
  }

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${module.aws-tested-oses.aws_ami}"

  # The name of our SSH keypair we created above.
  key_name = "${var.ssh_key_name}"

  # Our Security group to allow http and SSH access
  vpc_security_group_ids = ["${aws_security_group.private_slave.id}","${aws_security_group.admin.id}","${aws_security_group.any_access_internal.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.private.id}"

  provisioner "file" {
    source = "scripts/cloud/aws/dcos_vol_setup.sh"
    destination = "/tmp/dcos_vol_setup.sh"
  }

  provisioner "file" {
    source = "scripts/cloud/aws/setup_storage_mounts.sh"
    destination = "/tmp/setup_mounts.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/dcos_vol_setup.sh /usr/local/sbin/dcos_vol_setup.sh",
      "sudo chmod +x /usr/local/sbin/dcos_vol_setup.sh",
      "sudo chmod +x /tmp/setup_mounts.sh",
      "sudo bash /tmp/setup_mounts.sh",
    ]
  }

  # OS init script
  provisioner "file" {
   content = "${module.aws-tested-oses.os-setup}"
   destination = "/tmp/os-setup.sh"
  }

 # We run a remote provisioner on the instance after creating it.
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/os-setup.sh",
      "sudo bash /tmp/os-setup.sh",
    ]
  }

  provisioner "file" {
    source = "scripts/os/centos/centos-dcos-postinstall.sh"
    destination = "/tmp/os-dcos-postinstall.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/os-dcos-postinstall.sh",
      "sudo bash /tmp/os-dcos-postinstall.sh",
    ]
  }

  lifecycle {
    ignore_changes = ["tags.Name"]
  }
}

output "Storage instance Private IP Address" {
  value = ["${aws_instance.storage.*.private_ip}"]
}
