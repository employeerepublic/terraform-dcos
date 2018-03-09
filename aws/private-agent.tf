# Private agent instance deploy
resource "aws_instance" "agent" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "${module.aws-tested-oses.user}"

    # The connection will use the local SSH agent for authentication.
  }

  root_block_device {
    volume_size = "${var.aws_agent_instance_disk_size}"
    volume_type = "gp2"
  }

  # /var/log
  ebs_block_device {
    device_name = "/dev/sde"
    volume_type = "gp2"
    volume_size = "20"
    encrypted = "true"
  }

  # /var/lib/dcos
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_type = "gp2"
    volume_size = "50"
    encrypted = "true"
  }

  # /var/lib/mesos
  ebs_block_device {
    device_name = "/dev/sdg"
    volume_type = "gp2"
    volume_size = "50"
    encrypted = "true"
  }

  # /var/lib/docker
  ebs_block_device {
    device_name = "/dev/sdh"
    volume_type = "gp2"
    volume_size = "200"
    encrypted = "true"
  }

  # /home/centos
  ebs_block_device {
    device_name = "/dev/sdi"
    volume_type = "gp2"
    volume_size = "50"
    encrypted = "true"
  }

  # /dcos/volume0
  ebs_block_device {
    device_name = "/dev/sdm"
    volume_type = "gp2"
    volume_size = "100"
    encrypted = "true"
  }

  # /dcos/volume1
  ebs_block_device {
    device_name = "/dev/sdn"
    volume_type = "gp2"
    volume_size = "100"
    encrypted = "true"
  }

  # /dcos/volume2
  ebs_block_device {
    device_name = "/dev/sdo"
    volume_type = "gp2"
    volume_size = "100"
    encrypted = "true"
  }

  # /dcos/volume3
  ebs_block_device {
    device_name = "/dev/sdp"
    volume_type = "gp2"
    volume_size = "100"
    encrypted = "true"
  }

  # # /dcos/volume4
  # ebs_block_device {
  #   device_name = "/dev/sdq"
  #   volume_type = "gp2"
  #   volume_size = "250"
  #   encrypted = "true"
  # }

  count = "${var.num_of_private_agents}"
  instance_type = "${var.aws_agent_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.agent.name}"

  ebs_optimized = "true"

  tags {
   owner = "${coalesce(var.owner, data.external.whoami.result["owner"])}"
   expiration = "${var.expiration}"
   Name =  "${data.template_file.cluster-name.rendered}-pvtagt-${count.index + 1}"
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
    source = "scripts/cloud/aws/setup_private_agent_mounts.sh"
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
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/os-setup.sh",
      "sudo bash /tmp/os-setup.sh",
    ]
  }

  # setting this up to be run after DC/OS has been installed...
  # it needs to be able to change some of the DC/OS config files
  provisioner "file" {
    source = "scripts/os/centos/centos-dcos-postinstall.sh"
    destination = "/tmp/os-dcos-postinstall.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/os-dcos-postinstall.sh",
    ]
  }

  lifecycle {
    ignore_changes = ["tags.Name"]
  }
}

# Create DCOS Mesos Agent Scripts to execute
module "dcos-mesos-agent" {
  source               = "github.com/bernadinm/tf_dcos_core"
  bootstrap_private_ip = "${aws_instance.bootstrap.private_ip}"
  # Only allow upgrade and install as installation mode
  dcos_install_mode = "${var.state == "upgrade" ? "upgrade" : "install"}"
  dcos_version         = "${var.dcos_version}"
  role                 = "dcos-mesos-agent"
}

# Execute generated script on agent
resource "null_resource" "agent" {
  # If state is set to none do not install DC/OS
  count = "${var.state == "none" ? 0 : var.num_of_private_agents}"
  # Changes to any instance of the cluster requires re-provisioning
  triggers {
    cluster_instance_ids = "${null_resource.bootstrap.id}"
    current_ec2_instance_id = "${aws_instance.agent.*.id[count.index]}"
  }
  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    host = "${element(aws_instance.agent.*.public_ip, count.index)}"
    user = "${module.aws-tested-oses.user}"
  }

  count = "${var.num_of_private_agents}"

  # Generate and upload Agent script to node
  provisioner "file" {
    content     = "${module.dcos-mesos-agent.script}"
    destination = "run.sh"
  }

  # Wait for bootstrapnode to be ready
  provisioner "remote-exec" {
    inline = [
     "until $(curl --output /dev/null --silent --head --fail http://${aws_instance.bootstrap.private_ip}/dcos_install.sh); do printf 'waiting for bootstrap node to serve...'; sleep 20; done"
    ]
  }

  # Install Slave Node
  # - run the postinstall script
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x run.sh",
      "sudo ./run.sh",
      "sudo bash /tmp/os-dcos-postinstall.sh",
    ]
  }
}

output "Private Agent Public IP Address" {
  value = ["${aws_instance.agent.*.public_ip}"]
}
