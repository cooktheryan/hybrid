#!/bin/bash

read -p "Please provide an initial openshift username: " username
echo "Please provide the password for $username: "
read -s password
echo "Enter your email address"
read -s auth_user
echo "Enter your auth token"
read -s auth_password
 
subscription-manager repos --disable="*"
subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-fast-datapath-rpms" --enable="rhel-7-server-ansible-2.4-rpms"
yum -y update
yum -y install wget git net-tools git net-tools bind-utils iptables-services bridge-utils bash-completion httpd-tools nodejs qemu-img kexec-tools sos psacct docker-1.13.1 ansible gcc python-setuptools
yum -y install docker-1.13.1
yum -y install PyYAML
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install --enablerepo="epel" jq
systemctl enable docker
systemctl start docker
git clone https://github.com/openshift/openshift-ansible.git /usr/share/ansible/openshift-ansible
cd /usr/share/ansible/openshift-ansible
git checkout release-3.10
cd ~

# Enable what is needed for windows nodes
yum install -y python-dns
yum -y install --enablerepo="epel" python-devel krb5-devel krb5-libs krb5-workstation python-kerberos python-setuptools
yum -y install --enablerepo="epel" python-pip
pip install "pywinrm>=0.2.2"
pip install pywinrm[kerberos]



cat <<EOF > /home/${AUSERNAME}/.ansible.cfg
[defaults]
remote_tmp     = ~/.ansible/tmp
local_tmp      = ~/.ansible/tmp
host_key_checking = False
forks=30
gather_timeout=60
timeout=240
library = /usr/share/ansible:/usr/share/ansible/openshift-ansible/library
[ssh_connection]
control_path = ~/.ansible/cp/ssh%%h-%%p-%%r
ssh_args = -o ControlMaster=auto -o ControlPersist=600s -o ControlPath=~/.ansible/cp-%h-%p-%r
EOF

cat <<EOF > /etc/ansible/hosts
[OSEv3:children]
masters
nodes
etcd
new_nodes
new_masters

[OSEv3:vars]
openshift_web_console_install=False 
openshift_enable_service_catalog=False 
openshift_hosted_manage_router=False 
openshift_hosted_manage_registry=False 
openshift_hosted_manage_registry_console=False
ansible_ssh_user=root
#410 begin
openshift_release=v3.10
openshift_docker_additional_registries=registry.reg-aws.openshift.com:443
oreg_url=registry.reg-aws.openshift.com:443/openshift3/ose-\${component}:\${version}
oreg_auth_user=${auth_user}
oreg_auth_password=${auth_password}
openshift_disable_check=memory_availability,disk_availability,docker_image_availability
#310end
openshift_use_openshift_sdn=false
os_sdn_network_plugin_name=cni
openshift_disable_check=memory_availability,disk_availability,docker_storage,package_version,docker_image_availability,package_availability
openshift_examples_modify_imagestreams=true
openshift_clock_enabled=true
openshift_enable_service_catalog=false
debug_level=2
console_port=8443
docker_udev_workaround=True
openshift_node_debug_level="{{ node_debug_level | default(debug_level, true) }}"
openshift_master_debug_level="{{ master_debug_level | default(debug_level, true) }}"
openshift_master_access_token_max_seconds=2419200
openshift_hosted_router_replicas=3
openshift_hosted_registry_replicas=1
openshift_master_api_port="{{ console_port }}"
openshift_master_console_port="{{ console_port }}"
openshift_override_hostname_check=true
osm_use_cockpit=false
openshift_install_examples=true
deployment_type=openshift-enterprise
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider'}]
openshift_master_manage_htpasswd=false

openshift_master_default_subdomain=app.$1
openshift_public_hostname=$1

[masters]
$1 openshift_node_group_name="node-config-master" openshift_hostname=$1

[etcd]
$1 openshift_hostname=$1

[new_nodes]
[new_masters]

[nodes]
$1 openshift_node_group_name="node-config-master" openshift_hostname=$1
EOF

cat <<EOF > ~/postinstall.yml
---
- hosts: masters
  vars:
    description: "auth users"
    AUSERNAME: $username
    PASSWORD: $password
  tasks:
  - name: Create Master Directory
    file: path=/etc/origin/master state=directory
  - name: add initial user to Red Hat OpenShift Container Platform
    shell: htpasswd -c -b /etc/origin/master/htpasswd ${AUSERNAME} ${PASSWORD}

EOF


cat <<EOF > ~/openshift-install.sh
ansible-playbook  /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml < /dev/null
ansible-playbook  /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml < /dev/null || true

yum -y install atomic-openshift-clients
EOF

chmod +x ~/openshift-install.sh
~/openshift-install.sh | tee openshift-install.out
