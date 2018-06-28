#!/bin/bash

# Run this script only after init_worker.sh -> kubeadm join command

# set kubernetes network variables
podNetworkCidr=10.48.0.0/16
serviceCidr=172.16.1.0/24
masterIp=192.168.7.186
apiServer=https://${masterIp}:6443
hostname=$(hostname)
interfaceName=enp0s31f6
gatewayAddress=192.168.7.1
token=

# configure kubelet
awk '/ExecStart=/ && !x {print "Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs\""; x=1} 1' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > tmp && mv tmp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's/\$KUBELET_CERTIFICATE_ARGS/& \$KUBELET_CGROUP_ARGS/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's/--cluster-dns=10.96.0.10/--cluster-dns=172.16.1.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# restart kublet
systemctl daemon-reload
systemctl restart kubelet

# prevent egg-chicken problem after reboot
echo "OPTIONS=--delete-transient-ports" >> /etc/default/openvswitch

# configure cni
cat << EOF > /etc/openvswitch/ovn_k8s.conf
[default]
mtu=1500
conntrack-zone=64321
[kubernetes]
cacert=/etc/kubernetes/pki/ca.crt
[logging]
loglevel=5
logfile=/var/log/ovnkube.log
[cni]
conf-dir=/etc/cni/net.d
plugin=ovn-k8s-cni-overlay
EOF

mkdir -p /etc/cni/net.d/
echo '{"name":"ovn-kubernetes", "type":"ovn-k8s-cni-overlay"}' > /etc/cni/net.d/10-ovn-kubernetes.conf

# run kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# config ovn
cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/
[Service]
ExecStart=/usr/bin/ovnkube -init-node ${hostname} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${token}" \
                           -nodeport \
                           -init-gateways \
                           -k8s-apiserver "https://${masterIp}:6443" \
                           -cluster-subnet "${podNetworkCidr}" \
                           -service-cluster-ip-range "${serviceCidr}" \
                           -gateway-nexthop "${gatewayAddress}" \
                           -gateway-interface "${interfaceName}" \
                           -nb-address "tcp://${masterIp}:6641" \
                           -sb-address "tcp://${masterIp}:6642" \
                           -loglevel 5 \
                           -logfile /var/log/ovnkube.log
Restart=always
StartLimitInterval=0
RestartSec=10
[Install]
WantedBy=multi-user.target
END

# run ovn
systemctl enable ovnkube.service
systemctl start ovnkube.service
