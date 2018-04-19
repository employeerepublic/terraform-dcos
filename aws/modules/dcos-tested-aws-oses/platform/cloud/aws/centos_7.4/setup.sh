sudo setenforce 0 && \
sudo sed -i --follow-symlinks 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
sudo tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
# sudo yum -y update --exclude="docker-engine*"
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/override.conf <<- EOF
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay
EOF
sudo yum install -y docker-engine-1.13.1
sudo systemctl start docker
sudo systemctl enable docker
sudo yum install -y wget
sudo yum install -y git
sudo yum install -y unzip
sudo yum install -y curl
sudo yum install -y xz
sudo yum install -y ipset
sudo yum install -y ntp
## <yapster
sudo yum install -y tmux
sudo yum install -y telnet
sudo yum install -y epel-release
sudo yum install -y pssh
sudo yum install -y bzip2
## install GNU parallel for parallel shell scripts
## (useful for driving cassandra sstableloader)
(wget -O - pi.dk/3 || curl pi.dk/3/ || fetch -o - http://pi.dk/3) | bash
## </yapster>
sudo systemctl enable ntpd
sudo systemctl start ntpd
sudo getent group nogroup || sudo groupadd nogroup
sudo getent group docker || sudo groupadd docker

sudo touch /opt/dcos-prereqs.installed
