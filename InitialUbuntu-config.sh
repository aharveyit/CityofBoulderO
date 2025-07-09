#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo " This script must be run as root"
   exit 1
fi

# Prompt for new hostname
read -p "Enter new hostname: " NEW_HOSTNAME  
hostnamectl set-hostname "$NEW_HOSTNAME"
echo " Hostname changed to $NEW_HOSTNAME"

# Installing services
echo " Installing Ping services"
apt install iputils-ping

echo "installing network manager" 
apt install network-manager 

echo " starting services"
sudo systemctl start NetworkManager.service 

sudo systemctl enable NetworkManager.service

echo " install nano"
sudo apt install nano

echo "install vm tools"
sudo apt install open-vm-tools –y

echo " create log file for sssd"  # notice this was not created and would erro out
sudo mkdir -p /var/log/sssd


# Prompt for AD domain and credentials  # no boulder.local or Cobntdomain no fqdn
read -p "Enter AD Username: " AD_USER

# Install required ad packages
echo "Installing AD packages"
apt install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common-bin packagekit


#join domain
realm join --user=$AD_USER boulder.local

if [[ $? -ne 0 ]]; then
  echo " Failed to join domain. Please check credentials and network settings."
  exit 1
fi

echo " Joined to domain: boulder.local"

# Verify domain joined
realm list


# Only make the change if the line exists and is currently set to true
SSSD_FILE="/etc/sssd/sssd.conf"
  sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
  sudo systemctl restart sssd
  echo " Updated 'use_fully_qualified_names' to false in $SSSD_FILE"

# Restart SSSD to apply change
sudo systemctl restart sssd

echo "add group to the sudoers file"
echo "%boulder.local\\SG-LinuxAdmin ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/domainadmins # creates the file SG-Linuxadmin then adds the AD group
echo "%SG-LinuxAdmin ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/domainadmins # creates the file SG-Linuxadmin then adds the AD group
sudo chmod 440 /etc/sudoers.d/domainadmins
echo "Sudoers file created for group it-sysadmin-linux"
echo " restarting sssd"
 sudo systemctl restart sssd  # notice that a restart was needed








