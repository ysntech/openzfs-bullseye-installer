#!/usr/bin/env bash
###########################################################################################################
# Bash Script of this Documentation :
# https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bullseye%20Root%20on%20ZFS.html#debian-bullseye-root-on-zfs
#
# Copyright © 2022 - installer.sh
# Yasin Karabulak
# info@yasinkarabulak.com
# https://github.com/unique1984
#
###########################################################################################################

# this will open step by step progress [ 1 / 0 ]
STEP_BY_STEP=1

export bPoolName="bpool"
export rPoolName="rpool"

function dividerLine {
  echo -e "\n######################################################################"
  echo -e "#    $1"
  echo -e "######################################################################\n"
}

function innerSeperator {
  echo -e "----------------------------------------------------------------------"
  echo -e "    $1"
  echo -e "----------------------------------------------------------------------"
}

function amiAllowed {
  dividerLine "USE AT YOUR OWN RISK !!! THIS THING DOES BAD THINGS TO YOUR PHYSICAL HARD DRIVE !!!"
  read -r -p "If you want to continue then [ Enter ]"
  if [ "$(whoami)" != "root" ]; then
    echo -e "$(whoami) !"
    echo -e "Start this script as root!"
    exit 1
  fi
}

function stepByStep {
    if [[ $STEP_BY_STEP -eq 1 ]]; then
      echo -e "\n"
      read -p "Function : $1 [ Press Enter to Continue ... ]"
      echo -e "\n"
    fi
}

APT_SOURCES_HTTP=$(cat <<EOF
deb http://deb.debian.org/debian/ bullseye main contrib non-free
deb-src http://deb.debian.org/debian/ bullseye main contrib non-free

deb http://deb.debian.org/debian/ bullseye-updates main contrib non-free
deb-src http://deb.debian.org/debian/ bullseye-updates main contrib non-free

deb http://deb.debian.org/debian-security bullseye-security main contrib
deb-src http://deb.debian.org/debian-security bullseye-security main contrib
EOF
)

APT_SOURCES_HTTPS=$(cat <<EOF
deb https://deb.debian.org/debian/ bullseye main contrib non-free
deb-src https://deb.debian.org/debian/ bullseye main contrib non-free

deb https://deb.debian.org/debian/ bullseye-updates main contrib non-free
deb-src https://deb.debian.org/debian/ bullseye-updates main contrib non-free

deb https://deb.debian.org/debian-security bullseye-security main contrib
deb-src https://deb.debian.org/debian-security bullseye-security main contrib
EOF
)

function aptSourcesHttp {
  if [ ! -z $1 ]; then
    echo -e "${APT_SOURCES_HTTP}" > /mnt/etc/apt/sources.list
  else
    echo -e "${APT_SOURCES_HTTP}" > /etc/apt/sources.list
  fi

  stepByStep "aptSourcesHttp"
}

function aptSourcesHttps {
  if [ ! -z $1 ]; then
    echo -e "${APT_SOURCES_HTTPS}" > /mnt/etc/apt/sources.list
  else
    echo -e "${APT_SOURCES_HTTPS}" > /etc/apt/sources.list
  fi

  stepByStep "aptSourcesHttps"
}

function aptUpdateUpgrade {
  dividerLine "Apt Update & Upgrade & Autoremove"
  apt -qqq update -y
  apt -qq upgrade -y
  apt -qq autoremove -y
}

function installBaseApps {
  dividerLine "Base Applications Installation"
  apt -qqq update -y
  yes | apt -qq install -y bash-completion debootstrap dpkg-dev dkms gdisk parted zfsutils-linux mdadm sed ovmf
  modprobe zfs

  stepByStep "installBaseApps"
}

function selectInstallationDisk {
  dividerLine "Disk Selection"
  count=0
  for i in $(lsblk | grep -v '^NAME' | grep -iPo '^[a-z]+'); do
  DRIVE=$(ls -l /dev/disk/by-id/ | grep -P $i'$' | awk '{print $9}' | head -n1)
    if [ ! -z "${DRIVE}" ]; then
      export DISK$count="/dev/disk/by-id/${DRIVE}"
      echo -e "$count.\t/dev/$i\t/dev/disk/by-id/${DRIVE}"
      count=$((count+1))
    fi
  done

  read -r -p "Select Disk For The Base Installation [ `echo $(seq 0 $((count-1)))` ] : " installationDiskNumber
  if [ -z $installationDiskNumber ]; then
    echo -e "\nDisk must be selected !\n"
    unset count
    unset i
    unset DRIVE
    selectInstallationDisk
  fi

  export DISK=$(env | grep -iPo '^DISK'$installationDiskNumber'=\K.*')

  echo -e
  read -r -p "Selected disk is : ${DISK} confirm ? [ Y / n ] " diskSelectConfirm

  if [ -z "${diskSelectConfirm}" ] || [ "${diskSelectConfirm}" == "y" ] || [ "${diskSelectConfirm}" == "Y" ]; then
    innerSeperator "\nThe --- ${DISK} --- is selected!\n"
  else
    unset count
    unset i
    unset DRIVE
    unset DISK
    selectInstallationDisk
  fi

  stepByStep "selectInstallationDisk"
}

function listDisks {
  dividerLine "List Installed DISKs on the system"
  count=0
  for i in $(lsblk | grep -v '^NAME' | grep -iPo '^[a-z]+'); do
  DRIVE=$(ls -l /dev/disk/by-id/ | grep -P $i'$' | awk '{print $9}' | head -n1)
    if [ ! -z "${DRIVE}" ]; then
      export DISK$count="/dev/disk/by-id/${DRIVE}"
      # echo -e "$count.\t/dev/$i\t/dev/disk/by-id/${DRIVE}"
      count=$((count+1))
    fi
  done

  env | grep -P "DISK[0-9]+" | sort

  stepByStep "listDisks"
}

function swapsOffline {
  dividerLine "All swaps off!"
  swapoff --all
}

function checkMdadmArray {
  dividerLine "Check mdadm raid configuration!"
  cat /proc/mdstat
  MDADM_CHECK=$(cat <<EOF
mdadm --stop /dev/md0							# If so, stop them (replace ``md0`` as required):
mdadm --zero-superblock --force ${DISK}			# For an array using the whole disk:
mdadm --zero-superblock --force ${DISK}-part2	# For an array using a partition:
EOF
)
  echo -e "${MDADM_CHECK}"

  stepByStep "checkMdadmArray"
}

function clearupOldZfs {
  dividerLine "Cleanup old ZFS partitions on the disk!"
  innerSeperator "Label clear"
  zpool labelclear -f "${DISK}"
  innerSeperator "Wipe File System"
  wipefs -a "${DISK}"
  innerSeperator "Destroy the GPT and MBR data structures"
  sgdisk --zap-all "${DISK}"
  innerSeperator "Read the partition changes, inform the system!"
  partprobe
  innerSeperator "Active Disk configuration is :"
  lsblk

  stepByStep "clearupOldZfs"
}

function uefiPartitioning {
  dividerLine "UEFI Partitioning"
  innerSeperator "Boot UEFI partition"
  sgdisk -n2:1M:+512M -t2:EF00 "${DISK}"	# boot UEFI
  innerSeperator "Boot pool partition"
  sgdisk -n3:0:+1G -t3:BF01 "${DISK}"		# boot pool
  innerSeperator "root pool partition"
  sgdisk -n4:0:0 -t4:BF00 "${DISK}"		#root pool
  innerSeperator "Read the partition changes, inform the system!"
  partprobe
  innerSeperator "Active Disk configuration is :"
  lsblk

  stepByStep "uefiPartitioning"
}

function setBpoolName {
  read -r -p "Set new bpool name [a-z] : e.g [ bootpool ] " bpoolNameNew

  if [ -z "${bpoolNameNew}" ]; then
    bpoolNameNew="bootpool"
  fi

  read -r -p "New bpool name is ${bpoolNameNew} : [ Y / n ]" bpoolNameConfirm

  if [ -z "${bpoolNameConfirm}" ] || [ "${bpoolNameConfirm}" == "Y" ] || [ "${bpoolNameConfirm}" == "y" ]; then
    unset bpoolName
    export bpoolName="${bpoolNameNew}"
  else
    setBpoolName
  fi
}

function setRpoolName {
  read -r -p "Set new rpool name [a-z] : e.g [ rootpool ] " rpoolNameNew

  if [ -z "${rpoolNameNew}" ]; then
    rpoolNameNew="rootpool"
  fi

  read -r -p "New rpool name is ${rpoolNameNew} : [ Y / n ]" rpoolNameConfirm

  if [ -z "${rpoolNameConfirm}" ] || [ "${rpoolNameConfirm}" == "Y" ] || [ "${rpoolNameConfirm}" == "y" ]; then
    unset rpoolName
    export rpoolName="${rpoolNameNew}"
  else
    setRpoolName
  fi
}

function checkSystemHaveZfsPool {
  systemPools=$(zpool status 2> /dev/null | grep -iPo "pool: \K.*")

  if [ ! -z "${systemPools}" ]; then
    zpool status
    hasBpool=$(grep "bpool" <<< "${systemPools}")
    hasRpool=$(grep "rpool" <<< "${systemPools}")

    if [ ! -z "${hasBpool}" ]; then
      setBpoolName
    fi

    if [ ! -z "${hasRpool}" ]; then
      setRpoolName
    fi

#    checkSystemHaveZfsPool # check again!
  fi
}

function createBootPool {
  dividerLine "Creating BOOT pool"
  if [ -L "${DISK}"-part3 ]; then
    zpool create -f \
        -o cachefile=/etc/zfs/zpool.cache \
        -o ashift=12 -d \
        -o feature@async_destroy=enabled \
        -o feature@bookmarks=enabled \
        -o feature@embedded_data=enabled \
        -o feature@empty_bpobj=enabled \
        -o feature@enabled_txg=enabled \
        -o feature@extensible_dataset=enabled \
        -o feature@filesystem_limits=enabled \
        -o feature@hole_birth=enabled \
        -o feature@large_blocks=enabled \
        -o feature@livelist=enabled \
        -o feature@lz4_compress=enabled \
        -o feature@spacemap_histogram=enabled \
        -o feature@zpool_checkpoint=enabled \
        -O acltype=posixacl -O canmount=off -O compression=lz4 \
        -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
        -O mountpoint=/boot -R /mnt \
      "${bpoolName}" "${DISK}"-part3

    innerSeperator "Listing ZFS Filesystem"
    zfs list -t filesystem
  else
    dividerLine "There must be an error! can't find : ${DISK}-part3"
    lsblk
    exit 1
  fi

  stepByStep "createBootPool"
}

function createRootPool {
  dividerLine "Creating ROOT pool"

  if [ -L "${DISK}"-part4 ]; then
    zpool create -f \
      -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
      -O dnodesize=auto -O normalization=formD -O relatime=on \-O xattr=sa \
      -O mountpoint=/ -R /mnt "${rpoolName}" "${DISK}"-part4

    innerSeperator "Listing ZFS Filesystem"
    zfs list -t filesystem
  else
    dividerLine "There must be an error! can't find : ${DISK}-part4"
    lsblk
    exit 1
  fi

  stepByStep "createRootPool"
}

function createPoolsAndMounts {
  dividerLine "Creating Mount Pools"

  innerSeperator "Creating ${rpoolName}/BOOT & ${bpoolName}/BOOT"
  zfs create -o canmount=off -o mountpoint=none ${rpoolName}/ROOT
  zfs create -o canmount=off -o mountpoint=none ${bpoolName}/BOOT

  innerSeperator "Creating and mounting root ( / ) filesystem"
  zfs create -o canmount=noauto -o mountpoint=/ ${rpoolName}/ROOT/debian
  zfs mount ${rpoolName}/ROOT/debian

  innerSeperator "Creating ${bpoolName}/BOOT/debian pool [ EFI system nesting directory]"
  zfs create -o mountpoint=/boot ${bpoolName}/BOOT/debian

  innerSeperator "Creating ${rpoolName}/home"
  zfs create ${rpoolName}/home
  innerSeperator "Creating and mounting ${rpoolName}/home/root to /root"
  zfs create -o mountpoint=/root ${rpoolName}/home/root
  chmod 700 /mnt/root
  innerSeperator "Creating ${rpoolName}/var"
  zfs create -o canmount=off ${rpoolName}/var
  innerSeperator "Creating ${rpoolName}/var/lib"
  zfs create -o canmount=off ${rpoolName}/var/lib
  innerSeperator "Creating ${rpoolName}/var/log"
  zfs create ${rpoolName}/var/log
  innerSeperator "Creating ${rpoolName}/var/mail"
  zfs create ${rpoolName}/var/mail
  innerSeperator "Creating ${rpoolName}/var/www"
  zfs create ${rpoolName}/var/www
  innerSeperator "Creating ${rpoolName}/var/spool"
  zfs create ${rpoolName}/var/spool
  innerSeperator "Creating ${rpoolName}/var/cache (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false  ${rpoolName}/var/cache
  innerSeperator "Creating ${rpoolName}/var/tmp (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false  ${rpoolName}/var/tmp
  innerSeperator "Setting sticky bit [ 1 ] for /mnt/var/tmp (only owner)"
  chmod 1777 /mnt/var/tmp
  innerSeperator "Creating ${rpoolName}/opt"
  zfs create ${rpoolName}/opt
  innerSeperator "Creating ${rpoolName}/usr"
  zfs create -o canmount=off ${rpoolName}/usr
  innerSeperator "Creating ${rpoolName}/usr/local"
  zfs create ${rpoolName}/usr/local
  innerSeperator "Creating ${rpoolName}/var/lib/docker (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false  ${rpoolName}/var/lib/docker
  innerSeperator "Creating ${rpoolName}/var/lib/nfs (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false  ${rpoolName}/var/lib/nfs
  innerSeperator "Creating /mnt/run"
  mkdir /mnt/run
  innerSeperator "Mounting /mnt/run using tmp filesystem"
  mount -t tmpfs tmpfs /mnt/run
  innerSeperator "Creating /mnt/run/lock"
  mkdir /mnt/run/lock

  innerSeperator "Listing ZFS Filesystem"
  zfs list -t filesystem

  stepByStep "createPoolsAndMounts"
}

function installBaseSystem {
  dividerLine "Installing Debian bullseye base system !"
  debootstrap bullseye /mnt

  stepByStep "installBaseSystem"
}

function copyPoolCache {
  dividerLine "Copy pool cache to base system"
  mkdir /mnt/etc/zfs
  cp /etc/zfs/zpool.cache /mnt/etc/zfs/

  stepByStep "copyPoolCache"
}

function changeHostNameBaseSystem {
  dividerLine "Changing base system's hostname"
  read -r -p "What will be the name of your ZFS bullseye e.g. [ $(hostname)-zfs ? ] " newHostname
  if [ -z "${newHostname}" ]; then
    newHostname=$(hostname)-zfs
  fi

  sed '2 i 127.0.1.1\t'"${newHostname}" /etc/hosts > /mnt/etc/hosts

  stepByStep "changeHostNameBaseSystem"
}

function changeNetworkConfOfBaseSystem {
  dividerLine "Changing base system's network configuration"
  CHANGE_NET_IF=$(cat <<EOF
auto eth0
iface eth0 inet dhcp
EOF
)
  echo -e "${CHANGE_NET_IF}" > /mnt/etc/network/interfaces.d/eth0

  stepByStep "changeNetworkConfOfBaseSystem"
}

function addAptSourcesToBaseSystem {
  dividerLine "Adding /etc/apt/sources.list to base system"
  aptSourcesHttp "mnt"

  stepByStep "addAptSourcesToBaseSystem"
}

function makePrivateDirectories {
  mount --make-private --rbind /dev  /mnt/dev
  mount --make-private --rbind /proc /mnt/proc
  mount --make-private --rbind /sys  /mnt/sys

  stepByStep "makePrivateDirectories"
}

function chrootUpdate {
  dividerLine "chroot and apt update the base system"
  chroot /mnt apt -qq update

  stepByStep "chrootUpdate"
}

function chrootUpgrade {
  dividerLine "chroot and apt upgrade the base system"
  chroot /mnt apt -qq upgrade -y

  stepByStep "chrootUpgrade"
}

function chrootAutoremove {
  dividerLine "chroot and apt autoremove the base system"
  chroot /mnt apt -qq autoremove -y

  stepByStep "chrootAutoremove"
}

function chrootInstallBaseApps {
  dividerLine "Apt install chrooted system's applications"
  chroot /mnt apt -qq install -y sudo parted htop screen bash-completion apt-transport-https openssh-server \
      ca-certificates console-setup locales dosfstools grub-efi-amd64 shim-signed gdisk

  stepByStep "chrootInstallBaseApps"
}

function chrootSymlinkMounts {
  dividerLine "Chroot Symlink Mounts"
  chroot /mnt ln -s /proc/self/mounts /etc/mtab

  stepByStep "chrootSymlinkMounts"
}

function chrootDpkgReconfigure {
  dividerLine "Chroot DPKG reconfigure"
  chroot /mnt dpkg-reconfigure locales tzdata keyboard-configuration console-setup

  stepByStep "chrootDpkgReconfigure"
}

function chrootInstallKernelHeaders {
  dividerLine "Chroot Install Kernel headers"
  chroot /mnt apt -qq install -y dpkg-dev linux-headers-amd64 linux-image-amd64
  chroot /mnt apt -qq install -y zfs-initramfs

  chroot /mnt echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf

  stepByStep "chrootInstallKernelHeaders"
}

function chrootWriteUefiPart {
  dividerLine "Chroot Write UEFI boot"

  innerSeperator "Grub Probe [ you should see 'zfs']"
  chroot /mnt grub-probe /boot
  lsblk
  innerSeperator "mkdosfs EFI part"
  chroot /mnt /usr/bin/env DISK="${DISK}" mkdosfs -F 32 -s 1 -n EFI ${DISK}-part2
  innerSeperator "Create /boot/efi"
  chroot /mnt mkdir /boot/efi
  innerSeperator "Write /etc/fstab"
#  chroot /mnt /usr/bin/env DISK="${DISK}" echo -e ${DISK}-part2" /boot/efi vfat defaults 0 0" >> /etc/fstab
  bootEfiUuid=$(blkid -s UUID -o value ${DISK}-part2)
    if [ ! -z "${bootEfiUuid}" ]; then
      innerSeperator "UUID : ${bootEfiUuid}"
      echo -e "/dev/disk/by-uuid/${bootEfiUuid} /boot/efi vfat defaults 0 0" >> /mnt/etc/fstab
    else
      innerSeperator "DISK BY  ID : ${DISK}-part2"
      echo -e "${DISK}-part2 /boot/efi vfat defaults 0 0" >> /mnt/etc/fstab
    fi
  innerSeperator "Mount EFI"
  chroot /mnt mount /boot/efi
  innerSeperator "Purge os-prober [ Dual boot systems don't needed ]"
  chroot /mnt apt remove -y --purge os-prober

  stepByStep "chrootWriteUefiPart"
}

function chrootCreateRootPassword {
  dividerLine "Chrooted System Change 'root' password"
#  read -rs -p "Create root password : " chrootRootPassword
  chroot /mnt passwd

  stepByStep "chrootCreateRootPassword"
}

function chrootImportBpoolService {
  dividerLine "Chroot Create and enable Bpool service"
  export BPOOL_SERVICE=$(cat <<EOF
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none ${bpoolName}
# Work-around to preserve zpool cache:
ExecStartPre=-/bin/mv /etc/zfs/zpool.cache /etc/zfs/preboot_zpool.cache
ExecStartPost=-/bin/mv /etc/zfs/preboot_zpool.cache /etc/zfs/zpool.cache

[Install]
WantedBy=zfs-import.target
EOF
)

  innerSeperator "Write service file"
  echo -e "${BPOOL_SERVICE}" > /mnt/etc/systemd/system/zfs-import-${bpoolName}.service
  innerSeperator "Enable service"
  chroot /mnt /usr/bin/env bpoolName=${bpoolName} systemctl enable zfs-import-${bpoolName}.service
  innerSeperator "Enable tmp.mount service"
  chroot /mnt cp /usr/share/systemd/tmp.mount /etc/systemd/system/
  chroot /mnt systemctl enable tmp.mount

  stepByStep "chrootImportBpoolService"
}

function chrootUpdateInitRamFs {
  dividerLine "Chroot Update Init Ram Filesystem"
  chroot /mnt update-initramfs -c -k all

  stepByStep "chrootUpdateInitRamFs"
}

function chrootChangeGrubDefaults {
  dividerLine "Chroot set /etc/default/grub file"
  chroot /mnt sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/g' /etc/default/grub
  chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="console"/g' /etc/default/grub
  chroot /mnt /usr/bin/env rpoolName=${rpoolName} sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="root=ZFS='${rpoolName}'\/ROOT\/debian net.ifnames=0 biosdevname=0"/g' /etc/default/grub
  chroot /mnt update-grub

  stepByStep "chrootChangeGrubDefaults"
}

function chrootGrubInstall {
  dividerLine "Chroot grub install"
  chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-floppy

  stepByStep "chrootGrubInstall"
}

function chrootZfsListCaches {
  dividerLine "Chroot ZFS list caches"
  chroot /mnt mkdir /etc/zfs/zfs-list.cache
  chroot /mnt /usr/bin/env bpoolName=${bpoolName} touch /etc/zfs/zfs-list.cache/${bpoolName}
  chroot /mnt /usr/bin/env rpoolName=${rpoolName} touch /etc/zfs/zfs-list.cache/${rpoolName}
  chroot /mnt ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
  chroot /mnt zed -F &
  innerSeperator "When you see changes on the screen [ Ctrl + C ]"
  sleep 3
  chroot /mnt /usr/bin/env bpoolName=${bpoolName} watch -n1 cat /etc/zfs/zfs-list.cache/${bpoolName}
  innerSeperator "When you see changes on the screen [ Ctrl + C ]"
  sleep 3
  chroot /mnt /usr/bin/env rpoolName=${rpoolName} watch -n1 cat /etc/zfs/zfs-list.cache/${rpoolName}
  innerSeperator "Chroot get the zed application and exit [ Ctrl + C ]"
  chroot /mnt pkill -15 zed

  stepByStep "chrootZfsListCaches"
}

function chrootChangeMntDir {
  dividerLine "Chroot change '/mnt/' to '/' root file system"
  sed -Ei "s|/mnt/?|/|" /mnt/etc/zfs/zfs-list.cache/*

  stepByStep "chrootChangeMntDir"
}

function afterReboot {
  dividerLine "After the reboot you might want to start 'after-reboot.sh':"
  AFTER_REBOOT_SH=$(cat <<EOF
#!/usr/bin/env bash

function dividerLine {
  echo -e "\\\n######################################################################"
  echo -e "#    \$1"
  echo -e "######################################################################\\\n"
}

function innerSeperator {
  echo -e "----------------------------------------------------------------------"
  echo -e "    \$1"
  echo -e "----------------------------------------------------------------------"
}

function getUserPassword {
    read -rs -p "Password : " userPass
    echo ""
    read -rs -p "Password (Re) : " userPassSecond

    if [ "\${userPass}" != "\${userPassSecond}" ]; then
      echo -e "Passwords don't match!"
      unset userPass
      unset userPassSecond
      getUserPassword
    fi
}

function addNewUserToBaseSystem {
  dividerLine "Add New User to System"
  read -r -p "Username : [ Username / N (continue without) ] " username

  if [ -z "\${username}" ]; then
    echo -e "You should give a username or 'N' to continue without one!"
    addNewUserToBaseSystem
  fi

  if [ ! "\${username}" == "n" ] || [ ! "\${username}" == "N" ]; then
    innerSeperator "The username is : \${username}"
    innerSeperator "ZFS Create \${username} 's pool"
    zfs create ${rpoolName}/home/\${username}
    chown -R \${username}:\${username} /home/\${username}
    adduser "\${username}"
    cp -a /etc/skel/. /home/\${username}
    chown -R \${username}:\${username} /home/\${username}
    usermod -a -G audio,cdrom,dip,floppy,netdev,plugdev,sudo,video \${username}
    innerSeperator "Set user password"
    getUserPassword
    echo "\${username}:\${userPass}" | chpasswd
    innerSeperator "\${username} 's Password has Changed"
  fi
}

function startTaskSel {
  dividerLine "TASKSEL"
  tasksel
}

addNewUserToBaseSystem
startTaskSel

EOF
)
  innerSeperator "/root/after-reboot.sh script generated."
  echo -e "${AFTER_REBOOT_SH}" > /mnt/root/after-reboot.sh
#  echo -e "${AFTER_REBOOT_SH}" > "$(pwd)"/after-reboot.sh
  chmod 700 /mnt/root/after-reboot.sh
#  chmod 700 "$(pwd)"/after-reboot.sh

  stepByStep "afterReboot"
}

function chrootTakeInitialSnapshots {
  dividerLine "Chroot take initial snapshots"
  chroot /mnt /usr/bin/env bpoolName=${bpoolName} zfs snapshot ${bpoolName}/BOOT/debian@initial
  chroot /mnt /usr/bin/env rpoolName=${rpoolName} zfs snapshot ${rpoolName}/ROOT/debian@initial

  stepByStep "chrootTakeInitialSnapshots"
}

function unmountAllFilesystems {
  dividerLine "Unmount all ZFS /mnt partitions"
  mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}		# LiveCD environment to unmount all filesystems

  stepByStep "unmountAllFilesystems"
}

function exportZfsPools {
  dividerLine "Export ZFS Pools"
  zpool export -f "${bpoolName}"
  zpool export -f "${rpoolName}"

  stepByStep "exportZfsPools"
}

function rebootSystem {
  read -r -p "Reboot the system : [ Y / n ] " rebootConfirm

  if [ -z "${rebootConfirm}" ] || [ "${rebootConfirm}" == "Y" ] || [ "${rebootConfirm}" == "y" ]; then
    dividerLine "System will reboot in 5 seconds..."
    sleep 5
    reboot
  fi
  stepByStep "rebootSystem"
}

#chroot /mnt /usr/bin/env DISK=$DISK bash --login
##### START #####
amiAllowed
aptSourcesHttp
installBaseApps
aptSourcesHttps
aptUpdateUpgrade
selectInstallationDisk
#listDisks
swapsOffline
checkMdadmArray
clearupOldZfs
uefiPartitioning
checkSystemHaveZfsPool
createBootPool
createRootPool
createPoolsAndMounts
installBaseSystem
copyPoolCache
changeHostNameBaseSystem
changeNetworkConfOfBaseSystem
addAptSourcesToBaseSystem
makePrivateDirectories
chrootUpdate
chrootUpgrade
chrootAutoremove
chrootInstallBaseApps
aptSourcesHttps "mnt"
chrootUpdate
chrootUpgrade
chrootAutoremove
chrootSymlinkMounts
chrootDpkgReconfigure
chrootInstallKernelHeaders
chrootWriteUefiPart
chrootCreateRootPassword
chrootImportBpoolService
chrootUpdateInitRamFs
chrootChangeGrubDefaults
chrootGrubInstall
chrootZfsListCaches
chrootChangeMntDir
afterReboot
chrootTakeInitialSnapshots
unmountAllFilesystems
exportZfsPools
rebootSystem
