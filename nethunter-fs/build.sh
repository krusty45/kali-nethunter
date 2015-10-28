#!/bin/bash

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo "Please run this as root"
   exit
fi

# Default help if no arguments are supplied
if [[ $# -eq 0 ]] ; then
	echo "Usage: build.sh"
	echo "-f, --full         : A full build with all packages"
	echo "-m, --minimal      : A minimal build with only the most basic packages"
# echo "-a, --arch         : Select architecture. (Default: armhf)"
# echo "                        e.g. armhf, i686, mips, x86"
  exit 0
fi

# Set default architecture for most Android devices
export architecture="armhf"

# Dependency checks
dep_check(){
DEPS=(git-core gnupg flex bison gperf libesd0-dev build-essential \
zip curl libncurses5-dev zlib1g-dev libncurses5-dev gcc-multilib g++-multilib \
parted kpartx debootstrap pixz qemu-user-static abootimg cgpt vboot-kernel-utils \
vboot-utils bc lzma lzop automake autoconf m4 dosfstools rsync u-boot-tools \
schedtool git e2fsprogs device-tree-compiler ccache dos2unix debootstrap)

for i in "${DEPS[@]}"
do
  PKG_OK=$(dpkg-query -W --showformat='${Status}\n' ${i}|grep "install ok installed")
  echo "[+] Checking for installed dependency: ${i}"
  if [ "" == "$PKG_OK" ]; then
    echo "[-] Missing dependency: ${i}"
    echo "[+] Attempting to install...."
    sudo apt-get -y install ${i}
  fi
done

echo "[+] All done! Creating hidden file .dep_check so we don't have preform check again."
touch .dep_check
}

# Run dependency check once (see above for dep check)
if [ ! -f ".dep_check" ]; then
  dep_check
else
  echo "[+] Dependency check previously conducted. To rerun remove file .dep_check"
fi

if [ -d "kali-$architecture" ]; then
  echo "Detected prebuilt chroot."
  echo ""
  read -p "Would you like to create a new chroot? (y/n): " -e -i "y" createrootfs
    if [ "$createrootfs" == "y" ]; then
      echo "Removing previous chroot"
      rm -rf kali-$architecture
    else
      echo "Exiting"
      exit
    fi
else
  echo "Previous rootfs build not found. Ready to build."
  sleep 1
fi

if [ "$1" == "--minimal" ] || [ "$1" == "-m" ]; then
  if [ -f "output/kalifs-minimal.tar.xz" ]; then
    echo "Detected previously created chroot output file: output/kalifs-minimal.tar.xz."
    echo ""
    read -p "Would you like to create a new file? (y/n): " -e -i "y" createnewxz
    if [ "$createnewxz" == "y" ]; then
      echo "Removing previous chroot"
      rm -rf output/kalifs-minimal.tar.xz output/kalifs-minimal.sha1sum
    else
      echo "Exiting"
      exit
    fi
  fi
fi

if [ "$1" == "--full" ] || [ "$1" == "-f" ]; then
  if [ -f "output/kalifs-full.tar.xz" ]; then
    echo "Detected previously created chroot output file: output/kalifs-full.tar.xz."
    echo ""
    read -p "Would you like to create a new file? (y/n): " -e -i "y" createnewxz
    if [ "$createnewxz" == "y" ]; then
      echo "Removing previous chroot"
      rm -rf output/kalifs-full.tar.xz output/kalifs-full.sha1sum
    else
      echo "Exiting"
      exit
    fi
  fi
fi

# Add packages you want installed here:
# MINIMAL PACKAGES
# Hostapd, openssh, and kismet have custom configuration files
# So they need to be installed also since we use sed to replace
# pciutils is needed for wifite (unsure why) and apt-transport-https for updates

arm="abootimg cgpt fake-hwclock ntpdate vboot-utils vboot-kernel-utils"
minimalnh="pciutils usbutils hostapd openssh-server kismet apt-transport-https dnsmasq"

# DEFAULT PACKAGES
base="kali-menu kali-defaults initramfs-tools usbutils openjdk-7-jre mlocate google-nexus-tools"
desktop="kali-defaults kali-root-login desktop-base xfce4 xfce4-places-plugin xfce4-goodies"
tools="nmap metasploit-framework tcpdump tshark wireshark burpsuite armitage sqlmap recon-ng wipe socat ettercap-text-only beef-xss set device-pharmer nishang"
wireless="wifite pixiewps iw aircrack-ng gpsd kismet kismet-plugins giskismet dnsmasq dsniff sslstrip mdk3 mitmproxy"
services="autossh openssh-server tightvncserver apache2 postgresql openvpn php5"
extras="wpasupplicant zip macchanger dbd florence libffi-dev python-setuptools python-pip hostapd ptunnel tcptrace dnsutils p0f mitmf"
mana="python-twisted python-dnspython libssl-dev sslsplit python-pcapy tinyproxy isc-dhcp-server rfkill"
bdf="backdoor-factory bdfproxy"
spiderfoot="python-lxml python-m2crypto python-netaddr python-mako"
sdr="sox librtlsdr-dev "

# If minimal, set only minimal packages
if [ "$1" == "--minimal" ] || [ "$1" == "-m" ]; then
	export packages="${arm} ${minimalnh}"
  filename=kalifs-minimal
fi

# If full install, set all packages
if [ "$1" == "--full" ] || [ "$1" == "-f" ]; then
	export packages="${arm} ${base} ${desktop} ${tools} ${wireless} ${services} \
                   ${extras} ${mana} ${spiderfoot} ${sdr} ${bdf}"
  filename=kalifs-full
fi

# Need to find where this error occurs, but we make nano read
# only during build and reset after installation is completed
chattr +i /bin/nano

# Stage 1 - Debootstrap creates basic chroot
echo "[+] Starting stage 1 (debootstrap)"
source stages/stage1

# Stage 2 - Adds repo, bash_profile, hosts file
echo "[+] Starting stage 2 (repo/config)"
source stages/stage2

# Stage 3 - Downloads all packages, modify configuration files
echo "[+] Starting stage 3 (packages/installation)"
source stages/stage3

# Cleanup stage
echo "[+] Starting stage 4 (cleanup)"
source stages/stage4-cleanup 

# Compress final file
tar -cf - kali-armhf/ | xz -9 -c - > output/${filename}.tar.xz
sha1sum output/${filename}.tar.xz > output/${filename}.sha1sum

# Remove read only from nano
chattr -i /bin/nano

umount kali-$architecture/dev/pts
umount kali-$architecture/dev/
umount kali-$architecture/proc

echo "[+] Finished!  Check output folder for chroot"

# Extract on device
# xz -d /sdcard/kalifs.tar.xz | tar xvf /sdcard/kalifs.tar -C /data/local/
