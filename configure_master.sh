#!/bin/bash

# set kubernetes network variables
podNetworkCidr=172.16.0.0/16
serviceCidr=10.96.0.0/24
masterIp=192.168.7.186
apiServer=https://${masterIp}:6443
hostname=$(hostname)

# configute kubelet and run
awk '/ExecStart=/ && !x {print "Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs\""; x=1} 1' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > tmp && mv tmp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed 's/\$KUBELET_CERTIFICATE_ARGS/& \$KUBELET_CGROUP_ARGS/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

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


# configure ovn
ovn-nbctl set-connection ptcp:6641
ovn-sbctl set-connection ptcp:6642

# init cluster
kubeadm init --apiserver-advertise-address ${masterIp} --pod-network-cidr ${podNetworkCidr} --service-cidr ${serviceCidr}

# setup kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -au):$(id -g) $HOME/.kube/config

# create rbac for ovn

cat > /opt/ovn-kubernetes-rbac.yaml <<- END
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ovn-controller
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: ovn-controller
rules:
  - apiGroups:
      - ""
      - networking.k8s.io
    resources:
      - pods
      - services
      - endpoints
      - namespaces
      - networkpolicies
      - nodes
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes
      - pods
    verbs:
      - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: ovn-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ovn-controller
subjects:
- kind: ServiceAccount
  name: ovn-controller
  namespace: kube-system
END

kubectl create -f /opt/ovn-kubernetes-rbac.yaml

# get token
until  kubectl get secrets -n kube-system | grep ovn-controller-token ; do echo "waiting for ovn-controller-token"; sleep 1; done
token=$(kubectl get secrets -n kube-system $(kubectl get secrets -n kube-system | grep ovn-controller-token | cut -f1 -d ' ') -o yaml | grep token: | cut -f2 -d":" | tr -d ' ' | tr -d '\t' | base64 -d)

# config ovn
cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/
[Service]
ExecStart=/usr/bin/ovnkube -init-master ${hostname} \
                           -init-node ${hostname} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${token}" \
                           -nodeport \
                           -k8s-apiserver "${apiServer}" \
                           -cluster-subnet "${podNetworkCidr}" \
                           -service-cluster-ip-range "${serviceCidr}" \
                           -net-controller \
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

# start ovn
systemctl enable ovnkube.service
systemctl start ovnkube.service

echo "Token: ${token}";
