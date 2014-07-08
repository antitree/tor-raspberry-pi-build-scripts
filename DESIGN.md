## Design Document ##
The following is the design document and list of commands to accomplish the design. 

## Overview ##
The purpose of this image is:

1)  Help facilitate users to run obfuscated bridges on their RBP's: 
Providing a pre-built environment for the latest version of Tor, pre-installing obfsproxy, providing an easy-to-use configuration tool that helps get you up and running without much prior knowledge. 

2) Optimize the distro for Tor running a RBP: 
This is accomplished by modifying a minimal Debian Wheezy image to include only necessary packages, use packages with minimal memory usage, avoid unnecessary wear on the SDCard, and ensure that Tor is running as expected. 


## Base Image ##
* Debian Wheezy Image
* raspbian-ua-netinst based "minimal" image [link](https://github.com/debian-pi/raspbian-ua-netinst)
* installed extra packages: (TODO update)
     VIM
* using inetutils-syslogd as opposed to rsyslog (lower memory)
* removed extra TTY windows from /etc/inittab (commented out except for the first 2)
* using dropbear instead of OpenSSH
     apt-get install dropbear
     apt-get remove openssh-server
     edit /etc/defaults and on the first line there is a "NO_START 1" - change to 0 to allow it to startup 
* using a watchdog service to monitor Tor and other system properties
     apt-get install watchdog
     edit /etc/watchdog.conf file to monitor the Tor pid
          pidfile = /var/run/tor/tor.pid
     (optional) modify it to ping a remote host to make sure it's online (can't do in the base image)
* remove packages(TODO update)


## Installing Tor:##
This is how to setup Tor, obfsproxy, and it's supporting packages to run a bridge. 
* install deb packages for Tor and GeoIP (see github project TODO Link)
* install libevent using apt-get install -f (fulfills dependences)
* apt-get install pip (will in stall a bunch of build essential tools as well)
* pip install obfsproxy (requires python2.7-dev)
* make modifications to the TORRC (NOTE: can use the torpi-config tool for this):
    SocksPort 0
	ORPort 443 # or some other port if you already run a webserver/skype
	BridgeRelay 1
	Exitpolicy reject *:*
	Nickname Whatever
	ContactInfo you@you.edu
	ServerTransportPlugin obfs3 exec /usr/local/bin/obfsproxy managed

## Host Hardening ##
* mount /var/log as a tmpfs to cut down on wear of the SDcard
    add to fstab:
     tmpfs /var/log tmpfs defaults,noexec,nosuid,size=10m   0   0
* change tor to use syslog instead of /var/log/tor (because of what you just did above, it won't start)
     - edit torrc
     - set logging to syslog
          Log notice syslog
* change Torrc to avoid writes
     AvoidDiskWrites 1

##  Scripts ##
* TODO link to imaging scripts
* TODO link to first boot script
* * regenerate drop bear ssh keys
* TODO link to torpi-config tool

References:
https://www.torproject.org/projects/obfsproxy-instructions.html.en
