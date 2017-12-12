#!/bin/bash

INSTALL_FILE="/home/user/splunkforwarder-7.0.1-2b5b15c4ee89-Linux-x86_64.tgz"

DEPLOY_SERVER="servername:8089"
PASSWORD=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 60)
INSTALL_LOCATION="/opt"
SPLUNKUSER=splunk

# check for root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
  else echo "[!] Thx for running as root. Continuing..."
fi

# unpack tarball to install location
echo "[*] Unpacking Tarball"
sudo tar -xzf $INSTALL_FILE -C $INSTALL_LOCATION


# create Splunk user account
if id $SPLUNKUSER >/dev/null 2>&1; then
  echo "Splunk user already exists, no changes"
else
  echo "[*] Creating splunk user for service account"
  sudo useradd -m -r $SPLUNKUSER
fi


echo "[*] Changing ownership of Splunk Forwarder folders"
chown -R $SPLUNKUSER:$SPLUNKUSER $INSTALL_LOCATION/splunkforwarder

echo "[*] Doing initial run of Splunk install"
sudo -u $SPLUNKUSER $INSTALL_LOCATION/splunkforwarder/bin/splunk start --accept-license --answer-yes --auto-ports --no-prompt

# enable boot-start, set to run as user splunk
echo "[*] Configuring Splunk Forwarder to start on bootup"
$INSTALL_LOCATION/splunkforwarder/bin/splunk enable boot-start -user $SPLUNKUSER --accept-license --answer-yes --no-prompt

# disable management port
echo "[*] Disabling management port for security."
mkdir -p $INSTALL_LOCATION/splunkforwarder/etc/apps/UF-TA-killrest/local
echo '[httpServer]
disableDefaultPort = true' > $INSTALL_LOCATION/splunkforwarder/etc/apps/UF-TA-killrest/local/server.conf

# Point to the Deployment server for remote administration
echo "[*] Configuring Splunk Forwarder for remote administration"
sudo -u $SPLUNKUSER $INSTALL_LOCATION/splunkforwarder/bin/splunk set deploy-poll $DEPLOY_SERVER --accept-license --answer-yes --auto-ports --no-prompt  -auth admin:changeme

# change admin pass
echo "[*] Changing administrative credentials"
$INSTALL_LOCATION/splunkforwarder/bin/splunk edit user admin -password $PASSWORD -auth admin:changeme

# ensure user splunk can read /var/log
echo "[*] Adding splunk account to read /var/log"
setfacl -Rm u:$SPLUNKUSER:r-x,d:u:$SPLUNKUSER:r-x /var/log

# do the same for the audit log
sed -i 's/log_group = root/log_group = $SPLUNKUSER/g' /etc/audit/auditd.conf
chgrp -R $SPLUNKUSER /var/log/audit
chmod 0750 /var/log/audit
chmod 0640 /var/log/audit/*

echo "[*] Restarting Splunk to finalize configuration"
sudo -u $SPLUNKUSER $INSTALL_LOCATION/splunkforwarder/bin/splunk restart

echo "[!] Please check for errors, as this install script has limited error checking!. Otherwise, work complete."
