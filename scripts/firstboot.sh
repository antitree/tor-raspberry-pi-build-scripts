#!/bin/sh
# First book check
# System image check to see if this is the first
# time ever starting the box. If it is, it
# performs security tasks related to:
#  - ssh keys
#  - tor hidden services
#  - tor configuration information

FB=/firstboot

#If /firstrun exists
if [ -e /firstboot ]
then
    #reset rsa and dsa keys
    rm /etc/dropbear/dropbear_*_host_key
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key > /dev/null 2>&1
    dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key > /dev/null 2>&1

    #execute torpi-config script
    torpi-config -w

    #remove file
    rm /firstboot
fi
