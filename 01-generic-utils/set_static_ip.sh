#!/bin/bash

# --- CONFIGURATION ---
# Set the desired last octet here
LAST_OCTET=100
# ---------------------

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo "Gathering network information..."

# Detect the active network interface
INTERFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)

# Detect the current gateway ip
GATEWAY=$(ip route show default | awk '/default/ {print $3}' | head -n1)

# Detect the current ip address and subnet mask
CURRENT_IP_CIDR=$(ip -4 -o addr show "$INTERFACE" | awk '{print $4}' | head -n1)

# Extract just the ip address and the prefix
CURRENT_IP=$(echo "$CURRENT_IP_CIDR" | cut -d'/' -f1)
PREFIX=$(echo "$CURRENT_IP_CIDR" | cut -d'/' -f2)

# Construct the new static ip address
# Take the first 3 parts of the current ip and add the desired octet
IP_BASE=$(echo "$CURRENT_IP" | cut -d'.' -f1-3)
NEW_STATIC_IP="$IP_BASE.$LAST_OCTET"

echo "---------------------------------------------"
echo "Interface detected: $INTERFACE"
echo "Current IP:         $CURRENT_IP"
echo "Gateway:            $GATEWAY"
echo "Subnet Prefix:      /$PREFIX"
echo "---------------------------------------------"
echo "Target Static IP:   $NEW_STATIC_IP"
echo "---------------------------------------------"

# Generate the netplan configuration file
# Use a high number to ensure this file takes precedence over default configs
CONFIG_FILE="/etc/netplan/99-static-config.yaml"

echo "Generating Netplan configuration at $CONFIG_FILE..."

cat <<EOF > "$CONFIG_FILE"
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses:
        - $NEW_STATIC_IP/$PREFIX
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

# Set secure permissions for the config file
chmod 600 "$CONFIG_FILE"

# Apply the changes
echo "Applying network configuration..."

echo "The static IP ($NEW_STATIC_IP) will be set permanently."
echo "If you are connected via SSH, your session may disconnect now."

# If this is run via ssh, the session might hang when the ip changes successfully
netplan apply
