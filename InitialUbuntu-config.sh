#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo " This script must be run as root"
   exit 1
fi


# Access and use GitHub token
TOKEN_FILE="/etc/.secrets/github_token"

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo " GitHub token not found at $TOKEN_FILE"
  exit 1
fi

GIT_TOKEN=$(< "$TOKEN_FILE")

# Optional: Test API access to GitHub
echo " Testing GitHub API access with token..."
curl -s -H "Authorization: token $GIT_TOKEN" https://api.github.com/user | grep "login"

if [[ $? -ne 0 ]]; then
  echo " GitHub token may be invalid or access is restricted."
  exit 2
fi

echo " GitHub token is valid."

# Optional: Clone a private repo using token
# NOTE: The token must be URL-encoded if it contains special characters
REPO_URL="https://$GIT_TOKEN@github.com/aharveyit/CityofBoulder.git"
CLONE_DIR="/opt/CityofBoulder"

echo " Cloning repo into $CLONE_DIR..."
git clone "$REPO_URL" "$CLONE_DIR"

if [[ $? -eq 0 ]]; then
  echo " Repository cloned successfully."
else
  echo " Failed to clone repository. Check token and repo URL."
fi



# Prompt for new hostname
read -p "Enter new hostname: " NEW_HOSTNAME  
hostnamectl set-hostname "$NEW_HOSTNAME"
echo " Hostname changed to $NEW_HOSTNAME"

# Installing services
echo " Installing Ping services"
apt install iputils-ping -y

echo "installing network manager" 
apt install network-manager -y

echo " restarting services"
sudo systemctl restart NetworkManager.service


echo " install nano"
sudo apt install nano -y

echo "install vm tools"
sudo apt install open-vm-tools –y

echo " create log file for sssd"  # notice this was not created and would error out
sudo mkdir -p /var/log/sssd


# Install required ad packages
echo "Installing AD packages"
apt install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common-bin packagekit


# Prompt for AD username
#read -p "Enter AD Username: " AD_USER

# Prompt for OU in DN format
read -p "Enter target OU for this linux machine (e.g., OU=LinuxInfra,OU=Servers,DC=boulder,DC=local): " COMPUTER_OU

# Allow up to 3 attempts for correct password

MAX_ATTEMPTS=3
attempt=1
LDAP_SERVER="msdc20.boulder.local"
AD_DOMAIN="boulder.local"

read -p "Enter AD Username: " AD_USER

while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  read -s -p "Enter Password for $AD_USER@$AD_DOMAIN (attempt $attempt of $MAX_ATTEMPTS): " AD_PASS
  echo

  # Define the command in a variable
  LDAP_CMD="ldapwhoami -x -D \"$AD_USER@$AD_DOMAIN\" -w \"$AD_PASS\" -H ldap://$LDAP_SERVER"

  # Run the command and capture output
  OUTPUT=$(eval "$LDAP_CMD" 2>/dev/null)

  # Check if output contains the username
  if echo "$OUTPUT" | grep -qi "$AD_USER"; then
    echo " Credentials verified. Output: $OUTPUT"
    #unset AD_PASS
    break
  else
    echo " Invalid credentials or unexpected output."
    ((attempt++))
  fi

  if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
    echo " Maximum attempts reached. Exiting."
    exit 1
  fi
done

# Install required AD packages
echo "Installing AD packages"
apt install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common-bin packagekit

# Join domain with specified OU
#echo "$AD_PASS" | realm join --user="$AD_USER" --computer-ou="$COMPUTER_OU" boulder.local

sudo apt install expect -y

expect <<EOF
spawn realm join --user="$AD_USER" --computer-ou="$COMPUTER_OU" boulder.local
expect "Password for $AD_USER:"
send "$AD_PASS\r"
expect eof
EOF

if [[ $? -ne 0 ]]; then
  echo "Failed to join domain. Please check network or domain settings."
  exit 1
fi

echo "Successfully joined to domain: boulder.local in OU: $COMPUTER_OU"

# Clear the password from memory
unset AD_PASS

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

read -p "Configure a static IP address? (y/n): " SET_STATIC

#Set network Static
if [[ "$SET_STATIC" =~ ^[Yy]$ ]]; then
  NET_IFACE=$(ip -o -4 route show to default | awk '{print $5}')

  read -p "Enter static IP address (e.g., 192.168.1.50/24): " STATIC_IP
  read -p "Enter default gateway (e.g., 192.168.1.1): " GATEWAY
  read -p "Enter DNS servers (comma-separated, e.g., 8.8.8.8,1.1.1.1): " DNS

  NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

  # Backup and remove the old netplan config
  if [[ -f "$NETPLAN_FILE" ]]; then
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak"
    rm "$NETPLAN_FILE"
  fi

  # Create new netplan config
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $NET_IFACE:
      dhcp4: no
      addresses:
        - $STATIC_IP
      gateway4: $GATEWAY
      nameservers:
        addresses: [${DNS//,/ , }]
EOF

  echo "Applying new network settings..."
  netplan apply

  if [[ $? -ne 0 ]]; then
    echo "Failed to apply static IP configuration. Please check your inputs."
    exit 1
  else
    echo "Static IP configuration applied to $NET_IFACE."
  fi
else
  echo "Skipping static IP configuration."
fi






