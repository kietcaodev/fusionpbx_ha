#!/bin/bash
# Setup SSH passwordless authentication for lsyncd bidirectional sync
# This ensures both nodes can sync to each other after role swap

if [ ! -f config.txt ]; then
    echo "Error: config.txt not found! Run main installation script first."
    exit 1
fi

# Load configuration
n=1
while read line; do
    case $n in
        1) ip_master=$line ;;
        2) ip_standby=$line ;;
    esac
    n=$((n+1))
done < config.txt

echo "============================================================"
echo "     Setup SSH Passwordless Authentication for lsyncd      "
echo "============================================================"
echo ""
echo "Master IP:  $ip_master"
echo "Standby IP: $ip_standby"
echo ""
echo "This script will setup SSH keys on both nodes for bidirectional sync"
read -p "Press ENTER to continue or CTRL+C to cancel..."
echo ""

# Setup on Master node
echo "------------------------------------------------------------"
echo "Step 1: Setup SSH keys on Master node"
echo "------------------------------------------------------------"
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating SSH key on Master..."
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
    echo "✓ SSH key generated"
else
    echo "✓ SSH key already exists"
fi

echo "Copying SSH key to Standby node..."
ssh-copy-id -o StrictHostKeyChecking=no root@$ip_standby
echo "✓ SSH key copied to Standby"
echo ""

# Test SSH from Master to Standby
echo "Testing SSH connection Master -> Standby..."
if ssh -o BatchMode=yes root@$ip_standby 'echo OK' 2>/dev/null | grep -q OK; then
    echo "✓ SSH passwordless access working: Master -> Standby"
else
    echo "✗ SSH passwordless access FAILED: Master -> Standby"
    exit 1
fi
echo ""

# Setup on Standby node
echo "------------------------------------------------------------"
echo "Step 2: Setup SSH keys on Standby node"
echo "------------------------------------------------------------"
if ! ssh root@$ip_standby "test -f ~/.ssh/id_rsa"; then
    echo "Generating SSH key on Standby..."
    ssh root@$ip_standby 'ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa'
    echo "✓ SSH key generated on Standby"
else
    echo "✓ SSH key already exists on Standby"
fi

echo "Copying SSH key from Standby to Master..."
# Get the public key from standby and add to master's authorized_keys
standby_pubkey=$(ssh root@$ip_standby 'cat ~/.ssh/id_rsa.pub')
if ! grep -q "$standby_pubkey" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$standby_pubkey" >> ~/.ssh/authorized_keys
    echo "✓ Standby SSH key added to Master"
else
    echo "✓ Standby SSH key already in Master's authorized_keys"
fi
echo ""

# Test SSH from Standby to Master
echo "Testing SSH connection Standby -> Master..."
if ssh root@$ip_standby "ssh -o BatchMode=yes root@$ip_master 'echo OK' 2>/dev/null" | grep -q OK; then
    echo "✓ SSH passwordless access working: Standby -> Master"
else
    echo "✗ SSH passwordless access FAILED: Standby -> Master"
    exit 1
fi
echo ""

echo "============================================================"
echo "              SSH Keys Setup Complete!                      "
echo "============================================================"
echo ""
echo "Both nodes can now SSH to each other without password."
echo "lsyncd bidirectional sync should work after role swap."
echo ""
echo "To verify, run on each node:"
echo "  ./check_lsyncd_sync.sh"
echo ""
