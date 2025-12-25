# Troubleshooting lsyncd Sync Issues After Role Swap

## Problem
After swapping nodes (standby becomes master), new files created on the new master are not syncing to the old master (now standby).

## Root Causes

### 1. SSH Passwordless Authentication Not Setup
**Symptom:** lsyncd cannot connect to the other node

**Check:**
```bash
# On current active node, test SSH to the other node
ssh -o BatchMode=yes root@<OTHER_NODE_IP> 'echo OK'
```

**Solution:**
```bash
# Run the setup script (copies it to both nodes)
./setup_ssh_keys.sh
```

**Manual Setup:**
```bash
# On BOTH nodes, run:
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
ssh-copy-id root@<OTHER_NODE_IP>
```

### 2. lsyncd Service Not Running After Swap
**Symptom:** Service shows as stopped or inactive

**Check:**
```bash
pcs status resources
systemctl status lsyncd
```

**Solution:**
```bash
# Let pacemaker manage it
pcs resource cleanup lsyncd
pcs resource refresh lsyncd

# Or manually restart
systemctl restart lsyncd
```

### 3. lsyncd Config Points to Wrong Direction
**Symptom:** Files sync in wrong direction or not at all

**Check:**
```bash
grep "target = " /etc/lsyncd/lsyncd.conf.lua
# Should point to the OTHER node's IP
```

**Explanation:**
- Master node (10.0.0.10) has config that syncs TO Standby (10.0.0.20)
- Standby node (10.0.0.20) has config that syncs TO Master (10.0.0.10)
- After swap, Standby (10.0.0.20) becomes active and its lsyncd runs
- It syncs back to old Master (10.0.0.10) - this is CORRECT
- The config is already correct, just verify SSH keys work

### 4. File Permissions or Directory Not Exists
**Symptom:** Specific directories not syncing

**Check:**
```bash
# Check if directories exist and have correct ownership
ls -la /etc/freeswitch
ls -la /var/www/fusionpbx
```

**Solution:**
```bash
# Ensure directories exist on BOTH nodes with correct ownership
chown -R www-data:www-data /var/www/fusionpbx
chown -R freeswitch:freeswitch /etc/freeswitch
```

## Quick Diagnostic Script

Run this on the CURRENT ACTIVE NODE:
```bash
chmod +x check_lsyncd_sync.sh
./check_lsyncd_sync.sh
```

This will:
1. Show current node role (Master/Standby)
2. Check lsyncd service status
3. Show recent lsyncd logs
4. Test SSH connectivity
5. Create a test file and verify it syncs

## Step-by-Step Troubleshooting

### Step 1: Check Current Role
```bash
role
# or
pcs status
```

### Step 2: Check lsyncd Service
```bash
systemctl status lsyncd
journalctl -u lsyncd -n 50
```

### Step 3: Check lsyncd Logs
```bash
tail -f /var/log/lsyncd/lsyncd.log
cat /var/log/lsyncd/lsyncd.status
```

### Step 4: Test SSH Connection
```bash
# Get target IP from config
grep "target = " /etc/lsyncd/lsyncd.conf.lua | head -1

# Test SSH (replace IP with target from above)
ssh -o BatchMode=yes root@TARGET_IP 'echo OK'

# If fails, setup SSH keys
ssh-copy-id root@TARGET_IP
```

### Step 5: Manual Sync Test
```bash
# Create test file
echo "test" > /etc/freeswitch/test_sync.txt

# Wait 20 seconds
sleep 20

# Check on other node
ssh root@OTHER_NODE_IP 'ls -la /etc/freeswitch/test_sync.txt'
```

### Step 6: Manual rsync Test
```bash
# If lsyncd not working, test rsync manually
rsync -avz /etc/freeswitch/test_sync.txt root@OTHER_NODE_IP:/etc/freeswitch/

# If this works but lsyncd doesn't, restart lsyncd
systemctl restart lsyncd
```

## Common Errors and Solutions

### Error: "Permission denied (publickey,password)"
**Solution:** SSH keys not setup
```bash
./setup_ssh_keys.sh
```

### Error: "cannot get absolute path of dir"
**Solution:** Trying to sync a file instead of directory (already fixed in latest version)

### Error: "Normal: Finished a list = /..."
**This is NORMAL** - means lsyncd completed a sync cycle

### Error: "Error: Failure on startup"
**Solution:** Check config syntax
```bash
lsyncd --nodaemon /etc/lsyncd/lsyncd.conf.lua
# Press CTRL+C after checking for errors
```

## Prevention

### Always Setup SSH Keys During Installation
The main installation script now reminds you to setup SSH keys. Make sure to run:
```bash
./setup_ssh_keys.sh
```

### Verify Bidirectional SSH BEFORE First Swap
```bash
# On Master
ssh root@STANDBY_IP 'echo "Master to Standby OK"'

# On Standby  
ssh root@MASTER_IP 'echo "Standby to Master OK"'
```

### Test Sync After Installation
```bash
# On Master, create test file
echo "test from master" > /etc/freeswitch/master_test.txt
sleep 20
ssh root@STANDBY_IP 'cat /etc/freeswitch/master_test.txt'

# On Standby, create test file
ssh root@STANDBY_IP 'echo "test from standby" > /etc/freeswitch/standby_test.txt'
sleep 20
cat /etc/freeswitch/standby_test.txt
```

## Architecture Reminder

```
┌─────────────────────────────────────────────────────────────┐
│                    lsyncd Bidirectional Sync                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Master (Active)              Standby (Passive)             │
│  ┌──────────────┐            ┌──────────────┐             │
│  │ lsyncd       │            │ lsyncd       │             │
│  │ RUNNING      │            │ STOPPED      │             │
│  │ syncs ──────►│────────────│  (inactive)  │             │
│  └──────────────┘            └──────────────┘             │
│                                                             │
│  After Swap:                                                │
│                                                             │
│  Master (was Standby)        Standby (was Master)          │
│  ┌──────────────┐            ┌──────────────┐             │
│  │ lsyncd       │            │ lsyncd       │             │
│  │ RUNNING      │            │ STOPPED      │             │
│  │ syncs ──────►│────────────│  (inactive)  │             │
│  └──────────────┘            └──────────────┘             │
│                                                             │
│  Each node has config to sync TO the OTHER node            │
│  Only active node runs lsyncd service                       │
└─────────────────────────────────────────────────────────────┘
```

## Need Help?

1. Run diagnostic script: `./check_lsyncd_sync.sh`
2. Check full logs: `journalctl -u lsyncd -f`
3. Test manual rsync to isolate the issue
4. Verify SSH keys work in BOTH directions
