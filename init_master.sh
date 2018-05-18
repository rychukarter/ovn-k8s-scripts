#!/bin/bash

# preconfig
#echo 'pagoda ALL:(ALL) NOPASSWD:ALL' >> /etc/sudoers

# turn off swap
swapname=$(systemctl --type swap | grep .swap | awk 'NR%3==2{print $1}')
systemctl mask $swapname
sed -e '/swap/ s/^#*/#/' -i /etc/fstab
swapoff -a

# install dependencies
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# add repositories
echo "deb https://packages.wand.net.nz $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/wand.list
curl https://packages.wand.net.nz/keyring.gpg -o /etc/apt/trusted.gpg.d/wand.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update

# install docker
apt-get install docker-ce
groupadd docker
gpasswd -a pagoda docker

# install go
wget -q https://dl.google.com/go/go1.10.1.linux-amd64.tar.gz
tar -xvzf go1.10.1.linux-amd64.tar.gz -C /usr/local
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> $HOME/.profile
source ~/.profile

# install kube
apt-get install -y kubelet kubeadm kubectl

# install ovs and ovn
apt-get build-dep dkms
apt-get install python-six openssl python-pip -y
-H pip install --upgrade pip
apt-get install openvswitch-datapath-dkms -y
apt-get install openvswitch-switch openvswitch-common -y
-H pip install ovs
apt-get install ovn-central ovn-common ovn-host -y

# run
