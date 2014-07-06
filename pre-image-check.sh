#!/bin/sh

## Clear history
echo Making sure bash history is removed
rm ~/.bash_history

## Update version info
while true; do
    read -p "Do you need to update the version info?" yn
    case $yn in
        [Yy]* ) sudo vi /etc/version; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

## Remove SSH keys
while true; do
    read -p "Are you sure you want to remov ethe RSA DSS SSH keys?" yn
    case $yn in
        [Yy]* ) rm /etc/dropbear/dropbear_*host_key; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

## Installing available updates
echo Checking for available updates
sudo apt-get upgrade -q

## Clear Hidden Service
echo Removing hidden service files
while true; do
    read -p "Are you sure?" yn
    case $yn in
	[Yy]* ) sudo rm -rf /var/lib/tor/hidden_service; break;; 
   	[Nn]* ) break;;
	* ) echo "Please answer yes or no.";;
    esac
done

## Reset Torrc
echo Resetting Torrc
while true; do
	read -p "Are you sure?" yn
	case $yn in
	[Yy]* ) sudo mv /etc/tor/torrc.default /etc/tor/torrc; break;;
   	[Nn]* ) break;;
	* ) echo "Please answer yes or no.";;
    esac
done

## Remove unnecessary logs
echo Removing unnecessary files and cache
sudo find / -type f -name "*-old" |xargs sudo rm -rf
sudo rm -rf /var/backups/* /var/lib/apt/lists/* ~/.bash_history

## Clear home directory
echo Will not clear pi directory

## Clearing wireless network
while true; do
    read -p "Removing wicd settings. Are you sure?" yn
    case $yn in
	[Yy]* ) sudo rm /etc/wicd/wireless-settings.conf; break;;
	[Nn]* ) echo Wireless settings retained;break;;
	* ) echo "Choose something pussy";;
    esac
done

## Checking unnecessary users
tail /etc/passwd
echo Review the list above
while true; do
    read -p "Do you notice any unnecessary users?" yn
    case $yn in
	[Yy]* ) echo Please removed these users manually before imaging; exit;;
       	[Nn]* ) break;;
	* ) echo "Choose something pussy";;
    esac
done

## Tell the system to go into image mode
## if firstboot exists, it will go into primary boot mode
# exec dropbear -d ./dropbear_dss_host_key -r ./dropbear_rsa_host_key -F -E -p 22
# dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
echo Setting imaging to run firstboot script in /firstboot
touch /firstboot

## Done
echo Image prepping complete. 
