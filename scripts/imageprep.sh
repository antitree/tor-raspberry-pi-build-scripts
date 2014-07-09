# System image check to see if this is the first
# time ever starting the box. If it is, it
# performs security tasks related to:
#  - ssh keys
#  - tor hidden services
#  - tor configuration information

FB=/firstboot

reset_network() {
  echo auto lo > /etc/network/interfaces
  echo iface lo inet loopback >> /etc/network/interfaces
  echo >> /etc/network/interfaces
  echo auto eth0  >> /etc/network/interfaces
  echo iface eth0 inet dhcp >> /etc/network/interfaces
  rm /etc/udev/rules.d/70-persistent-net.rules
}


check_updates() {
	apt-get update
	apt-get upgrade -s
	read -p "OK to do updates?" yn
	case $yn in
		[Yy]* ) apt-get upgrade -y; break;;
		[Nn]* ) break;;
		* ) echo "answer yes or no.";;
	esac
	apt-get --purge autoremove
	
	OBFS=$(pip search obfsproxy | grep "latest")
	if [ -z "$OBFS" ]; then
		echo Updating obfsproxy...
		pip install obfsproxy -U -q
	fi
}

check_binaries() {
	# Check that custom binaries are in place
	chmod +x /usr/local/bin/*
	
}

reset_ssh() {
    rm /etc/dropbear/dropbear_*_host_key
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key > /dev/null 2>&1
    dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key > /dev/null 2>&1
}

clear_cache() {
	apt-get clean
	rm /root/.bash_history
	rm -rf /var/backups/* /var/lib/apt/lists/* /root/* /root/.pip /root/.vim /root/.viminfo
}
	
clean_tor() {
	rm -rf /var/lib/tor/*
	cp /etc/tor/torrc.default /etc/tor/torrc
	rm /etc/tor/torrc.backup
}


echo Starting pre-image cleanup
echo checking binaries
check_binaries
echo checking for updates
check_updates
echo clearning cache
clear_cache
echo resetting tor
clean_tor
echo resetting SSH
reset_ssh
echo resetting network configuration
reset_network



#Prep for first boot
touch /firstboot
echo ---------------------- 
echo Summary:
echo Reset ssh, checked for updates, cleared cach, rest tor, reset network
echo ----------------------
while true; do
	read -p "OK to shutdown for imaging?" yn
	case $yn in
		[Yy]* ) shutdown -h now; break;;
		[Nn]* ) break;;
		* ) echo "answer yes or no.";;
	esac
done
