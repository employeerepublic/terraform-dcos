#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# need to switch off SELinux to restart journald
sudo setenforce 0

echo ">>> Set up filesystem mounts"
sudo tee /etc/systemd/system/dcos_vol_setup.service <<- EOF
[Unit]
Description=Initial setup of volume mounts
DefaultDependencies=no
Before=local-fs-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/dcos_vol_setup.sh /dev/xvde /var/log
ExecStart=/usr/local/sbin/dcos_vol_setup.sh /dev/xvdf /var/lib/dcos
ExecStart=/usr/local/sbin/dcos_vol_setup.sh /dev/xvdg /var/lib/mesos
ExecStart=/usr/local/sbin/dcos_vol_setup.sh /dev/xvdh /var/lib/docker
ExecStart=/usr/local/sbin/dcos_vol_setup.sh /dev/xvdi /home/centos

[Install]
RequiredBy=local-fs-pre.target
EOF
sudo systemctl enable dcos_vol_setup
sudo systemctl start dcos_vol_setup
