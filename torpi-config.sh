#!/bin/sh
# Part of raspi-config http://github.com/asb/raspi-config
#
# See LICENSE file for copyright and license details

INTERACTIVE=True
ASK_TO_REBOOT=0

calc_wt_size() {
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_HEIGHT=17
  WT_WIDTH=$(tput cols)

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
This tool provides a straight-forward way of doing initial
configuration of the Raspberry Pi. Although it can be run
at any time, some of the options may have difficulties if
you have heavily customised your installation.\
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

# $1 is 0 to disable overscan, 1 to disable it
set_overscan() {
  # Stop if /boot is not a mountpoint
  if ! mountpoint -q /boot; then
    return 1
  fi

  [ -e /boot/config.txt ] || touch /boot/config.txt

  if [ "$1" -eq 0 ]; then # disable overscan
    sed /boot/config.txt -i -e "s/^overscan_/#overscan_/"
    set_config_var disable_overscan 1 /boot/config.txt
  else # enable overscan
    set_config_var disable_overscan 0 /boot/config.txt
  fi
}

do_overscan() {
  whiptail --yesno "What would you like to do with overscan" 20 60 2 \
    --yes-button Disable --no-button Enable
  RET=$?
  if [ $RET -eq 0 ] || [ $RET -eq 1 ]; then
    ASK_TO_REBOOT=1
    set_overscan $RET;
  else
    return 1
  fi
}

do_change_pass() {
  whiptail --msgbox "You will now be asked to enter a new password for the pi user" 20 60 1
  passwd pi &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

do_configure_keyboard() {
  dpkg-reconfigure keyboard-configuration &&
  printf "Reloading keymap. This may take a short while\n" &&
  invoke-rc.d keyboard-setup start
}

do_change_locale() {
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

do_memory_split() { # Memory Split
  if [ -e /boot/start_cd.elf ]; then
    # New-style memory split setting
    if ! mountpoint -q /boot; then
      return 1
    fi
    ## get current memory split from /boot/config.txt
    CUR_GPU_MEM=$(get_config_var gpu_mem /boot/config.txt)
    [ -z "$CUR_GPU_MEM" ] && CUR_GPU_MEM=64
    ## ask users what gpu_mem they want
    NEW_GPU_MEM=$(whiptail --inputbox "How much memory should the GPU have?  e.g. 16/32/64/128/256" \
      20 70 -- "$CUR_GPU_MEM" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ]; then
      set_config_var gpu_mem "$NEW_GPU_MEM" /boot/config.txt
      ASK_TO_REBOOT=1
    fi
  else # Old firmware so do start.elf renaming
    get_current_memory_split
    MEMSPLIT=$(whiptail --menu "Set memory split.\n$MEMSPLIT_DESCRIPTION" 20 60 10 \
      "240" "240MiB for ARM, 16MiB for VideoCore" \
      "224" "224MiB for ARM, 32MiB for VideoCore" \
      "192" "192MiB for ARM, 64MiB for VideoCore" \
      "128" "128MiB for ARM, 128MiB for VideoCore" \
      3>&1 1>&2 2>&3)
    if [ $? -eq 0 ]; then
      set_memory_split ${MEMSPLIT}
      ASK_TO_REBOOT=1
    fi
  fi
}

get_current_memory_split() {
  # Stop if /boot is not a mountpoint
  if ! mountpoint -q /boot; then
    return 1
  fi
  AVAILABLE_SPLITS="128 192 224 240"
  MEMSPLIT_DESCRIPTION=""
  for SPLIT in $AVAILABLE_SPLITS;do
    if [ -e /boot/arm${SPLIT}_start.elf ] && cmp /boot/arm${SPLIT}_start.elf /boot/start.elf >/dev/null 2>&1;then
      CURRENT_MEMSPLIT=$SPLIT
      MEMSPLIT_DESCRIPTION="Current: ${CURRENT_MEMSPLIT}MiB for ARM, $((256 - $CURRENT_MEMSPLIT))MiB for VideoCore"
      break
    fi
  done
}

set_memory_split() {
  cp -a /boot/arm${1}_start.elf /boot/start.elf
  sync
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
  if [ -e /var/log/regen_ssh_keys.log ] && ! grep -q "^finished" /var/log/regen_ssh_keys.log; then
    whiptail --msgbox "Initial ssh key generation still running. Please wait and try again." 20 60 2
    return 1
  fi
  whiptail --yesno "Would you like the SSH server enabled or disabled?" 20 60 2 \
    --yes-button Enable --no-button Disable
  RET=$?
  if [ $RET -eq 0 ]; then
    update-rc.d ssh enable &&
    invoke-rc.d ssh start &&
    whiptail --msgbox "SSH server enabled" 20 60 1
  elif [ $RET -eq 1 ]; then
    update-rc.d ssh disable &&
    whiptail --msgbox "SSH server disabled" 20 60 1
  else
    return $RET
  fi
}

do_spi() {
  CURRENT_STATUS="yes" # assume not blacklisted
  if [ -e /etc/modprobe.d/raspi-blacklist.conf ] && grep -q "^blacklist[[:space:]]*spi-bcm2708" /etc/modprobe.d/raspi-blacklist.conf; then
    CURRENT_STATUS="no"
  fi

  whiptail --yesno "Would you like the SPI kernel module to be loaded by default? Current setting: $CURRENT_STATUS" 20 60 2
  RET=$?
  if [ $RET -eq 0 ]; then
    sed -i /etc/modprobe.d/raspi-blacklist.conf -e "s/^blacklist[[:space:]]*spi-bcm2708.*/#blacklist spi-bcm2708/"
    sudo modprobe spi-bcm2708
    whiptail --msgbox "SPI kernel module will now be loaded by default" 20 60 1
  elif [ $RET -eq 1 ]; then
    sed -i /etc/modprobe.d/raspi-blacklist.conf -e "s/^#blacklist[[:space:]]*spi-bcm2708.*/blacklist spi-bcm2708/"
    if ! grep -q "^blacklist spi-bcm2708" /etc/modprobe.d/raspi-blacklist.conf; then
      printf "blacklist spi-bcm2708\n" >> /etc/modprobe.d/raspi-blacklist.conf
    fi
    whiptail --msgbox "SPI kernel module will no longer be loaded by default" 20 60 1
  else
    return $RET
  fi
}

disable_raspi_config_at_boot() {
  if [ -e /etc/profile.d/raspi-config.sh ]; then
    rm -f /etc/profile.d/raspi-config.sh
    sed -i /etc/inittab \
      -e "s/^#\(.*\)#\s*RPICFG_TO_ENABLE\s*/\1/" \
      -e "/#\s*RPICFG_TO_DISABLE/d"
    telinit q
  fi
}

enable_boot_to_scratch() {
  if [ -e /etc/profile.d/boottoscratch.sh ]; then
    printf "/etc/profile.d/boottoscratch.sh exists, so assuming boot to scratch enabled\n"
    return 0;
  fi
  sed -i /etc/inittab -e "s|^\(1:2345.*getty.*tty1.*\)|\
#\1 # BTS_TO_ENABLE\n1:2345:respawn:/bin/login -f pi tty1 </dev/tty1 >/dev/tty1 2>\&1 # BTS_TO_DISABLE|"
  cat <<\EOF > /etc/profile.d/boottoscratch.sh
#!/bin/sh
# Part of raspi-config http://github.com/asb/raspi-config
#
# See LICENSE file for copyright and license details

# Should be installed to /etc/profile.d/boottoscratch.sh to force scratch to run upon boot

# You may also want to set automatic login in /etc/inittab on tty1 by adding a 
# line such as the following (raspi-config does this for you):
# 1:2345:respawn:/bin/login -f pi tty1 </dev/tty1 >/dev/tty1 2>&1 # BTS_TO_DISABLE

if [ $(tty) = "/dev/tty1" ]; then
  printf "openbox --config-file /home/pi/boottoscratch/openbox_rc.xml & scratch" | xinit /dev/stdin
  printf "\n\n\nShutting down in 5 seconds, hit ctrl-C to cancel\n" && sleep 5 && sudo shutdown -h now
fi
EOF

  mkdir -p /home/pi/boottoscratch
  cat <<\EOF > /home/pi/boottoscratch/openbox_rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
    xmlns:xi="http://www.w3.org/2001/XInclude">
<applications>
  <application name="squeak" type="normal">
    <focus>yes</focus>
    <fullscreen>yes</fullscreen>
  </application>
</applications>
</openbox_config>
EOF
  telinit q
}

disable_boot_to_scratch() {
  if [ -e /etc/profile.d/boottoscratch.sh ]; then
    rm -f /etc/profile.d/boottoscratch.sh
    sed -i /etc/inittab \
      -e "s/^#\(.*\)#\s*BTS_TO_ENABLE\s*/\1/" \
      -e "/#\s*BTS_TO_DISABLE/d"
    telinit q
  fi
}

do_boot_behaviour() {
  BOOTOPT=$(whiptail --menu "Chose boot option" 20 60 10 \
    "Console" "Text console, requiring login (default)" \
    "Desktop" "Log in as user 'pi' at the graphical desktop" \
    "Scratch" "Start the Scratch programming environment upon boot" \
    3>&1 1>&2 2>&3)
  if [ $? -eq 0 ]; then
    case "$BOOTOPT" in
      Console)
        [ -e /etc/init.d/lightdm ] && update-rc.d lightdm disable 2
        disable_boot_to_scratch
        ;;
      Desktop)
        if [ -e /etc/init.d/lightdm ]; then
          if id -u pi > /dev/null 2>&1; then
            update-rc.d lightdm enable 2
            sed /etc/lightdm/lightdm.conf -i -e "s/^#autologin-user=.*/autologin-user=pi/"
            disable_boot_to_scratch
            disable_raspi_config_at_boot
          else
            whiptail --msgbox "The pi user has been removed, can't set up boot to desktop" 20 60 2
          fi
        else
          whiptail --msgbox "Do sudo apt-get install lightdm to allow configuration of boot to desktop" 20 60 2
          return 1
        fi
        ;;
      Scratch)
        if [ -e /usr/bin/scratch ]; then
          if id -u pi > /dev/null 2>&1; then
            [ -e /etc/init.d/lightdm ] && update-rc.d lightdm disable 2
            disable_raspi_config_at_boot
            enable_boot_to_scratch
          else
            whiptail --msgbox "The pi user has been removed, can't set up boot to scratch" 20 60 2
          fi
        else
          whiptail --msgbox "Do sudo apt-get install scratch to allow configuration of boot to scratch" 20 60 2
        fi
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised boot option" 20 60 2
        return 1
        ;;
    esac
    ASK_TO_REBOOT=1
  fi
}

do_rastrack() {
  whiptail --msgbox "\
Rastrack (http://rastrack.co.uk) is a website run by Ryan Walmsley
for tracking where people are using Raspberry Pis around the world.
If you have an internet connection, you can add yourself directly
using this tool. This is just a bit of fun, not any sort of official
registration.\
" 20 70 1
  if [ $? -ne 0 ]; then
    return 0;
  fi
  UNAME=$(whiptail --inputbox "Username / Nickname For Rastrack Addition" 20 70 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  EMAIL=$(whiptail --inputbox "Email Address For Rastrack Addition" 20 70 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 1;
  fi
  curl --data "name=$UNAME&email=$EMAIL" http://rastrack.co.uk/api.php
  printf "Hit enter to continue\n"
  read TMP
}

# $1 is 0 to disable camera, 1 to enable it
set_camera() {
  # Stop if /boot is not a mountpoint
  if ! mountpoint -q /boot; then
    return 1
  fi

  [ -e /boot/config.txt ] || touch /boot/config.txt

  if [ "$1" -eq 0 ]; then # disable camera
    set_config_var start_x 0 /boot/config.txt
    sed /boot/config.txt -i -e "s/^startx/#startx/"
    sed /boot/config.txt -i -e "s/^start_file/#start_file/"
    sed /boot/config.txt -i -e "s/^fixup_file/#fixup_file/"
  else # enable camera
    set_config_var start_x 1 /boot/config.txt
    CUR_GPU_MEM=$(get_config_var gpu_mem /boot/config.txt)
    if [ -z "$CUR_GPU_MEM" ] || [ "$CUR_GPU_MEM" -lt 128 ]; then
      set_config_var gpu_mem 128 /boot/config.txt
    fi
    sed /boot/config.txt -i -e "s/^startx/#startx/"
    sed /boot/config.txt -i -e "s/^fixup_file/#fixup_file/"
  fi
}

do_camera() {
  if [ ! -e /boot/start_x.elf ]; then
    whiptail --msgbox "Your firmware appears to be out of date (no start_x.elf). Please update" 20 60 2
    return 1
  fi
  whiptail --yesno "Enable support for Raspberry Pi camera?" 20 60 2 \
    --yes-button Disable --no-button Enable
  RET=$?
  if [ $RET -eq 0 ] || [ $RET -eq 1 ]; then
    ASK_TO_REBOOT=1
    set_camera $RET;
  else
    return 1
  fi
}

do_update() {
  apt-get update &&
  apt-get install raspi-config &&
  printf "Sleeping 5 seconds before reloading raspi-config\n" &&
  sleep 5 &&
  exec raspi-config
}

do_audio() {
  AUDIO_OUT=$(whiptail --menu "Choose the audio output" 20 60 10 \
    "0" "Auto" \
    "1" "Force 3.5mm ('headphone') jack" \
    "2" "Force HDMI" \
    3>&1 1>&2 2>&3)
  if [ $? -eq 0 ]; then
    amixer cset numid=3 "$AUDIO_OUT"
  fi
}

do_finish() {
  disable_raspi_config_at_boot
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

# $1 = filename, $2 = key name
get_json_string_val() {
  sed -n -e "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\(.*\)\"[[:space:]]*,$/\1/p" $1
}

do_apply_os_config() {
  [ -e /boot/os_config.json ] || return 0
  NOOBSFLAVOUR=$(get_json_string_val /boot/os_config.json flavour)
  NOOBSLANGUAGE=$(get_json_string_val /boot/os_config.json language)
  NOOBSKEYBOARD=$(get_json_string_val /boot/os_config.json keyboard)

  if [ -n "$NOOBSFLAVOUR" ]; then
    printf "Setting flavour to %s based on os_config.json from NOOBS. May take a while\n" "$NOOBSFLAVOUR"

    if printf "%s" "$NOOBSFLAVOUR" | grep -q "Scratch"; then
      disable_raspi_config_at_boot
      enable_boot_to_scratch
    else
      printf "Unrecognised flavour. Ignoring\n"
    fi
  fi

  # TODO: currently ignores en_gb settings as we assume we are running in a 
  # first boot context, where UK English settings are default
  case "$NOOBSLANGUAGE" in
    "en")
      if [ "$NOOBSKEYBOARD" = "gb" ]; then
        DEBLANGUAGE="" # UK english is the default, so ignore
      else
        DEBLANGUAGE="en_US.UTF-8"
      fi
      ;;
    "de")
      DEBLANGUAGE="de_DE.UTF-8"
      ;;
    "fi")
      DEBLANGUAGE="fi_FI.UTF-8"
      ;;
    "fr")
      DEBLANGUAGE="fr_FR.UTF-8"
      ;;
    "hu")
      DEBLANGUAGE="hu_HU.UTF-8"
      ;;
    "ja")
      DEBLANGUAGE="ja_JP.UTF-8"
      ;;
    "nl")
      DEBLANGUAGE="nl_NL.UTF-8"
      ;;
    "pt")
      DEBLANGUAGE="pt_PT.UTF-8"
      ;;
    "ru")
      DEBLANGUAGE="ru_RU.UTF-8"
      ;;
    "zh_CN")
      DEBLANGUAGE="zh_CN.UTF-8"
      ;;
    *)
      printf "Language '%s' not handled currently. Run sudo raspi-config to set up" "$NOOBSLANGUAGE"
      ;;
  esac

  if [ -n "$DEBLANGUAGE" ]; then
    printf "Setting language to %s based on os_config.json from NOOBS. May take a while\n" "$DEBLANGUAGE"
    cat << EOF | debconf-set-selections
locales   locales/locales_to_be_generated multiselect     $DEBLANGUAGE UTF-8
EOF
    rm /etc/locale.gen
    dpkg-reconfigure -f noninteractive locales
    update-locale LANG="$DEBLANGUAGE"
    cat << EOF | debconf-set-selections
locales   locales/default_environment_locale select       $DEBLANGUAGE
EOF
  fi

  if [ -n "$NOOBSKEYBOARD" -a "$NOOBSKEYBOARD" != "gb" ]; then
    printf "Setting keyboard layout to %s based on os_config.json from NOOBS. May take a while\n" "$NOOBSKEYBOARD"
    sed -i /etc/default/keyboard -e "s/^XKBLAYOUT.*/XKBLAYOUT=\"$NOOBSKEYBOARD\"/"
    dpkg-reconfigure -f noninteractive keyboard-configuration
    invoke-rc.d keyboard-setup start
  fi
  return 0
}

#
# Command line options for non-interactive use
#
for i in $*
do
  case $i in
  --memory-split)
    OPT_MEMORY_SPLIT=GET
    printf "Not currently supported\n"
    exit 1
    ;;
  --memory-split=*)
    OPT_MEMORY_SPLIT=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
    printf "Not currently supported\n"
    exit 1
    ;;
  --expand-rootfs)
    INTERACTIVE=False
    do_expand_rootfs
    printf "Please reboot\n"
    exit 0
    ;;
  --apply-os-config)
    INTERACTIVE=False
    do_apply_os_config
    exit $?
    ;;
  *)
    # unknown option
    ;;
  esac
done

#if [ "GET" = "${OPT_MEMORY_SPLIT:-}" ]; then
#  set -u # Fail on unset variables
#  get_current_memory_split
#  echo $CURRENT_MEMSPLIT
#  exit 0
#fi

# Everything else needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo raspi-config'\n"
  exit 1
fi

if [ -n "${OPT_MEMORY_SPLIT:-}" ]; then
  set -e # Fail when a command errors
  set_memory_split "${OPT_MEMORY_SPLIT}"
  exit 0
fi

do_internationalisation_menu() {
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Internationalisation Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "I1 Change Locale" "Set up language and regional settings to match your location" \
    "I2 Change Timezone" "Set up timezone to match your location" \
    "I3 Change Keyboard Layout" "Set the keyboard layout to match your keyboard" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      I1\ *) do_change_locale ;;
      I2\ *) do_change_timezone ;;
      I3\ *) do_configure_keyboard ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
}

do_advanced_menu() {
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Advanced Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "A1 Overscan" "You may need to configure overscan if black bars are present on display" \
    "A2 Hostname" "Set the visible name for this Pi on a network" \
    "A3 Memory Split" "Change the amount of memory made available to the GPU" \
    "A4 SSH" "Enable/Disable remote command line access to your Pi using SSH" \
    "A5 SPI" "Enable/Disable automatic loading of SPI kernel module (needed for e.g. PiFace)" \
    "A6 Audio" "Force audio out through HDMI or 3.5mm jack" \
    "A7 Update" "Update this tool to the latest version" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      A1\ *) do_overscan ;;
      A2\ *) do_change_hostname ;;
      A3\ *) do_memory_split ;;
      A4\ *) do_ssh ;;
      A5\ *) do_spi ;;
      A6\ *) do_audio ;;
      A7\ *) do_update ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
}


#
# Interactive use loop
#
calc_wt_size
while true; do
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
    "1 Expand Filesystem" "Ensures that all of the SD card storage is available to the OS" \
    "2 Change User Password" "Change password for the default user (pi)" \
    "3 Enable Boot to Desktop/Scratch" "Choose whether to boot into a desktop environment, Scratch, or the command-line" \
    "4 Internationalisation Options" "Set up language and regional settings to match your location" \
    "5 Enable Camera" "Enable this Pi to work with the Raspberry Pi Camera" \
    "6 Add to Rastrack" "Add this Pi to the online Raspberry Pi Map (Rastrack)" \
    "7 Overclock" "Configure overclocking for your Pi" \
    "8 Advanced Options" "Configure advanced settings" \
    "9 About raspi-config" "Information about this configuration tool" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    do_finish
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      1\ *) do_expand_rootfs ;;
      2\ *) do_change_pass ;;
      3\ *) do_boot_behaviour ;;
      4\ *) do_internationalisation_menu ;;
      5\ *) do_camera ;;
      6\ *) do_rastrack ;;
      7\ *) do_overclock ;;
      8\ *) do_advanced_menu ;;
      9\ *) do_about ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  else
    exit 1
  fi
done