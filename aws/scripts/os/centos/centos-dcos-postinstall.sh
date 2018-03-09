###### DC/OS config
# particularly for cassandra
# https://docs.datastax.com/en/dse/5.1/dse-dev/datastax_enterprise/config/configRecommendedSettings.html

sudo tee /etc/sysctl.d/99-z-dcos-sysctls.conf <<- EOF
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=10
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=40960
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
vm.max_map_count = 1048575
EOF
sudo sysctl -p /etc/sysctl.d/99-z-dcos-sysctls.conf

# create a user for cassandra containers to run under, and
# give it increased limits

useradd cassandra

sudo tee /etc/security/limits.d/90-cassandra-nproc.conf <<- EOF
root - memlock unlimited
root - nofile 100000
root - nproc 32768
root - as unlimited

cassandra - memlock unlimited
cassandra - nofile 100000
cassandra - nproc 32768
cassandra - as unlimited
EOF
sudo sysctl -p

echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

### dc/os has a bad sysctl in its own config - fix it

if [ -f "/opt/mesosphere/etc/dcos-service-configuration.json" ] ; then

   cat /opt/mesosphere/etc/dcos-service-configuration.json | \
       sudo sed 's%"vm.max_map_count": *[0-9][0-9]*%"vm.max_map_count":1048575%g' > /tmp/dcos-service-configuration.json

   sudo cp /tmp/dcos-service-configuration.json /opt/mesosphere/etc/dcos-service-configuration.json

fi

###### END DC/OS config
