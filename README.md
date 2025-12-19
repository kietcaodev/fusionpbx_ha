# FusionPBX High Availability with PostgreSQL Cluster

## Overview

This script automates the installation and configuration of a High Availability (HA) FusionPBX system with PostgreSQL cluster backend.

**Architecture:**
- 2 FusionPBX nodes (Master/Standby) with Corosync, PCS, and Pacemaker
- 3-node PostgreSQL HA Cluster accessible via HAProxy
- Floating IP for seamless failover
- Real-time file synchronization using lsyncd

**License:** Proprietary - Basebs_PBX LLC Company  
**Version:** 1.0  
**Date:** 18-Dec-2025

---

## Prerequisites

### Hardware Requirements
- **Minimum 2 servers** for FusionPBX nodes (Master + Standby)
- **3 separate servers** for PostgreSQL HA cluster (already installed)
- Each server should have at least:
  - 4 CPU cores
  - 8 GB RAM
  - 100 GB storage

### Network Requirements
- All servers must be on the same network segment
- SSH root access between all nodes
- Internet connectivity on all servers
- A floating/virtual IP address available

### Software Prerequisites
- **Operating System:** Debian 10/11 or Ubuntu 20.04/22.04
- **FusionPBX** already installed on both nodes
- **PostgreSQL HA Cluster** (3 nodes) with HAProxy configured
- **Required packages** (auto-installed by script):
  - pcs
  - corosync
  - pacemaker
  - lsyncd
  - rsync

---

## Installation Steps

### 1. Prepare Configuration

The script will prompt for the following information:
- **IP Master (sip-ipt01):** Primary FusionPBX node IP
- **IP Standby (sip-ipt02):** Secondary FusionPBX node IP
- **VIP Listen:** Floating IP address for HA
- **hacluster password:** Password for cluster authentication
- **Database password:** PostgreSQL database password

### 2. Setup PostgreSQL HA Cluster First

**IMPORTANT:** Before running this script, you must:

1. Install PostgreSQL HA Cluster (3 nodes)
2. Configure HAProxy on both FusionPBX nodes pointing to PostgreSQL cluster
3. Backup and restore FusionPBX database to the PostgreSQL cluster
4. Ensure HAProxy is accessible on port 5000 (localhost)

### 3. Run the Installation Script

```bash
chmod +x ha_fusionpbx_postgresql_cluster.sh
./ha_fusionpbx_postgresql_cluster.sh
```

The script will:
- Create configuration file (`config.txt`)
- Configure hostname resolution
- Setup cluster authentication
- Create and start the cluster
- Configure floating IP
- Setup file synchronization (lsyncd)
- Create cluster management commands
- Verify database connectivity

### 4. Resume Installation

If the script is interrupted, it will automatically resume from the last completed step. The progress is saved in `step.txt`.

---

## Post-Installation

### Verify Cluster Status

```bash
role
```

This command shows:
- Current server role (Master/Standby)
- Cluster status
- Resource status
- IP addresses
- System uptime

### Switch Master/Standby Roles

```bash
bascul
```

This command performs a controlled failover:
- Moves all resources from Master to Standby
- Switches the floating IP
- **WARNING:** All active calls will be dropped during switchover

---

## File Synchronization

The following directories are synchronized from Master to Standby:

**FreeSwitch:**
- `/etc/freeswitch/`
- `/etc/default/freeswitch`
- `/var/lib/freeswitch/`
- `/var/log/freeswitch/`
- `/usr/lib/freeswitch/`
- `/usr/bin/freeswitch`
- `/usr/share/freeswitch/`
- `/usr/include/freeswitch/`
- `/run/freeswitch/`

**FusionPBX:**
- `/etc/fusionpbx/`
- `/var/www/fusionpbx/`
- `/var/cache/fusionpbx/`
- `/var/backups/fusionpbx/`
- `/run/fusionpbx/`
- `/etc/nginx/sites-enabled/fusionpbx`
- `/etc/nginx/sites-available/fusionpbx`

**Sync Interval:** 15 seconds (configurable in `/etc/lsyncd/lsyncd.conf.lua`)

---

## Cluster Management Commands

### Check Cluster Status
```bash
pcs status
```

### Manually Move Resource
```bash
pcs resource move <resource_name> <target_node>
```

### Standby a Node
```bash
pcs node standby <node_name>
```

### Unstandby a Node
```bash
pcs node unstandby <node_name>
```

### Cleanup Resources
```bash
pcs resource cleanup
```

### Refresh Resources
```bash
pcs resource refresh
```

---

## Security Considerations

⚠️ **IMPORTANT SECURITY WARNINGS:**

### 1. Configuration File Security

The `config.txt` file contains sensitive information in plain text:
- hacluster password
- Database password

**Recommended Actions:**
```bash
# Set restrictive permissions
chmod 600 config.txt

# Delete after installation
rm -f config.txt

# Or move to secure location
mv config.txt /root/.fusionpbx_ha_config
chmod 600 /root/.fusionpbx_ha_config
```

### 2. SSH Key Authentication

Replace password-based SSH with key-based authentication:
```bash
# Generate SSH key on master
ssh-keygen -t rsa -b 4096

# Copy to standby
ssh-copy-id root@<standby_ip>
```

### 3. Firewall Configuration

Ensure these ports are accessible between nodes:
- **2224/tcp** - PCS daemon
- **3121/tcp** - Pacemaker
- **5403/tcp** - Corosync (multicast)
- **5405/tcp** - Corosync (multicast)
- **21064/tcp** - DLM
- **SSH (22/tcp)** - Remote management
- **5000/tcp** - PostgreSQL HAProxy (localhost only)

### 4. Database Security

- Use `.pgpass` file instead of `PGPASSWORD` environment variable
- Never commit `config.txt` to version control
- Use strong passwords (20+ characters)

---

## Troubleshooting

### Cluster Not Starting

```bash
# Check cluster status
pcs status

# Check corosync
systemctl status corosync

# Check pacemaker
systemctl status pacemaker

# Check logs
journalctl -xe
```

### Resources Not Starting

```bash
# Cleanup resources
pcs resource cleanup

# Refresh resources
pcs resource refresh

# Check resource constraints
pcs constraint show
```

### Database Connection Issues

```bash
# Test HAProxy
systemctl status haproxy

# Test PostgreSQL connection
psql -h 127.0.0.1 -p 5000 -U postgres -d fusionpbx

# Check HAProxy logs
tail -f /var/log/haproxy.log
```

### File Sync Not Working

```bash
# Check lsyncd status
systemctl status lsyncd

# Check lsyncd logs
tail -f /var/log/lsyncd/lsyncd.log

# Test rsync manually
rsync -avz /etc/freeswitch/ root@<standby_ip>:/etc/freeswitch/
```

### Split-Brain Scenario

If both nodes think they are master:

```bash
# On one node (choose which should be standby)
pcs node standby <this_node>

# Wait for resources to migrate
sleep 30

# Unstandby the node
pcs node unstandby <this_node>
```

---

## Important Notes

1. **Database Location:** All database data resides in the PostgreSQL HA cluster, NOT on FusionPBX nodes
2. **Failover Time:** Typical failover takes 10-30 seconds
3. **Active Calls:** All active calls will be dropped during failover
4. **Registrations:** SIP devices will automatically re-register after failover
5. **Maintenance:** Always use `pcs node standby` before performing maintenance

---

## Files Generated

- **config.txt** - Configuration file (⚠️ contains passwords)
- **step.txt** - Installation progress tracker
- **/etc/lsyncd/lsyncd.conf.lua** - File synchronization configuration
- **/usr/bin/bascul** - Failover command
- **/usr/bin/role** - Status command
- **/etc/profile.d/fusionpbx_welcome.sh** - Login banner

---

## Support

For issues or questions:
- Check logs: `journalctl -xe`
- Cluster status: `pcs status`
- Review configuration: `pcs config show`

---

## Changelog

### Version 1.0 (18-Dec-2025)
- Initial release
- FusionPBX 2-node HA cluster
- PostgreSQL 3-node cluster integration
- HAProxy load balancer support
- lsyncd file synchronization
- Automatic failover with floating IP

---

## License

This software is proprietary and owned by Basebs_PBX LLC Company.  
Unauthorized copying, modification, or distribution is prohibited.

---

## Architecture Diagram

```
                    [Floating IP: VIP]
                           |
        +------------------+------------------+
        |                                     |
   [Master Node]                        [Standby Node]
   - FusionPBX                          - FusionPBX
   - FreeSwitch                         - FreeSwitch
   - HAProxy                            - HAProxy
   - lsyncd (sync →)                    - lsyncd
        |                                     |
        +------------------+------------------+
                           |
                    [HAProxy Port 5000]
                           |
        +------------------+------------------+
        |                  |                  |
   [PostgreSQL 1]   [PostgreSQL 2]   [PostgreSQL 3]
   (Primary/Standby) (Standby)       (Standby)
   
   - Streaming Replication
   - Automatic Failover
   - Data Persistence
```

---

**⚠️ Always test in a non-production environment first!**
