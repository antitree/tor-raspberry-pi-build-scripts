## Build Checklist
- copy from latest image install onto raspberry pi 
- update version in /etc/rbb-version
- update /etc/motd to change the build time
- download imageprep script: https://raw.githubusercontent.com/antitree/tor-raspberry-pi-build-scripts/master/scripts/imageprep.sh
- make sure tor is up to date
https://github.com/antitree/tor-deb-raspberry-pi/raw/master/latest.deb
- make sure torpi-config.sh is up to date
- run imageprep.sh
- run firstboot.sh (if not already run)
- image sdcard following naming convention (See thing script)
- run shrink.sh if necessary (if you've expanded it)
- 7zip compress to standard naming convention
- upload to Mega
- upload as torrent (share torrent)
- update web page http://rbb.antitree.com

## Tests
[] can install on new raspberry pi
[] is history cleared on boot
[] able to get online using hardware
[] able to get online with wifi
[] runs through wizard to setup a bridge
[] running latest version of obfsproxy, tor