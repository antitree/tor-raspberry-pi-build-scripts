#!/bin/sh
# Configuration tool for setting up a bridge on the Raspberry Pi
# Modified from
# raspi-config http://github.com/asb/raspi-config
#
# # #

INTERACTIVE=True
ASK_TO_REBOOT=1
TOR=/usr/sbin/tor

calc_wt_size() {
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_WIDTH=$(tput cols)
  WT_HEIGHT=17

  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-8))
}

do_about() {
  whiptail --msgbox "\
This tool provides a way of configuring Tor on a Raspberry
Pi. It was based off of the Rasp-conf tool included in 
Raspbian. @antitree \
" 20 70 1
}

do_expand_rootfs() {
  if ! [ -h /dev/root ]; then
    whiptail --msgbox "/dev/root does not exist or is not a symlink. Don't know how to expand" 20 60 2
    return 0
  fi

  ROOT_PART=$(readlink /dev/root)
  PART_NUM=${ROOT_PART#mmcblk0p}
  if [ "$PART_NUM" = "$ROOT_PART" ]; then
    whiptail --msgbox "/dev/root is not an SD card. Don't know how to expand" 20 60 2
    return 0
  fi

  # NOTE: the NOOBS partition layout confuses parted. For now, let's only 
  # agree to work with a sufficiently simple partition layout
  if [ "$PART_NUM" -ne 2 ]; then
    whiptail --msgbox "Your partition layout is not currently supported by this tool. You are probably using NOOBS, in which case your root filesystem is already expanded anyway." 20 60 2
    return 0
  fi

  LAST_PART_NUM=$(parted /dev/mmcblk0 -ms unit s p | tail -n 1 | cut -f 1 -d:)

  if [ "$LAST_PART_NUM" != "$PART_NUM" ]; then
    whiptail --msgbox "/dev/root is not the last partition. Don't know how to expand" 20 60 2
    return 0
  fi

  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d:)
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF
  ASK_TO_REBOOT=1

  # now set up an init.d script
cat <<\EOF > /etc/init.d/resize2fs_once &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5 S
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once" &&
    resize2fs /dev/root &&
    rm /etc/init.d/resize2fs_once &&
    update-rc.d resize2fs_once remove &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x /etc/init.d/resize2fs_once &&
  update-rc.d resize2fs_once defaults &&
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "Root partition has been resized.\nThe filesystem will be enlarged upon the next reboot" 20 60 2
  fi
}

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end

if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
}

get_config_var() {
  lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
  local val = line:match("^#?%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    break
  end
end
EOF
}

do_change_pass() {
  whiptail --msgbox "You will now be asked to enter a new password for the pi user" 20 60 1
  passwd root &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

do_configure_keyboard() {
  ##TODO requires keyboard-configuration package
  dpkg-reconfigure keyboard-configuration &&
  printf "Reloading keymap. This may take a short while\n" &&
  invoke-rc.d keyboard-setup start
}

do_change_locale() {
  #TODO requires locales package
  dpkg-reconfigure locales
}

do_change_timezone() {
  dpkg-reconfigure tzdata
}

do_change_hostname() {
  whiptail --msgbox "\
Please note: RFCs mandate that a hostname's labels \
may contain only the ASCII letters 'a' through 'z' (case-insensitive), 
the digits '0' through '9', and the hyphen.
Hostname labels cannot begin or end with a hyphen. 
No other symbols, punctuation characters, or blank spaces are permitted.\
" 20 70 1

  CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
  NEW_HOSTNAME=$(whiptail --inputbox "Please enter a hostname" 20 60 "$CURRENT_HOSTNAME" 3>&1 1>&2 2>&3)
  if [ $? -eq 0 ]; then
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
    ASK_TO_REBOOT=1
  fi
}


do_overclock() {
  whiptail --msgbox "\
Be aware that overclocking may reduce the lifetime of your
Raspberry Pi. If overclocking at a certain level causes
system instability, try a more modest overclock. Hold down
shift during boot to temporarily disable overclock.
See http://elinux.org/RPi_Overclocking for more information.\
" 20 70 1
  OVERCLOCK=$(whiptail --menu "Chose overclock preset" 20 60 10 \
    "None" "700MHz ARM, 250MHz core, 400MHz SDRAM, 0 overvolt" \
    "Modest" "800MHz ARM, 250MHz core, 400MHz SDRAM, 0 overvolt" \
    "Medium" "900MHz ARM, 250MHz core, 450MHz SDRAM, 2 overvolt" \
    "High" "950MHz ARM, 250MHz core, 450MHz SDRAM, 6 overvolt" \
    "Turbo" "1000MHz ARM, 500MHz core, 600MHz SDRAM, 6 overvolt" \
    3>&1 1>&2 2>&3)
  if [ $? -eq 0 ]; then
    case "$OVERCLOCK" in
      None)
        set_overclock None 700 250 400 0
        ;;
      Modest)
        set_overclock Modest 800 250 400 0
        ;;
      Medium)
        set_overclock Medium 900 250 450 2
        ;;
      High)
        set_overclock High 950 250 450 6
        ;;
      Turbo)
        set_overclock Turbo 1000 500 600 6
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised overclock preset" 20 60 2
        return 1
        ;;
    esac
    ASK_TO_REBOOT=1
  fi
}

set_overclock() {
  set_config_var arm_freq $2 /boot/config.txt &&
  set_config_var core_freq $3 /boot/config.txt &&
  set_config_var sdram_freq $4 /boot/config.txt &&
  set_config_var over_voltage $5 /boot/config.txt &&
  # now set up an init.d script
cat <<\EOF > /etc/init.d/switch_cpu_governor &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          switch_cpu_governor
# Required-Start: udev mountkernfs $remote_fs
# Required-Stop:
# Default-Start: S
# Default-Stop:
# Short-Description: Switch to ondemand cpu governor (unless shift key is pressed)
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Checking if shift key is held down"
    timeout 1 thd --dump /dev/input/event* | grep -q "LEFTSHIFT\|RIGHTSHIFT"
    if [ $? -eq 0 ]; then
      printf " Yes. Not switching scaling governor"
      log_end_msg 0
    else
      SYS_CPUFREQ_GOVERNOR=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
      [ -e $SYS_CPUFREQ_GOVERNOR ] && echo "ondemand" > $SYS_CPUFREQ_GOVERNOR
      echo 70 > /sys/devices/system/cpu/cpufreq/ondemand/up_threshold
      printf " No. Switching to ondemand scaling governor"
      log_end_msg 0
    fi
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x /etc/init.d/switch_cpu_governor &&
  update-rc.d switch_cpu_governor defaults &&
  whiptail --msgbox "Set overclock to preset '$1'" 20 60 2
}

do_ssh() {
  whiptail --yesno "Would you like the SSH server enabled or disabled?" 20 60 2 \
    --yes-button Enable --no-button Disable
  RET=$?
  if [ $RET -eq 0 ]; then
    update-rc.d ssh enable &&
	sed -i "s/^NO_START=1/NO_START=0/" /etc/default/dropbear
	service dropbear start
    whiptail --msgbox "SSH server enabled" 20 60 1
  elif [ $RET -eq 1 ]; then
	sed -i "s/^NO_START=0/NO_START=1/" /etc/default/dropbear
	service dropbear stop
    whiptail --msgbox "SSH server disabled" 20 60 1
  else
    return $RET
  fi
}



do_finish() {
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    if [ -e /firstboot ];then
		rm /firstboot
	fi
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

do_todo() {
  whiptail --msgbox "This feature is not yet implemented" 20 60 1
}

do_configure_tor() {
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Tor Configuration Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
  "T1 Setup Bridge" "Configure the system as an obfuscated bridge node (Recommended)" \
  3>&1 1>&2 2>&3)
    RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      T1\ *) do_configure_bridge ;;
      T2\ *) ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
  
}


do_network() {
  whiptail --msgbox "\
In most cases to setup a bridge you will need to set a static IP
behind your router and then forward a port from the firewall to
this bridge.  \
" 20 70 1
  whiptail --yesno "Would you like to set a static IP?" 20 60 2 \
    --yes-button Enable --no-button Disable
  RET=$?
  if [ $RET -eq 0 ]; then
	do_static
  elif [ $RET -eq 1 ]; then
    do_dhcp
  fi
  
  whiptail --yesno "Networking needs to reset to apply your changes. \
   This may cut out existing connections including SSH. Is that ok?" 20 60 2 \
    --yes-button Yes --no-button No
  RET=$?
  if [ $RET -eq 0 ]; then
	service networking restart
	whiptail --msgbox "Networking restarted successfully" 20 70 1
  else
    whiptail --msgbox "You must restart to apply networking settings" 20 70 1
  fi
  return 0
}

clean_interfaces() {
  echo auto lo > /etc/network/interfaces
  echo iface lo inet loopback >> /etc/network/interfaces
  echo >> /etc/network/interfaces
  echo auto eth0  >> /etc/network/interfaces
}

do_static(){
  ## Set static networking
  clean_interfaces
  echo iface eth0 inet static >> /etc/network/interfaces
  IP=$(whiptail --inputbox "IP address" 20 70 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  SUBNET=$(whiptail --inputbox "Subnet" 20 70 "255.255.255.0" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  GW=$(whiptail --inputbox "Gateway" 20 70 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi  
  echo "  address $IP" >> /etc/network/interfaces
  echo "  netmask $SUBNET" >> /etc/network/interfaces
  echo "  gateway $GW" >> /etc/network/interfaces
}  

do_dhcp() {
  ## Setup DHCP
  clean_interfaces
  echo iface eth0 inet dhcp >> /etc/network/interfaces
}

do_configure_bridge() {
  ## Setup bridge options
   whiptail --msgbox "\
Setting up a bridge node is the best way to help countries where
Tor is being blocked. A bridge (and ideally an obfuscated bridge)
is an unlisted entry node that is more difficult to censor. This
tool will walk you through the steps of configuring a bridge that
uses obfsproxy \
" 20 70 1
  if [ $? -ne 0 ]; then
    return 0;
  fi
  DNICK=$(tr -cd 0-9 </dev/urandom | head -c 6)
  NICKNAME=$(whiptail --inputbox "Bridge Nickname" 20 70 torpi$DNICK 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  EMAIL=$(whiptail --inputbox "Email Address to conact you if there is a problem with your node" 20 70 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  PORT=$(whiptail --inputbox "Listening port of the bridge. Ideally this should be 443 but use other ports if this is already in use by your network" 20 70 443 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  
  #Backup old torrc
  cp /etc/tor/torrc /etc/tor/torrc.backup
  cp /etc/tor/torrc.default /etc/tor/torrc
  
  TORRC=/etc/tor/torrc
  
  #Modify the Torrc
  sed -i "s/^#Nickname CHANGEME/Nickname $NICKNAME/" "$TORRC"
  sed -i "s/^#ContactInfo None/ContactInfo $EMAIL/" "$TORRC"
  sed -i "s/^#SocksPort 0/SocksPort 0/" "$TORRC"
  sed -i "s/^#ORPort 443/ORPort $PORT/" "$TORRC"
  sed -i "s/^#BridgeRelay/BridgeRelay/" "$TORRC"
  sed -i "s/^#ExitPolicy reject/ExitPolicy reject/" "$TORRC"
  sed -i "s/^#ServerTransportPlugin/ServerTransportPlugin/" "$TORRC"
  if ! check_tor_config ; then
	whiptail --msgbox "Configuration error: Torrc is not configured correctly" 20 60 1 
	cp /etc/tor/torrc.backup /etc/tor/torrc
	return 1
  else
	whiptail --msgbox "Tor configuration was successful. The service will now restart" 20 60 1
	#service watchdog stop
	service tor restart
	#service watchdog start
	return 0
  fi

}

check_tor_config() {
	if ! $TOR --verify-config > /dev/null; then
		return 1;
	else
		return 0;
	fi
}

do_update_obf() {
	# Check if obfsproxy is up to date
	echo Checking for updates for obfs4proxy...
	wget https://github.com/antitree/tor-deb-raspberry-pi/raw/master/obfs4proxy
	# TODO check hash #
	# wget sha1
	# sha1sum sha1
	# if sha1sum != sha1sum /obfs4proxy
	mv obfs4proxy /usr/local/bin/obfs4proxy
	chmod +x /usr/local/bin/obfs4proxy
		
	RET=$?
	if [ $RET -eq 0 ]; then
		whiptail --msgbox "Obfs4proxy is up to date" 20 70 1
		return 0
	else:
		whiptail --msgbox "There was a problem updating Obfs4proxy" 20 70 1
		return 1
	fi
}


start_wizard() {
  whiptail --yesno --title "Tor Pi Configuration Wizard" \
  "This is the Tor Pi configuration wizard that will guide you through \
setting up your Raspberry Pi as a Tor Bridge Relay. Would you like \
to continue?" 20 60 2 \
    --yes-button Yes --no-button No 
  RET=$?
  if [ $RET -eq 1 ]; then
    return $RET
  fi
  
  
  #whiptail --yesno --title "Password Change" \
  #"It's recommended that you change the default root password. Would \
#you like to do so now? \
  #" 20 60 2 --yes-button Yes --no-button No 
  #RET=$?
  #if [ $RET -eq 1 ]; then
    #return $RET
  #else
	do_change_pass
  #fi
  
  ## Configure networking
  do_network
 
  whiptail --yesno --title "Update software" \
  "It's important to update to the latest version of \
the obfsproxy to provide an obfuscated bridge.  \
Would you like to do so now? \
  " 20 60 2 --yes-button Yes --no-button No 
  RET=$?
  if [ $RET -eq 1 ]; then
    return $RET
  else
	do_update_obf
  fi
  
  #whiptail --yesno --title "Configure Tor" \
  #"This will help you configure Tor as an obfuscated bridge relay. \
#Are you ready to continue? \
  #" 20 60 2 \
  #  --yes-button Yes --no-button No 
  #RET=$?
  #if [ $RET -eq 1 ]; then
  #  return $RET
  #else
	do_configure_bridge
  #fi  
  
  
  whiptail --msgbox --title "Configuration successful" \
  "Congratulations. You have successfully configured your Raspberry Pi \
as a Tor Bridge relay. If you would like to make any changes you can \
always re-run torpi-config at any time. The system will not restart to \
apply its changes.
   
NOTE: YOU ARE NOT DONE. Make sure that you forward the bridge port \
through your firewall to the IP address you just configured. 
  
  #" 20 60 2 \
  
} 


for i in $*
do
  case $i in
  -w)
    start_wizard 
	RET=$?
	if [ $RET -eq 1 ]; then
	    whiptail --msgbox "The wizard is incomplete. You will need to manually make changes to the system going forward" 20 60 1 
	fi
	;;
  *)
    # unknown option
    ;;
  esac
done


 
  
#
#
#
calc_wt_size
while true; do
  FUN=$(whiptail --title "Tor Pi Software Configuration Tool (torpi-config)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
    "1 Expand Filesystem" "Ensures that all of the SD card storage is available to the OS" \
    "2 Change User Password" "Change password for the default user (pi)" \
	"3 Configure Networking" "Setup a static IP for the relay" \
    "4 Configure Tor relay " "Configure Tor as an obfsucated bridge node" \
	"5 Update Obfsproxy " "Update the Obfsproxy for providing an obfuscated bridge" \
    "6 Manage SSH" "Enable or disable SSH access" \
	"7 Change Hostname" "Set the visible name for this Pi on a network" \
    "0 About torpi-config" "Information about this configuration tool" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    do_finish
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      1\ *) do_expand_rootfs ;;
      2\ *) do_change_pass ;;
	  3\ *) do_network ;;
      4\ *) do_configure_bridge ;;
	  5\ *) do_update_obf ;;
      6\ *) do_ssh ;;
	  7\ *) do_change_hostname ;;
      0\ *) do_about ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  else
    exit 1
  fi
done
