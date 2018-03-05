# Reattach the public ELBs to the agents if they change
resource "aws_elb_attachment" "public-agent-elb" {
  count    = "${var.num_of_public_agents}"
  elb      = "${aws_elb.public-agent-elb.id}"
  instance = "${aws_instance.public-agent.*.id[count.index]}"
}

# Public Agent Load Balancer Access
# Adminrouter Only
resource "aws_elb" "public-agent-elb" {
  name = "${data.template_file.cluster-name.rendered}-pub-agt-elb"

  subnets         = ["${aws_subnet.public.id}"]
  security_groups = ["${aws_security_group.public_slave.id}"]
  instances       = ["${aws_instance.public-agent.*.id}"]

  listener {
    lb_port           = 80
    instance_port     = 80
    lb_protocol       = "tcp"
    instance_protocol = "tcp"
  }

  listener {
    lb_port           = 443
    instance_port     = 443
    lb_protocol       = "tcp"
    instance_protocol = "tcp"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 2
    target = "HTTP:9090/_haproxy_health_check"
    interval = 5
  }

  lifecycle {
    ignore_changes = ["name"]
  }
}

resource "aws_instance" "public-agent" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "${module.aws-tested-oses.user}"

    # The connection will use the local SSH agent for authentication.
  }

  root_block_device {
    volume_size = "${var.aws_public_agent_instance_disk_size}"
    volume_type = "gp2"
    volume_size = "8"
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
    volume_size = "10"
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

  count = "${var.num_of_public_agents}"
  instance_type = "${var.aws_public_agent_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.agent.name}"

  ebs_optimized = "true"

  tags {
   owner = "${coalesce(var.owner, data.external.whoami.result["owner"])}"
   expiration = "${var.expiration}"
   Name =  "${data.template_file.cluster-name.rendered}-pubagt-${count.index + 1}"
   cluster = "${data.template_file.cluster-name.rendered}"
   KubernetesCluster = "${var.kubernetes_cluster}"
  }

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${module.aws-tested-oses.aws_ami}"

  # The name of our SSH keypair we created above.
  key_name = "${var.ssh_key_name}"

  # Our Security group to allow http and SSH access
  vpc_security_group_ids = ["${aws_security_group.public_slave.id}","${aws_security_group.admin.id}","${aws_security_group.any_access_internal.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.public.id}"

  provisioner "file" {
    source = "scripts/cloud/aws/dcos_vol_setup.sh"
    destination = "/tmp/dcos_vol_setup.sh"
  }

  provisioner "file" {
    source = "scripts/cloud/aws/setup_public_agent_mounts.sh"
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

# Create DCOS Mesos Public Agent Scripts to execute
module "dcos-mesos-agent-public" {
  source               = "github.com/bernadinm/tf_dcos_core"
  bootstrap_private_ip = "${aws_instance.bootstrap.private_ip}"
  # Only allow upgrade and install as installation mode
  dcos_install_mode = "${var.state == "upgrade" ? "upgrade" : "install"}"
  dcos_version         = "${var.dcos_version}"
  role                 = "dcos-mesos-agent-public"
}

# Execute generated script on agent
resource "null_resource" "public-agent" {
  # If state is set to none do not install DC/OS
  count = "${var.state == "none" ? 0 : var.num_of_public_agents}"
  # Changes to any instance of the cluster requires re-provisioning
  triggers {
    cluster_instance_ids = "${null_resource.bootstrap.id}"
    current_ec2_instance_id = "${aws_instance.public-agent.*.id[count.index]}"
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    host = "${element(aws_instance.public-agent.*.public_ip, count.index)}"
    user = "${module.aws-tested-oses.user}"
  }

  count = "${var.num_of_public_agents}"

  # Generate and upload Agent script to node
  provisioner "file" {
    content     = "${module.dcos-mesos-agent-public.script}"
    destination = "run.sh"
  }

  # Wait for bootstrapnode to be ready
  provisioner "remote-exec" {
    inline = [
     "until $(curl --output /dev/null --silent --head --fail http://${aws_instance.bootstrap.private_ip}/dcos_install.sh); do printf 'waiting for bootstrap node to serve...'; sleep 20; done"
    ]
  }

  # Install Slave Node
  # - and run the postinstall script
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x run.sh",
      "sudo ./run.sh",
      "sudo bash /tmp/os-dcos-postinstall.sh",
    ]
  }
}

output "Public Agent ELB Address" {
  value = "${aws_elb.public-agent-elb.dns_name}"
}

output "Public Agent Public IP Address" {
  value = ["${aws_instance.public-agent.*.public_ip}"]
}
