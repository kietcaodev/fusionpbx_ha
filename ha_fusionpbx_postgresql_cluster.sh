#!/bin/bash
# This code is the property of Basebs_PBX LLC Company
# License: Proprietary
# Date: 18-Dec-2025
# FusionPBX High Availability with Corosync, PCS and Pacemaker
# Architecture: 2 FusionPBX nodes + 3-node PostgreSQL HA Cluster via HAProxy
#
set -e

function jumpto
{
    label=$start
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

echo -e "\n"
echo -e "************************************************************"
echo -e "*   Welcome to FusionPBX HA installation with PostgreSQL   *"
echo -e "*              HA Cluster Backend                          *"
echo -e "*                All options are mandatory                 *"
echo -e "************************************************************"

filename="config.txt"
if [ -f $filename ]; then
    echo -e "Config file found, loading..."
    n=1
    while read line; do
        case $n in
            1)
                ip_master=$line
              ;;
            2)
                ip_standby=$line
              ;;
            3)
                ip_floating=$line
              ;;
            4)
                hapassword=$line
              ;;
            5)
                db_password=$line
              ;;
        esac
        n=$((n+1))
    done < $filename
    echo -e "IP Master (sip-ipt01).... > $ip_master"
    echo -e "IP Standby (sip-ipt02)... > $ip_standby"
    echo -e "VIP Listen............... > $ip_floating"
    echo -e "hacluster password....... > $hapassword"
    echo -e "Database password........ > ********"
fi

while [[ $ip_master == '' ]]
do
    read -p "IP Master (sip-ipt01).... > " ip_master 
done 

while [[ $ip_standby == '' ]]
do
    read -p "IP Standby (sip-ipt02)... > " ip_standby 
done

while [[ $ip_floating == '' ]]
do
    read -p "VIP Listen............... > " ip_floating 
done 

while [[ $hapassword == '' ]]
do
    read -p "hacluster password....... > " hapassword 
done

while [[ $db_password == '' ]]
do
    read -sp "Database password........ > " db_password
    echo ""
done

echo -e "************************************************************"
echo -e "*                   Check Information                      *"
echo -e "*        Make sure you have internet on both servers       *"
echo -e "*   PostgreSQL HA Cluster should be installed already      *"
echo -e "************************************************************"
while [[ $veryfy_info != yes && $veryfy_info != no ]]
do
    read -p "Are you sure to continue with this settings? (yes,no) > " veryfy_info 
done

if [ "$veryfy_info" = yes ] ;then
    echo -e "************************************************************"
    echo -e "*                Starting to run the scripts               *"
    echo -e "************************************************************"
else
    exit;
fi

cat > config.txt << EOF
$ip_master
$ip_standby
$ip_floating
$hapassword
$db_password
EOF

echo -e "************************************************************"
echo -e "*            Get the hostname in Master and Standby        *"
echo -e "************************************************************"
host_master=`hostname`
host_standby=`ssh root@$ip_standby 'hostname'`
echo -e "Master hostname: $host_master"
echo -e "Standby hostname: $host_standby"
echo -e "*** Done ***"

stepFile=step.txt
if [ -f $stepFile ]; then
    step=`cat $stepFile`
else
    step=1
fi

echo -e "Start in step:" $step

start="create_hostname"
case $step in
    1)
        start="create_hostname"
      ;;
    2)
        start="create_hacluster_password"
      ;;
    3)
        start="starting_pcs"
      ;;
    4)
        start="auth_hacluster"
    ;;
    5)
        start="creating_cluster"
      ;;
    6)
        start="starting_cluster"
      ;;
    7)
        start="creating_floating_ip"
      ;;
    8)
        start="create_lsyncd_config_file"
      ;;
    9)
        start="disable_services"
      ;;
    10)
        start="setting_freeswitch_files"
    ;;
    11)
        start="verify_database_connection"
    ;;
    12)
        start="create_freeswitch_service"
    ;;
    13)
        start="create_lsyncd_service"
    ;;
    14)
        start="basebs_create_switch_node"
    ;;
    15)
        start="basebspbx_create_role"
    ;;
    16)
        start="create_welcome_message"
    ;;
    17)
        start="basebspbx_cluster_ok"
    ;;                
esac
jumpto $start

echo -e "*** Done Step 1 ***"
echo -e "1" > step.txt

create_hostname:
echo -e "************************************************************"
echo -e "*          Creating hosts name in Master/Standby           *"
echo -e "************************************************************"
echo -e "$ip_master \t$host_master" >> /etc/hosts
echo -e "$ip_standby \t$host_standby" >> /etc/hosts
ssh root@$ip_standby "echo -e '$ip_master \t$host_master' >> /etc/hosts"
ssh root@$ip_standby "echo -e '$ip_standby \t$host_standby' >> /etc/hosts"
echo -e "*** Done Step 2 ***"
echo -e "2" > step.txt

create_hacluster_password:
echo -e "************************************************************"
echo -e "*     Create password for hacluster in Master/Standby      *"
echo -e "************************************************************"
echo hacluster:$hapassword | chpasswd
ssh root@$ip_standby "echo hacluster:$hapassword | chpasswd"
echo -e "*** Done Step 3 ***"
echo -e "3" > step.txt

starting_pcs:
echo -e "************************************************************"
echo -e "*         Starting pcsd services in Master/Standby         *"
echo -e "************************************************************"
systemctl start pcsd
ssh root@$ip_standby "systemctl start pcsd"
systemctl enable pcsd.service 
systemctl enable corosync.service 
systemctl enable pacemaker.service
ssh root@$ip_standby "systemctl enable pcsd.service"
ssh root@$ip_standby "systemctl enable corosync.service"
ssh root@$ip_standby "systemctl enable pacemaker.service"

echo -e "*** Done Step 4 ***"
echo -e "4" > step.txt

auth_hacluster:
echo -e "************************************************************"
echo -e "*            Server Authenticate in Master                 *"
echo -e "************************************************************"
yes | pcs cluster destroy
pcs host auth $ip_master $ip_standby -u hacluster -p $hapassword
echo -e "*** Done Step 5 ***"
echo -e "5" > step.txt

creating_cluster:
echo -e "************************************************************"
echo -e "*              Creating Cluster in Master                  *"
echo -e "************************************************************"
pcs cluster setup cluster_FusionPBX_HA $ip_master $ip_standby --force
echo -e "*** Done Step 6 ***"
echo -e "6" > step.txt

starting_cluster:
echo -e "************************************************************"
echo -e "*           Starting/Settings Cluster in Master            *"
echo -e "************************************************************"
pcs cluster start --all
pcs cluster enable --all
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
echo -e "*** Done Step 7 ***"
echo -e "7" > step.txt

creating_floating_ip:
echo -e "************************************************************"
echo -e "*            Creating Floating IP in Master                *"
echo -e "************************************************************"
pcs resource create virtual_ip ocf:heartbeat:IPaddr2 ip=$ip_floating cidr_netmask=24 op monitor interval=30s on-fail=restart
pcs cluster cib drbd_cfg
pcs cluster cib-push drbd_cfg --config
echo -e "*** Done Step 8 ***"
echo -e "8" > step.txt

create_lsyncd_config_file:
echo -e "************************************************************"
echo -e "*          Configure lsync in Server 1 and 2               *"
echo -e "************************************************************"
# Create lsyncd directories on both nodes
if [ ! -d "/etc/lsyncd" ] ;then
    mkdir /etc/lsyncd
fi
if [ ! -d "/var/log/lsyncd" ] ;then
    mkdir /var/log/lsyncd
    touch /var/log/lsyncd/lsyncd.{log,status}
fi

ssh root@$ip_standby "mkdir -p /etc/lsyncd/"
ssh root@$ip_standby "mkdir -p /var/log/lsyncd/"
ssh root@$ip_standby "touch /var/log/lsyncd/lsyncd.{log,status}"

echo -e "Creating lsyncd config for Master -> Standby direction..."
cat > /etc/lsyncd/lsyncd.conf.lua << EOF
----
-- User configuration file for lsyncd.
-- FusionPBX HA Configuration - Full Sync
--
settings {
    logfile = "/var/log/lsyncd/lsyncd.log",
    statusFile = "/var/log/lsyncd/lsyncd.status",
    statusInterval = 20,
    inotifyMode = "CloseWrite",
}

-- Sync /etc/freeswitch directory
sync {
    default.rsync,
    source = "/etc/freeswitch",
    target = "root@$ip_standby:/etc/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/lib/freeswitch directory
sync {
    default.rsync,
    source = "/var/lib/freeswitch",
    target = "root@$ip_standby:/var/lib/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/log/freeswitch directory
sync {
    default.rsync,
    source = "/var/log/freeswitch",
    target = "root@$ip_standby:/var/log/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/lib/freeswitch directory
sync {
    default.rsync,
    source = "/usr/lib/freeswitch",
    target = "root@$ip_standby:/usr/lib/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/share/freeswitch directory
sync {
    default.rsync,
    source = "/usr/share/freeswitch",
    target = "root@$ip_standby:/usr/share/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/include/freeswitch directory
sync {
    default.rsync,
    source = "/usr/include/freeswitch",
    target = "root@$ip_standby:/usr/include/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /run/freeswitch directory
sync {
    default.rsync,
    source = "/run/freeswitch",
    target = "root@$ip_standby:/run/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /etc/fusionpbx directory
sync {
    default.rsync,
    source = "/etc/fusionpbx",
    target = "root@$ip_standby:/etc/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/www/fusionpbx directory
sync {
    default.rsync,
    source = "/var/www/fusionpbx",
    target = "root@$ip_standby:/var/www/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/cache/fusionpbx directory
sync {
    default.rsync,
    source = "/var/cache/fusionpbx",
    target = "root@$ip_standby:/var/cache/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/backups/fusionpbx directory
sync {
    default.rsync,
    source = "/var/backups/fusionpbx",
    target = "root@$ip_standby:/var/backups/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /run/fusionpbx directory
sync {
    default.rsync,
    source = "/run/fusionpbx",
    target = "root@$ip_standby:/run/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

EOF

echo -e "Creating lsyncd config for Standby -> Master direction (reverse sync)..."
cat > /tmp/lsyncd_standby.conf.lua << EOF2
----
-- User configuration file for lsyncd.
-- FusionPBX HA Configuration - Reverse Sync (Standby to Master)
--
settings {
    logfile = "/var/log/lsyncd/lsyncd.log",
    statusFile = "/var/log/lsyncd/lsyncd.status",
    statusInterval = 20,
    inotifyMode = "CloseWrite",
}

-- Sync /etc/freeswitch directory
sync {
    default.rsync,
    source = "/etc/freeswitch",
    target = "root@$ip_master:/etc/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/lib/freeswitch directory
sync {
    default.rsync,
    source = "/var/lib/freeswitch",
    target = "root@$ip_master:/var/lib/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/log/freeswitch directory
sync {
    default.rsync,
    source = "/var/log/freeswitch",
    target = "root@$ip_master:/var/log/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/lib/freeswitch directory
sync {
    default.rsync,
    source = "/usr/lib/freeswitch",
    target = "root@$ip_master:/usr/lib/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/share/freeswitch directory
sync {
    default.rsync,
    source = "/usr/share/freeswitch",
    target = "root@$ip_master:/usr/share/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /usr/include/freeswitch directory
sync {
    default.rsync,
    source = "/usr/include/freeswitch",
    target = "root@$ip_master:/usr/include/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /run/freeswitch directory
sync {
    default.rsync,
    source = "/run/freeswitch",
    target = "root@$ip_master:/run/freeswitch",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /etc/fusionpbx directory
sync {
    default.rsync,
    source = "/etc/fusionpbx",
    target = "root@$ip_master:/etc/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/www/fusionpbx directory
sync {
    default.rsync,
    source = "/var/www/fusionpbx",
    target = "root@$ip_master:/var/www/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/cache/fusionpbx directory
sync {
    default.rsync,
    source = "/var/cache/fusionpbx",
    target = "root@$ip_master:/var/cache/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /var/backups/fusionpbx directory
sync {
    default.rsync,
    source = "/var/backups/fusionpbx",
    target = "root@$ip_master:/var/backups/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

-- Sync /run/fusionpbx directory
sync {
    default.rsync,
    source = "/run/fusionpbx",
    target = "root@$ip_master:/run/fusionpbx",
    rsync = {
        archive = true,
        compress = true,
        verbose = true,
        whole_file = false,
    },
    delay = 15,
    maxProcesses = 1,
}

EOF2

# Copy reverse sync config to standby node
scp /tmp/lsyncd_standby.conf.lua root@$ip_standby:/etc/lsyncd/lsyncd.conf.lua
rm -f /tmp/lsyncd_standby.conf.lua

echo -e "\e[42m SUCCESS: Bidirectional lsyncd configuration created! \e[0m"
echo -e "  - Master syncs TO Standby"
echo -e "  - Standby syncs TO Master"
echo -e "  Whichever node runs lsyncd will sync to the other node."
echo -e ""
echo -e "\e[43m IMPORTANT: SSH Passwordless Setup Required \e[0m"
echo -e "  Run these commands to setup SSH keys for bidirectional sync:"
echo -e "  # On Master node:"
echo -e "  ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
echo -e "  ssh-copy-id root@$ip_standby"
echo -e ""
echo -e "  # On Standby node:"
echo -e "  ssh root@$ip_standby 'ssh-keygen -t rsa -N \"\" -f ~/.ssh/id_rsa'"
echo -e "  ssh root@$ip_standby \"ssh-copy-id root@$ip_master\""
echo -e ""
echo -e "*** Done Step 9 ***"
echo -e "9" > step.txt

disable_services:
echo -e "************************************************************"
echo -e "*             Disable Services in Server 1 and 2           *"
echo -e "************************************************************"
systemctl stop freeswitch
systemctl disable freeswitch
systemctl stop lsyncd
systemctl disable lsyncd
ssh root@$ip_standby "systemctl stop freeswitch"
ssh root@$ip_standby "systemctl disable freeswitch"
ssh root@$ip_standby "systemctl stop lsyncd"
ssh root@$ip_standby "systemctl disable lsyncd"
echo -e "*** Done Step 10 ***"
echo -e "10" > step.txt

setting_freeswitch_files:
echo -e "************************************************************"
echo -e "*          Configure Freeswitch to use Floating IP         *"
echo -e "************************************************************"

# Enable non-local bind for floating IP on both nodes
echo 'net.ipv4.ip_nonlocal_bind=1' >> /etc/sysctl.conf
ssh root@$ip_standby "echo 'net.ipv4.ip_nonlocal_bind=1' >> /etc/sysctl.conf"
sysctl -p
ssh root@$ip_standby "sysctl -p"

echo -e "Syncing FreeSwitch configuration from Master to Standby..."
# Initial sync all FreeSwitch and FusionPBX directories to Standby
rsync -avz --delete /etc/freeswitch/ root@$ip_standby:/etc/freeswitch/
rsync -avz --delete /etc/default/freeswitch root@$ip_standby:/etc/default/freeswitch
rsync -avz --delete /var/lib/freeswitch/ root@$ip_standby:/var/lib/freeswitch/
rsync -avz --delete /var/log/freeswitch/ root@$ip_standby:/var/log/freeswitch/
rsync -avz --delete /usr/lib/freeswitch/ root@$ip_standby:/usr/lib/freeswitch/
rsync -avz --delete /usr/share/freeswitch/ root@$ip_standby:/usr/share/freeswitch/
rsync -avz --delete /usr/include/freeswitch/ root@$ip_standby:/usr/include/freeswitch/
rsync -avz --delete /etc/fusionpbx/ root@$ip_standby:/etc/fusionpbx/
rsync -avz --delete /var/www/fusionpbx/ root@$ip_standby:/var/www/fusionpbx/
rsync -avz /var/cache/fusionpbx/ root@$ip_standby:/var/cache/fusionpbx/
rsync -avz /var/backups/fusionpbx/ root@$ip_standby:/var/backups/fusionpbx/
rsync -avz /etc/nginx/sites-enabled/fusionpbx root@$ip_standby:/etc/nginx/sites-enabled/
rsync -avz /etc/nginx/sites-available/fusionpbx root@$ip_standby:/etc/nginx/sites-available/

echo -e "\e[42m SUCCESS: FreeSwitch configuration synced to Standby node! \e[0m"

echo -e "*** Done Step 11 ***"
echo -e "11" > step.txt

verify_database_connection:
echo -e "************************************************************"
echo -e "*        Verify Database Connection to HA PostgreSQL       *"
echo -e "************************************************************"
echo -e "Checking if HAProxy is running and connecting to PostgreSQL cluster..."

db_check_failed=0

# Test if HAProxy is installed and running on both nodes
if ! systemctl is-active --quiet haproxy; then
    echo -e "\e[43m WARNING: HAProxy is not running on master node! \e[0m"
    db_check_failed=1
else
    echo -e "\e[42m OK: HAProxy is running on master node \e[0m"
fi

if ! ssh root@$ip_standby "systemctl is-active --quiet haproxy"; then
    echo -e "\e[43m WARNING: HAProxy is not running on standby node! \e[0m"
    db_check_failed=1
else
    echo -e "\e[42m OK: HAProxy is running on standby node \e[0m"
fi

# Test PostgreSQL connection via HAProxy on master
if PGPASSWORD="$db_password" psql -h 127.0.0.1 -p 5000 -U postgres -d fusionpbx -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "\e[42m OK: Database connection successful on master node (HAProxy port 5000) \e[0m"
else
    echo -e "\e[43m WARNING: Cannot connect to PostgreSQL via HAProxy on master! \e[0m"
    db_check_failed=1
fi

# Test PostgreSQL connection via HAProxy on standby
if ssh root@$ip_standby "PGPASSWORD='$db_password' psql -h 127.0.0.1 -p 5000 -U postgres -d fusionpbx -c 'SELECT version();' > /dev/null 2>&1"; then
    echo -e "\e[42m OK: Database connection successful on standby node (HAProxy port 5000) \e[0m"
else
    echo -e "\e[43m WARNING: Cannot connect to PostgreSQL via HAProxy on standby! \e[0m"
    db_check_failed=1
fi

if [ $db_check_failed -eq 1 ]; then
    echo -e ""
    echo -e "\e[43m==============================================================\e[0m"
    echo -e "\e[43m                   DATABASE CHECK FAILED                     \e[0m"
    echo -e "\e[43m==============================================================\e[0m"
    echo -e ""
    echo -e "Before continuing, please ensure you have completed:"
    echo -e "  1. Section 5.1-5.4: Install PostgreSQL HA Cluster (3 nodes)"
    echo -e "  2. Section 5.5: Install HAProxy on both FusionPBX nodes"
    echo -e "  3. Section 5.6: Backup and restore FusionPBX database to cluster"
    echo -e ""
    echo -e "FusionPBX HA cluster will NOT work without database!"
    echo -e ""
    
    while [[ $continue_anyway != yes && $continue_anyway != no ]]; do
        read -p "Do you want to continue anyway? (yes/no) > " continue_anyway
    done
    
    if [ "$continue_anyway" != "yes" ]; then
        echo -e "Installation stopped. Please setup PostgreSQL HA cluster first."
        exit 1
    fi
    
    echo -e "\e[43m WARNING: Continuing without database verification... \e[0m"
else
    echo -e "\e[42m SUCCESS: All database connections verified! \e[0m"
fi

echo -e "*** Done Step 12 ***"
echo -e "12" > step.txt

create_freeswitch_service:
echo -e "************************************************************"
echo -e "*          Create Freeswitch Service in Server 1           *"
echo -e "************************************************************"
pcs resource create freeswitch service:freeswitch op monitor interval=30s
pcs cluster cib fs_cfg 
pcs cluster cib-push fs_cfg --config 
pcs -f fs_cfg constraint colocation add freeswitch with virtual_ip INFINITY
pcs -f fs_cfg constraint order virtual_ip then freeswitch
pcs cluster cib-push fs_cfg --config 

# Changing these values from 15s (default) to 120s is very important 
# since depending on the server and the number of extensions 
# the freeswitch can take more than 15s to start
pcs resource update freeswitch op stop timeout=120s
pcs resource update freeswitch op start timeout=120s
pcs resource update freeswitch op restart timeout=120s
echo -e "*** Done Step 13 ***"
echo -e "13" > step.txt

create_lsyncd_service:
echo -e "************************************************************"
echo -e "*             Create lsyncd Service in Server 1            *"
echo -e "************************************************************"

pcs resource create lsyncd service:lsyncd.service op monitor interval=30s
pcs cluster cib fs_cfg
pcs cluster cib-push fs_cfg --config
pcs -f fs_cfg constraint colocation add lsyncd with virtual_ip INFINITY
pcs -f fs_cfg constraint order freeswitch then lsyncd
pcs cluster cib-push fs_cfg --config

echo -e "*** Done Step 14 ***"
echo -e "14" > step.txt

basebs_create_switch_node:
echo -e "************************************************************"
echo -e "*         Creating FusionPBX Cluster basebs Command        *"
echo -e "************************************************************"
cat > /usr/bin/basebs << 'EOF'
#!/bin/bash
# This code is the property of BasebsPBX LLC Company
# License: Proprietary
# Date: 18-Dec-2025
# Change the status of the servers, the Master goes to Standby and the Standby goes to Master.

set -e

progress-bar() {
    local duration=${1}

    already_done() { for ((done=0; done<$elapsed; done++)); do printf ">"; done }
    remaining() { for ((remain=$elapsed; remain<$duration; remain++)); do printf " "; done }
    percentage() { printf "| %s%%" $(( (($elapsed)*100)/($duration)*100/100 )); }
    clean_line() { printf "\r"; }

    for (( elapsed=1; elapsed<=$duration; elapsed++ )); do
        already_done; remaining; percentage
        sleep 1
        clean_line
    done
    clean_line
}

server_a=`pcs status | grep 'Online' | awk '{print $4}'`
server_b=`pcs status | grep 'Online' | awk '{print $5}'`
server_master=`pcs status resources | awk 'NR==1 {print $5}'`

# Perform some validations
if [ "${server_a}" = "" ] || [ "${server_b}" = "" ]
then
    echo -e "\e[41m There are problems with high availability, please check with the command *pcs status* (we recommend applying the command *pcs node unstandby* in both servers) \e[0m"
    exit;
fi

if [[ "${server_master}" = "${server_a}" ]]; then
    host_master=$server_a
    host_standby=$server_b
else
    host_master=$server_b
    host_standby=$server_a
fi

arg=$1
if [ "$arg" = 'yes' ] ;then
    perform_bascul='yes'
fi

# Print a warning message and ask to the user if he wants to continue
echo -e "************************************************************"
echo -e "*     Change the roles of servers in high availability     *"
echo -e "*\e[41m WARNING-WARNING-WARNING-WARNING-WARNING-WARNING-WARNING  \e[0m*"
echo -e "*All calls in progress will be lost and the system will be *"
echo -e "*     unavailable for a few seconds.                       *"
echo -e "*    Database remains in PostgreSQL HA cluster             *"
echo -e "************************************************************"

# Perform a loop until the users confirm if wants to proceed or not
while [[ $perform_bascul != yes && $perform_bascul != no ]]; do
    read -p "Are you sure to switch from $host_master to $host_standby? (yes,no) > " perform_bascul
done

if [[ "${perform_bascul}" = "yes" ]]; then
    # Unstandby both nodes
    pcs node unstandby $host_master
    pcs node unstandby $host_standby

    # Do a loop per resource
    pcs status resources | grep "^s.*s(.*):s.*" | awk '{print $1}' | while read -r resource ; do
        # Skip moving the virtual_ip resource, it will be moved at the end
        if [[ "${resource}" != "virtual_ip" ]]; then
            echo "Moving ${resource} from ${host_master} to ${host_standby}"
            pcs resource move ${resource} ${host_standby}
        fi
    done

    sleep 5 && pcs node standby $host_master & # Standby current Master node after five seconds
    sleep 20 && pcs node unstandby $host_master & # Automatically Unstandby current Master node after 20 seconds

    # Move the Virtual IP resource to standby node
    echo "Moving virtual_ip from ${host_master} to ${host_standby}"
    pcs resource move virtual_ip ${host_standby}

    # End the script
    echo "Becoming ${host_standby} to Master"
    progress-bar 10
    echo "Done"
else
    echo "Nothing to do, bye, bye"
fi

sleep 5
role
EOF
chmod +x /usr/bin/basebs
scp /usr/bin/basebs root@$ip_standby:/usr/bin/basebs
ssh root@$ip_standby 'chmod +x /usr/bin/basebs'
echo -e "*** Done Step 15 ***"
echo -e "15" > step.txt

basebspbx_create_role:
echo -e "************************************************************"
echo -e "*         Creating FusionPBX Cluster role Command          *"
echo -e "************************************************************"
cat > /usr/bin/role << 'EOF'
#!/bin/bash
# This code is the property of BasebsPBX LLC Company
# License: Proprietary
# Date: 18-Dec-2025
# Show the Role of Server in FusionPBX HA Cluster

# Bash Colour Codes
green="\033[00;32m"
txtrst="\033[00;0m"

if [ -f /etc/debian_version ]; then
    linux_ver="Debian "`cat /etc/debian_version`
else
    linux_ver="Unknown"
fi

ha_version="FusionPBX_HA_PostgreSQL_Cluster_v1.0"
server_master=`pcs status resources | awk 'NR==1 {print $5}'`
host=`hostname -I | awk '{print $1}'`

if [[ "${server_master}" = "${host}" ]]; then
    server_mode="Master"
else
    server_mode="Standby"
fi

logo='
███████╗██╗██████╗     ██╗  ██╗ █████╗ 
██╔════╝██║██╔══██╗    ██║  ██║██╔══██╗
███████╗██║██████╔╝    ███████║███████║
╚════██║██║██╔═══╝     ██╔══██║██╔══██║
███████║██║██║         ██║  ██║██║  ██║
╚══════╝╚═╝╚═╝         ╚═╝  ╚═╝╚═╝  ╚═╝
'

echo -e "
${green}
${logo}
${txtrst}
 Role           : $server_mode
 Version        : ${ha_version}
 Linux Version  : ${linux_ver}
 Hostname       : `hostname`
 Uptime         : `uptime | grep -ohe 'up .*' | sed 's/up //g' | awk -F "," '{print $1}'`
 Load           : `uptime | grep -ohe 'load average[s:][: ].*' | awk '{ print "Last Minute: " $3" Last 5 Minutes: "$4" Last 15 Minutes: "$5 }'`
 Users          : `uptime | grep -ohe '[0-9.*] user[s,]'`
 IP Address     : ${green}`ip addr | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | xargs`${txtrst}
 Clock          :`timedatectl | sed -n '/Local time/ s/^[ \t]*Local time:\(.*$\)/\1/p'`
 NTP Sync       :`timedatectl | awk -F: '/System clock synchronized/ {print $2}'`
"

echo -e ""
echo -e "************************************************************"
echo -e "*              FusionPBX Cluster Status                    *"
echo -e "************************************************************"
pcs status 
EOF

chmod +x /usr/bin/role
scp /usr/bin/role root@$ip_standby:/usr/bin/role
ssh root@$ip_standby 'chmod +x /usr/bin/role'
echo -e "*** Done Step 16 ***"
echo -e "16" > step.txt

create_welcome_message:
echo -e "************************************************************"
echo -e "*              Creating Welcome message                    *"
echo -e "************************************************************"
/bin/cp -rf /usr/bin/role /etc/profile.d/fusionpbx_welcome.sh
chmod 755 /etc/profile.d/fusionpbx_welcome.sh
scp /etc/profile.d/fusionpbx_welcome.sh root@$ip_standby:/etc/profile.d/fusionpbx_welcome.sh
ssh root@$ip_standby "chmod 755 /etc/profile.d/fusionpbx_welcome.sh"
echo -e "*** Done Step 17 ***"
echo -e "17" > step.txt

basebspbx_cluster_ok:
echo -e "************************************************************"
echo -e "*           FusionPBX HA Cluster Setup Complete!           *"
echo -e "*                                                          *"
echo -e "*  Architecture:                                           *"
echo -e "*  - 2 FusionPBX nodes (Master/Standby)                    *"
echo -e "*  - 3-node PostgreSQL HA Cluster (via HAProxy)            *"
echo -e "*  - Floating IP: $ip_floating                             *"
echo -e "*                                                          *"
echo -e "*  Don't worry if you still see the status in Stop        *"
echo -e "*  sometimes you have to wait about 30 seconds for it to  *"
echo -e "*  restart completely                                      *"
echo -e "*                                                          *"
echo -e "*  Run 'role' command to check cluster status              *"
echo -e "*  Run 'basebs' command to switch Master/Standby           *"
echo -e "************************************************************"

pcs resource cleanup
pcs resource refresh
sleep 20
role

echo -e ""
echo -e "************************************************************"
echo -e "*                   Installation Complete!                 *"
echo -e "************************************************************"

