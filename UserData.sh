#!/bin/bash
sudo echo ECS_CLUSTER=poc-gs-lms-vam-1111 >> /etc/ecs/ecs.config
#### Configure YUM repository using Proxy ########
sudo chmod 777 /etc/yum.conf
sudo echo "proxy=http://use-proxy.ad.evoncloud.com:8080" >> /etc/yum.conf
sudo chmod 644 /etc/yum.conf
sudo yum install wget -y
sudo yum install unzip -y
sudo cat << EOF >> /etc/profile
export http_proxy=http://use-proxy.ad.evoncloud.com:8080
export https_proxy=http://use-proxy.ad.evoncloud.com:8080
export HTTP_PROXY=http://use-proxy.ad.evoncloud.com:8080
export HTTPS_PROXY=http://use-proxy.ad.evoncloud.com:8080 
EOF
source /etc/profile
set -o xtrace
IP=`ifconfig | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1 | sed 's/\./-/g'`

##### Antivirus agent installation ###########
wget https://gs-bootstrap-bucket.s3.amazonaws.com/AgentDeploymentScriptlinux.sh
chmod -R 777 AgentDeploymentScriptlinux.sh
sudo bash -x AgentDeploymentScriptlinux.sh
####################################################

###### DNS and DHCP Configuration #####################
sudo sed -i '4inameserver 127.0.0.1' /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

######### SIEM Integration  ############################
sudo echo "*.info  @10.64.105.52" >> /etc/rsyslog.conf
sudo systemctl restart rsyslog & sudo systemctl status rsyslog
####################################################################

######## DNS MASQ configuration for amazonaws.com resolution ##########
sudo yum install dnsmasq rsync bind-utils -y && sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf_bkp
sudo cat << EOF > /etc/dnsmasq.conf
listen-address=127.0.0.1
server=/amazonaws.com/172.29.168.130
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now --no-block docker
sudo systemctl restart dnsmasq && yum update -y
########################################################################

########## Security Hardening of the server #############################
echo "Installing hardening script"
wget https://gs-bootstrap-bucket.s3.amazonaws.com/hardeningscript_linux.sh
chmod -R 777 hardeningscript_linux.sh
sudo bash -x hardeningscript_linux.sh
sudo systemctl daemon-reload
##########################################################################

############# Qualys Agent Integration  ####################################
wget https://gs-bootstrap-bucket.s3.amazonaws.com/qualys-cloud-agent.x86_64.rpm
sudo rpm -ivh qualys-cloud-agent.x86_64.rpm
sudo /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh ActivationId=c08c7906-338a-4ca6-9148-2b8eb3038463 CustomerId=03952c71-bb64-e01d-82ae-a7f4f0158820
sudo touch /etc/sysconfig/qualys-cloud-agent && sudo chmod 777 /etc/sysconfig/qualys-cloud-agent
sudo echo https_proxy=http://use-proxy.ad.evoncloud.com:8080 > /etc/sysconfig/qualys-cloud-agent
sudo echo qualys_https_proxy=http://use-proxy.ad.evoncloud.com:8080 >> /etc/sysconfig/qualys-cloud-agent
sudo chmod 755 /etc/sysconfig/qualys-cloud-agent
sudo systemctl enable qualys-cloud-agent
sudo systemctl restart qualys-cloud-agent
###############################################################################

############# FireEye Agent Installation #######################################
wget https://gs-bootstrap-bucket.s3.amazonaws.com/IMAGE_HX_AGENT_LINUX_29.7.12_MODIFIED-fire-eye_new.tar
wget https://gs-bootstrap-bucket.s3.amazonaws.com/test_sth-fire-eye_new.json
sudo tar -xvzf IMAGE_HX_AGENT_LINUX_29.7.12_MODIFIED-fire-eye_new.tar
sudo yum install -y xagt-29.7.12-1.el7.x86_64.rpm
sudo sed -i "s/172.29.153.132/use-proxy.ad.evoncloud.com/g" agent_config.json
sudo cat agent_config.json > /opt/fireeye/agent_config.json
sudo /opt/fireeye/bin/xagt -i /opt/fireeye/agent_config.json
sudo systemctl restart xagt && sleep 2 && sudo systemctl status xagt && sudo systemctl enable xagt && sleep 2
sudo /opt/fireeye/bin/xagt -g /var/log/agent.log
####################################################################################

wget https://gs-bootstrap-bucket.s3.amazonaws.com/Assessment_script_S376.zip
unzip Assessment_script_S376.zip && chmod -R 777 Assessment_script_S376 && cd Assessment_script_S376

########## Local User Creation for administration ######################################
echo " local user creation"
sudo useradd gsluser
echo gsluser:gsluser | sudo chpasswd
sudo useradd gsluser2
echo gsluser2:gsluser2 | sudo chpasswd
echo 'gsluser ALL=(ALL)       ALL' | sudo EDITOR='tee -a' visudo
echo 'gsluser2 ALL=(root) NOPASSWD:/usr/bin/docker exec *, /usr/bin/docker run -itd *,/bin/docker logs *,/bin/docker ps' | sudo EDITOR='tee -a' visudo
echo '%EVOC_MGMT_USRS_PROD      ALL=(ALL)    NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo
echo '%EVOC_FINGMS_USRS_PRD_RW  ALL=(gsluser) ALL' | sudo EDITOR='tee -a' visudo
echo '%EVOC_FINGMS_USRS_PRD_RO  ALL=(gsluser2) ALL' | sudo EDITOR='tee -a' visudo

file=/etc/ssh/sshd_config
sudo cp -p $file $file.old &&
sudo awk '
$1=="PasswordAuthentication" {$2="yes"}
{print}
' $file.old > $file
sudo systemctl restart sshd
##########################################################################################

##### Configurations for AD Integration   ##########################################
echo "AD Integration"
wget https://gs-bootstrap-bucket.s3.amazonaws.com/LDAP_nslcd_Rhel_AmznLinux.sh
sudo chmod -R 777 LDAP_nslcd_Rhel_AmznLinux.sh
sudo bash -x LDAP_nslcd_Rhel_AmznLinux.sh
sudo systemctl restart nslcd
sudo systemctl restart sshd
######################################################################################

############ Configure AWS CLI #################################
echo " INSTALLING AWS CLI"
sudo yum install python3 -y 
sudo pip3 install awscli
sudo aws --version  
#################################################################

###### EFS Mount creation ########################################
echo "MOUNTING EFS"
sudo systemctl enable nfs-utils
sudo systemctl start nfs-utils
sudo mkdir /finaclegs && sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport fs-58845cad.efs.us-east-1.amazonaws.com:/ /finaclegs && sudo chmod -R 777 /finaclegs
###################################################################