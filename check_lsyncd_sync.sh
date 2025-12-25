#!/bin/bash
# Script to troubleshoot lsyncd sync issues after role swap
# Usage: ./check_lsyncd_sync.sh

echo "============================================================"
echo "           FusionPBX HA - lsyncd Sync Checker              "
echo "============================================================"
echo ""

# Get current role
server_master=`pcs status resources | awk 'NR==1 {print $5}'`
host=`hostname -I | awk '{print $1}'`

if [[ "${server_master}" = "${host}" ]]; then
    server_mode="Master (Active)"
else
    server_mode="Standby (Passive)"
fi

echo "Current Node Role: $server_mode"
echo "Current Node IP: $host"
echo ""

# Check lsyncd service status
echo "------------------------------------------------------------"
echo "1. Checking lsyncd service status..."
echo "------------------------------------------------------------"
if systemctl is-active --quiet lsyncd; then
    echo "✓ lsyncd service is RUNNING"
    systemctl status lsyncd --no-pager | grep -E "(Active:|Main PID:)"
else
    echo "✗ lsyncd service is NOT RUNNING"
    echo "  Run: systemctl status lsyncd"
fi
echo ""

# Check lsyncd log
echo "------------------------------------------------------------"
echo "2. Checking lsyncd log (last 20 lines)..."
echo "------------------------------------------------------------"
if [ -f /var/log/lsyncd/lsyncd.log ]; then
    tail -n 20 /var/log/lsyncd/lsyncd.log
else
    echo "✗ lsyncd log file not found!"
fi
echo ""

# Check lsyncd status file
echo "------------------------------------------------------------"
echo "3. Checking lsyncd status..."
echo "------------------------------------------------------------"
if [ -f /var/log/lsyncd/lsyncd.status ]; then
    cat /var/log/lsyncd/lsyncd.status
else
    echo "✗ lsyncd status file not found!"
fi
echo ""

# Check config file
echo "------------------------------------------------------------"
echo "4. Checking lsyncd configuration..."
echo "------------------------------------------------------------"
if [ -f /etc/lsyncd/lsyncd.conf.lua ]; then
    echo "Config file exists: /etc/lsyncd/lsyncd.conf.lua"
    echo "Target sync direction:"
    grep "target = " /etc/lsyncd/lsyncd.conf.lua | head -1
else
    echo "✗ Config file not found!"
fi
echo ""

# Check SSH connectivity
echo "------------------------------------------------------------"
echo "5. Checking SSH passwordless access..."
echo "------------------------------------------------------------"
# Extract target IP from config
target_ip=$(grep 'target = ' /etc/lsyncd/lsyncd.conf.lua | head -1 | grep -oP 'root@\K[0-9.]+' | head -1)
if [ ! -z "$target_ip" ]; then
    echo "Testing SSH to target node: $target_ip"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$target_ip 'echo OK' 2>/dev/null | grep -q OK; then
        echo "✓ SSH passwordless access is working to $target_ip"
    else
        echo "✗ SSH passwordless access FAILED to $target_ip"
        echo "  Setup SSH keys:"
        echo "  ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
        echo "  ssh-copy-id root@$target_ip"
    fi
else
    echo "✗ Cannot determine target IP from config"
fi
echo ""

# Test manual sync
echo "------------------------------------------------------------"
echo "6. Test Manual Sync (create test file)..."
echo "------------------------------------------------------------"
test_file="/etc/freeswitch/lsyncd_test_$(date +%s).txt"
echo "Creating test file: $test_file"
echo "Test sync at $(date)" > $test_file

echo "Waiting 20 seconds for lsyncd to sync..."
sleep 20

if [ ! -z "$target_ip" ]; then
    echo "Checking if file exists on target node..."
    if ssh root@$target_ip "test -f $test_file && echo EXISTS" | grep -q EXISTS; then
        echo "✓ SYNC WORKING! Test file found on target node"
        rm -f $test_file
        ssh root@$target_ip "rm -f $test_file"
    else
        echo "✗ SYNC FAILED! Test file NOT found on target node"
        echo "  Troubleshooting steps:"
        echo "  1. Check lsyncd log: tail -f /var/log/lsyncd/lsyncd.log"
        echo "  2. Restart lsyncd: systemctl restart lsyncd"
        echo "  3. Test manual rsync:"
        echo "     rsync -avz $test_file root@$target_ip:$test_file"
    fi
else
    echo "Cannot perform sync test - target IP not found"
fi
echo ""

echo "============================================================"
echo "                    Check Complete                          "
echo "============================================================"
