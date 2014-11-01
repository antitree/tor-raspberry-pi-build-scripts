# System image check to see if this is the first
# time ever starting the box. If it is, it
# performs security tasks related to:
#  - ssh keys
#  - tor hidden services
#  - tor configuration information

FB=/firstboot

VERSION=$(cat /etc/rbb-version)


reset_network() {
  echo auto lo > /etc/network/interfaces
  echo iface lo inet loopback >> /etc/network/interfaces
  echo >> /etc/network/interfaces
  echo auto eth0  >> /etc/network/interfaces
  echo iface eth0 inet dhcp >> /etc/network/interfaces
  if [ -e /etc/udev/rules.d/70-persistent-net.rules ]; then
	rm /etc/udev/rules.d/70-persistent-net.rules
  fi
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
	
	#OBFS=$(pip search obfsproxy | grep "latest")
	#if [ -z "$OBFS" ]; then
	#	echo Updating obfsproxy...
	#	pip install obfsproxy -U -q
	#fi
	
	#update torpi-config
	wget https://github.com/antitree/tor-raspberry-pi-build-scripts/raw/master/scripts/torpi-config.sh
	mv torpi-config.sh /usr/local/bin/torpi-config
	chmod +x /usr/local/bin/torpi-config
	
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
	if [ -e /root/.bash_history]; then
		rm /root/.bash_history
	fi
	rm -rf /var/backups/* /var/lib/apt/lists/* /root/* /root/.pip /root/.vim /root/.viminfo
	history -c 
}
	
clean_tor() {
	rm -rf /var/lib/tor/*
	cp /etc/tor/torrc.default /etc/tor/torrc
	if [ -e /etc/tor/torrc.backup]; then
		rm /etc/tor/torrc.backup
	fi
}

update_version() {
	if [ -e ./Tor_Ascii_Art.txt] ##TODO making this if,then rm stuff a seprate function
		rm ./Tor_Ascii_Art.txt
	fi
	wget https://raw.githubusercontent.com/antitree/tor-raspberry-pi-build-scripts/master/scripts/Tor_Ascii_Art.txt
	if ! [ -e Tor_Ascii_Art.txt ]; then
		exit 1
	fi
	cp Tor_Ascii_Art.txt /etc/motd
	rm ./Tor_Ascii_Art.txt
	echo >> /etc/motd
	echo Raspberry Bridge $VERSION >>  /etc/motd
	echo Built: `date +%m-%d-%Y` >> /etc/motd
	echo Author: AntiTree - http://rbb.antitree.com >> /etc/motd
	echo >> /etc/motd
	echo Welcome to Bridge Pi. To get started run torpi-config from the command line.
	echo >> /etc/motd
	
	wget https://github.com/antitree/tor-deb-raspberry-pi/raw/master/obfs4proxy
	# TODO check hash #
	mv obfs4proxy /usr/local/bin/obfs4proxy
	chmod +x /usr/local/bin/obfs4proxy

}

reset_password() {
	echo "root:raspbridge" | chpasswd
}


echo Starting pre-image cleanup
echo Updating version
update_version
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
echo resetting password
reset_password
echo resetting network configuration
reset_network



#Prep for first boot
touch /firstboot
cat /etc/motd
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
