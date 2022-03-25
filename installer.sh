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

export RAID_TAGS=("" "mirror" "raidz1" "raidz2" "raidz3" "mirror" "raidz1" "raidz2" "raidz3")

export RAID_MINIMUM_DISKS=("1" "2" "2" "3" "4" "4" "4" "6" "8")

export RAID_TYPES=("[single | stripe] (RAID-0)"
  "[mirror] (RAID-1)"
  "[raidz1] (RAID-5)"
  "[raidz2] (RAID-6)"
  "[raidz3]"
  "[mirror + stripe] (RAID-10)"
  "[raidz1 + stripe] (RAID-50)"
  "[raidz2 + stripe] (RAID-60)"
  "[raidz3 + stripe]")

export RAID_EXPL=("(1+n)"
  "(2+n)"
  "(2+n)"
  "(3+n)"
  "(4+n)"
  "(2+n)*X"
  "(2+n)*X"
  "(3+n)*X"
  "(4+n)*X")

APT_SOURCES_HTTP=$(
  cat <<EOF
deb http://deb.debian.org/debian/ bullseye main contrib non-free
deb-src http://deb.debian.org/debian/ bullseye main contrib non-free

deb http://deb.debian.org/debian/ bullseye-updates main contrib non-free
deb-src http://deb.debian.org/debian/ bullseye-updates main contrib non-free

deb http://deb.debian.org/debian-security bullseye-security main contrib
deb-src http://deb.debian.org/debian-security bullseye-security main contrib
EOF
)
export APT_SOURCES_HTTP

APT_SOURCES_HTTPS=$(
  cat <<EOF
deb https://deb.debian.org/debian/ bullseye main contrib non-free
deb-src https://deb.debian.org/debian/ bullseye main contrib non-free

deb https://deb.debian.org/debian/ bullseye-updates main contrib non-free
deb-src https://deb.debian.org/debian/ bullseye-updates main contrib non-free

deb https://deb.debian.org/debian-security bullseye-security main contrib
deb-src https://deb.debian.org/debian-security bullseye-security main contrib
EOF
)
export APT_SOURCES_HTTPS

function dividerLine() {
  echo -e "\n######################################################################"
  echo -e "#    $1"
  echo -e "######################################################################\n"
}

function innerSeperator() {
  echo -e "----------------------------------------------------------------------"
  echo -e "    $1"
  echo -e "----------------------------------------------------------------------"
}

function amiAllowed() {
  dividerLine "USE AT YOUR OWN RISK !!! THIS THING DOES BAD THINGS TO YOUR PHYSICAL HARD DRIVE !!!"
  read -r -p "If you want to continue then [ Enter ]"
  if [ "$(whoami)" != "root" ]; then
    echo -e "$(whoami) !"
    echo -e "Start this script as root!"
    exit 1
  fi
}

function stepByStep() {
  if [[ $STEP_BY_STEP -eq 1 ]]; then
    echo -e "\n"
    read -p "Function : $1 [ Press Enter to Continue ... ]"
    echo -e "\n"
    clear
    return
  fi
  clear
}

function aptSourcesHttp() {
  if [ ! -z $1 ]; then
    echo -e "${APT_SOURCES_HTTP}" >/mnt/etc/apt/sources.list
  else
    echo -e "${APT_SOURCES_HTTP}" >/etc/apt/sources.list
  fi

  stepByStep "aptSourcesHttp"
}

function aptSourcesHttps() {
  if [ ! -z $1 ]; then
    echo -e "${APT_SOURCES_HTTPS}" >/mnt/etc/apt/sources.list
  else
    echo -e "${APT_SOURCES_HTTPS}" >/etc/apt/sources.list
  fi

  stepByStep "aptSourcesHttps"
}

function aptUpdateUpgrade() {
  dividerLine "Apt Update & Upgrade & Autoremove"
  apt -qqq update -y
  apt -qq upgrade -y
  apt -qq autoremove -y
}

function installBaseApps() {
  dividerLine "Base Applications Installation"
  apt -qqq update -y
  yes | apt -qq install -y bash-completion debootstrap dpkg-dev dkms gdisk parted zfsutils-linux mdadm ovmf
  modprobe zfs

  stepByStep "installBaseApps"
}

#------------------------------------------------ from here

function selectSystemDisk() {
  dividerLine "Selecting System Disk"
  lsblk
  echo -e "\n"
  read -r -p "Select the system disk wich is you are using right now e.g ( sda | vda ) without /dev/ : " SYSTEM_DISK

  echo -e "\n"

  if [ -z "${SYSTEM_DISK}" ]; then
    unset SYSTEM_DISK
    selectSystemDisk
    return
  fi

  checkIsThereAdisk=$(lsblk | grep -Po "^[a-z0-9]{3,}")
  thereIs=0
  for i in $checkIsThereAdisk; do
    if [ $i == "${SYSTEM_DISK}" ]; then
      thereIs=1
    fi
  done

  if [[ $thereIs -eq 0 ]]; then
    dividerLine "There is no such a disk like ${SYSTEM_DISK}"
    unset SYSTEM_DISK
    sleep 2
    selectSystemDisk
    return
  fi

  innerSeperator "\n $(lsblk /dev/"${SYSTEM_DISK}")\n"
  read -r -p "System disk is  - /dev/${SYSTEM_DISK} - [ Enter / N ] : " systemDiskConfirm

  if [ "${systemDiskConfirm}" == "N" ] || [ "${systemDiskConfirm}" == "n" ]; then
    unset SYSTEM_DISK
    unset systemDiskConfirm
    selectSystemDisk
    return
  fi

  #  dividerLine "Disks Except System Disk"
  disksExceptSystemDisk=$(lsblk | grep -v "${SYSTEM_DISK}" | grep -Po '^[a-z]+')
  DISK_COUNT=0

  #  innerSeperator "Disk Name\tDisk by-path\t\t\tDisk by-id"
  DISKS_EXCEPT_SYSTEM_DISK=()
  DISKS_EXCEPT_SYSTEM_DISK_BY_PATH=()
  DISKS_EXCEPT_SYSTEM_DISK_BY_ID=()

  for i in ${disksExceptSystemDisk}; do
    diskBypath=$(ls -l /dev/disk/by-path/ | grep -v "part[0-9]*" | grep -P "$i" | awk '{print $9}')
    diskById=$(ls -l /dev/disk/by-id/ | grep -v "part[0-9]*" | grep -P "$i" | awk '{print $9}')
    DISKS_EXCEPT_SYSTEM_DISK+=("$i")
    DISKS_EXCEPT_SYSTEM_DISK_BY_PATH+=("${diskBypath}")
    DISKS_EXCEPT_SYSTEM_DISK_BY_ID+=("${diskById}")
    #    echo -e " $DISK_COUNT : $i\t${diskBypath}\t${diskById}"
    DISK_COUNT=$((DISK_COUNT + 1))
  done
  innerSeperator "Total : ( $DISK_COUNT ) disks except System Disk (${SYSTEM_DISK})"

  export SYSTEM_DISK
  export DISK_COUNT
  export DISKS_EXCEPT_SYSTEM_DISK
  export DISKS_EXCEPT_SYSTEM_DISK_BY_ID
  export DISKS_EXCEPT_SYSTEM_DISK_BY_PATH

  stepByStep "selectSystemDisk"
}

function selectRaidType() {
  dividerLine "Raid Type Selection"
  length=${#RAID_TYPES[@]}
  innerSeperator "Select the RAID Type\n\t[ n = (0,1,2,...inf) ]\n\t[ X = (1,2,3,...inf) ] :"
  count=0
  for i in "${RAID_TYPES[@]}"; do
    echo -e $count" : $i [ ${RAID_EXPL[$count]} ]\n"
    count=$((count + 1))
  done

  read -r -p "Select One [ 0 ] : " selectedRaid
  if [ -z "${selectedRaid}" ]; then
    selectedRaid=0
  fi

  if [[ $selectedRaid -ge 0 ]] && [[ $selectedRaid -le $((length - 1)) ]]; then
    echo -e "\n"
    read -r -p "${RAID_TYPES[$selectedRaid]} is this true ? [ Y / n] : " selectedRaidConfirm
    if [ -z "${selectedRaidConfirm}" ]; then
      selectedRaidConfirm="Y"
    fi

    if [ ! -z "${selectedRaidConfirm}" ] && [ "${selectedRaidConfirm}" == "Y" ] || [ "${selectedRaidConfirm}" == "y" ]; then
      #      dividerLine "Selected Raid Configuration is \n\
      #      \n\t${RAID_TYPES[$selectedRaid]}\
      #      \n\n\tYou need at least ${RAID_EXPL[$selectedRaid]} disks!\n"
      export SELECTED_RAID_CONF="${RAID_TYPES[$selectedRaid]}"
      export selectedRaid
    else
      innerSeperator "Select between 0 and $((length - 1))"
      unset count
      unset selectedRaid
      unset SELECTED_RAID_CONF
      selectRaidType
      return
    fi
  else
    innerSeperator "Select between 0 and $((length - 1))"
    unset count
    unset selectedRaid
    unset SELECTED_RAID_CONF
    selectRaidType
    return
  fi

  if [[ $DISK_COUNT -lt ${RAID_MINIMUM_DISKS[$selectedRaid]} ]]; then
    dividerLine "Your disk count ( $DISK_COUNT ) is not supported ${SELECTED_RAID_CONF} setup ! at least ( ${RAID_MINIMUM_DISKS[$selectedRaid]} ) disks!"
    sleep 3
    unset count
    unset selectedRaid
    unset SELECTED_RAID_CONF
    selectRaidType
    return
  fi

  stepByStep "selectRaidType"
}

function selectInstallationDisks() {
  dividerLine "Installation Disks Selection"

  innerSeperator "\nYour raid type is ${SELECTED_RAID_CONF}\n\n
Minimum Disks : ${RAID_MINIMUM_DISKS[$selectedRaid]}\n
Maximum Disks : ${RAID_EXPL[$selectedRaid]}\n
You Have : $DISK_COUNT disks !\n"

  dividerLine "\n
For Example Your Raid Type is [raidz1 + stripe] (RAID-50)
You need at least 4 disks for this setup, the equation is :  (2+n)*X

n = stands by disk count those append (default 0)
X = stands by Array count (default 2)

e.g You have 9 disks, for this setup, you can use :
----------
n = 1 & X = 3
(2+1)*3 = 9 Disks
----------
n = 0 & X = 2
(2+0)*2 = 4 Disks
----------
n = 2 & X = 2
(2+2)*2 = 8 Disks
----------
\n"

  canAppendable=$((DISK_COUNT - ${RAID_MINIMUM_DISKS[$selectedRaid]}))
  dividerLine "Appendable disk count is : $canAppendable (array ignored)"

  # check appendable disks if exists
  if [[ $canAppendable -ge 0 ]]; then
    case $selectedRaid in
    # first disk is bootable except mirror (both)
    0 | 1 | 2 | 3 | 4) # stripe | mirror | raidz1 | raidz2 | raidz3
      read -r -p "    Add disk(s) to the conf | n = [ 0 - $canAppendable ] : " n
      if [ -z $n ]; then
        n=0
      fi

      if [[ $n -gt $canAppendable ]]; then
        dividerLine "Disk count can't be greater then $canAppendable"
        sleep 3
        selectInstallationDisks
        return
      fi

      x=1
      minimalDiskCountforSetup=${RAID_MINIMUM_DISKS[$selectedRaid]}

      ;;
    # first array's all disks are bootable
    5 | 6 | 7 | 8) # mirror + stripe | raidz1 + stripe | raidz2 + stripe | raidz3 + stripe
      canAppendableForSetup=$((canAppendable / 2))
      read -r -p "Add disk(s) to the array | n = [ 0 - $canAppendableForSetup ] : " n
      if [ -z $n ]; then n=0; fi
      if [[ $n -gt $canAppendableForSetup ]]; then
        dividerLine "Disk count can't be greater then $canAppendableForSetup"
        sleep 3
        selectInstallationDisks
        return
      fi

      minimalDiskCountforSetup=$((${RAID_MINIMUM_DISKS[$selectedRaid]} / 2))
      canCreateMinimalArray=$(((minimalDiskCountforSetup + n) * 2))
      if [[ $canCreateMinimalArray -gt $DISK_COUNT ]]; then
        dividerLine "Can't create a minimal Array Using $canCreateMinimalArray disks for this setup"
        sleep 3
        selectInstallationDisks
        return
      fi

      howManyArrayCanCreate=$((DISK_COUNT / $((minimalDiskCountforSetup + n))))

      read -r -p "Add array(s) to the conf | X = [ 2 - $howManyArrayCanCreate ] : " x
      if [ -z $x ]; then
        x=2
      fi

      if [[ $x -lt 2 ]]; then
        dividerLine "Can't create an Array less then 2 selecting 2"
        sleep 3
        x=2
      fi

      if [[ $x -gt $howManyArrayCanCreate ]]; then
        dividerLine "Can't create an Array greater then ($howManyArrayCanCreate)"
        sleep 3
        selectInstallationDisks
        return
      fi

      canCreateSettedupArray=$(((minimalDiskCountforSetup + n) * x))
      if [[ $canCreateSettedupArray -gt $DISK_COUNT ]]; then
        dividerLine "Can't create an Array greater then the disk count ($DISK_COUNT)"
        sleep 3
        selectInstallationDisks
        return
      fi
    ;;
    *) # return
      clear
      selectInstallationDisks
      return
    ;;
    esac
  fi

  settedupDiskCount=$(((minimalDiskCountforSetup + n) * x))

  count=0
  setupMessage="Your Pool Setup Is :\n\n\tzpool create poolName \n"
  for a in $(seq 1 $x); do
    setupMessage+="\t\t\t${RAID_TAGS[$selectedRaid]}\t"
    for d in $(seq 0 $((settedupDiskCount / x - 1))); do
      setupMessage+="<disk$count> "
      count=$((count + 1))
    done
    setupMessage+="\n"
  done
  dividerLine "${setupMessage}"

  read -r -p "Is This Setup Acceptable ? [ Y / n ] : " diskSetupConfirm
  case $diskSetupConfirm in
  "" | "Y" | "y") ;;

  "N" | "n")
    selectInstallationDisks
    return
    ;;
  *)
    selectInstallationDisks
    return
    ;;
  esac

  clear
  dividerLine "INSTALLATION DISK SELECTION

Selected disks will be wiped and partitioned after this selection!

After partitioning we'll use the disk's PARTUUID info rather then block name (sdX), id name or parth name ...\n"

  innerSeperator "
Select Disks for the ${RAID_TAGS[$selectedRaid]} configuration,
boot pool and root pool will be automatically configured.

[ Enter to select first $settedupDiskCount disk(s) ]

or

e.g (sda sdb sdc sdd ...) input dev names with space,
(selected disks will be processed given order!)

-----

*** First disk's of the array has boot partition and boot pool,

*** mirror (raid1 or raid10) configuration is exception,
all disks of 1st array has boot partition and boot pool.
\n"

  innerSeperator "Disk By Dev Name"
  for i in $(seq 0 $((${#DISKS_EXCEPT_SYSTEM_DISK[@]} - 1))); do
    #    echo -e "$i : ${DISKS_EXCEPT_SYSTEM_DISK[$i]}\t${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[$i]}\t${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[$i]}"
    echo -e "$i : ${DISKS_EXCEPT_SYSTEM_DISK[$i]}\n"
  done

  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK[@]}"
  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[@]}"
  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[@]}"

  read -r -p "Select Installation Disks ($settedupDiskCount of them) [ Enter / input ] : " selectedDisks

  # first time, seperated. After partition part UUID
  BOOT_PARTED_DISKS=()
  POOL_PARTED_DISKS=()


  case ${selectedDisks} in
  "")
    SELECTED_DISKS=("${DISKS_EXCEPT_SYSTEM_DISK[@]}")
    ;;
  [a-z0-9]*)
    count=0
    for i in ${selectedDisks}; do
      SELECTED_DISKS+=("$i")
    done

    # sayı ve isimleri kontrol et...
    if [[ ${#SELECTED_DISKS[@]} -ne $settedupDiskCount ]]; then
      clear
      dividerLine "
You have to choose ($settedupDiskCount) piece of disk(s)
Raid Configuration is : ${RAID_TAGS[$selectedRaid]} configuration
Minimal disks \t : ($minimalDiskCountforSetup)
Appened disks \t : ($n)
Array count \t : ($x)
"
      sleep 3
      selectInstallationDisks
      return
    fi

    CONFIRM_SELECTED_DISKS=()
#    ERROR_SELECTED_DISKS=()
    for i in "${SELECTED_DISKS[@]}"; do
      for d in "${DISKS_EXCEPT_SYSTEM_DISK[@]}"; do
        if [ "$i" == "$d" ]; then
          CONFIRM_SELECTED_DISKS+=("$i")
        fi
      done
    done

#    if [[ "${#ERROR_SELECTED_DISKS[@]}" -gt 0 ]]; then
#      array_uniq=("$(printf "%s\n" "${ERROR_SELECTED_DISKS[@]}" | sort -u | tr '\n' ' ')")
#    fi

    if [[ "${#SELECTED_DISKS[@]}" != "${#CONFIRM_SELECTED_DISKS[@]}" ]]; then
      clear
      dividerLine "
There is a problem, we don't have some of these disks on the system !
Selected Disks \t: ${SELECTED_DISKS[*]}
Disks on System\t: ${DISKS_EXCEPT_SYSTEM_DISK[*]}
"
      unset CONFIRM_SELECTED_DISKS
      unset ERROR_SELECTED_DISKS
      unset array_uniq
      sleep 3
      selectInstallationDisks
      return
    fi

  ;;
  esac

  count=0
  for a in $(seq 1 $x); do
    for d in $(seq 0 $((settedupDiskCount / x - 1))); do

      if [[ $d -eq 0 ]] && [ "${RAID_TAGS[$selectedRaid]}" != "mirror" ]; then
        BOOT_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $d -gt 0 ]] && [ "${RAID_TAGS[$selectedRaid]}" != "mirror" ]; then
        POOL_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -eq 1 ]] && [ "${RAID_TAGS[$selectedRaid]}" == "mirror" ]; then
        BOOT_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -gt 1 ]] && [ "${RAID_TAGS[$selectedRaid]}" == "mirror" ]; then
        POOL_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      count=$((count + 1))
    done
  done

  # confirm setup
  innerSeperator "Boot parted disks are : \n\n\t${BOOT_PARTED_DISKS[*]}\n"
  innerSeperator "Stripe parted disks are : \n\n\t${POOL_PARTED_DISKS[*]}\n"

  echo -e "\n"
  read -r -p "Confirm Installation Disk Setup [ Enter / n ] : " installationDisksConfirm

  case "${installationDisksConfirm}" in
  "n" | "N")
    unset CONFIRM_SELECTED_DISKS
    unset ERROR_SELECTED_DISKS
    unset array_uniq
    selectInstallationDisks
    return
  ;;
  esac

  stepByStep "selectInstallationDisks"
}

function labelClear() {
  dividerLine "ZFS Label Clear If Exist on Selected Disks"

  for i in "${BOOT_PARTED_DISKS[@]}"; do
    for d in $(lsblk | grep -iPo "${i}[0-9]+"); do
      innerSeperator "ZFS Label Clear on /dev/$d"
      zpool labelclear -f "/dev/$d"
      echo -e "\n"
    done
  done

  for i in "${POOL_PARTED_DISKS[@]}"; do
    for d in $(lsblk | grep -iPo "${i}[0-9]+"); do
      innerSeperator "ZFS Label Clear on /dev/$d"
      zpool labelclear -f "/dev/$d"
      echo -e "\n"
    done
  done

  stepByStep "labelClear"
}

function wipeDisks() {
  dividerLine "Wipe Partitions and Filesystem on Selected Disks"

  for i in "${BOOT_PARTED_DISKS[@]}"; do
    innerSeperator "Wipe Filesystem on /dev/$i"
    wipefs -a "/dev/$i"
    innerSeperator "Clear Partitions on /dev/$i"
    sgdisk --zap-all "/dev/$i"
    echo -e "\n"
  done

  for i in "${POOL_PARTED_DISKS[@]}"; do
    innerSeperator "Wipe Filesystem on /dev/$i"
    wipefs -a "/dev/$i"
    innerSeperator "Clear Partitions on /dev/$i"
    sgdisk --zap-all "/dev/$i"
    echo -e "\n"
  done

  stepByStep "wipeDisks"
}

function createPartitions() {
  dividerLine "Create Partitions on Selected Disks"

  innerSeperator "BOOT DISKS ARE PARTITIONING"
  for i in "${BOOT_PARTED_DISKS[@]}"; do
    innerSeperator "UEFI Boot Partition on /dev/$i"
    sgdisk -n2:1M:+512M -t2:EF00 "/dev/$i" # boot UEFI sdX2
    sleep 0.5

    innerSeperator "Boot Pool Partition on /dev/$i"
    sgdisk -n3:0:+1G -t3:BF01 "/dev/$i" # boot pool sdX3
    sleep 0.5

    innerSeperator "Root Pool Partition on /dev/$i"
    sgdisk -n4:0:0 -t4:BF00 "/dev/$i" #root pool sdX4
    sleep 0.5

    innerSeperator "Read the partition changes, inform the system!"
    partprobe
    sleep 0.5

    echo -e "\n"
  done

  innerSeperator "STRIPE DISK PARTITIONING"
  for i in "${POOL_PARTED_DISKS[@]}"; do
    innerSeperator "Root Pool Partition on /dev/$i"
    sgdisk -n1:0:0 -t1:BF00 "/dev/$i" # root pool sdX1
    sleep 0.5

    innerSeperator "Read the partition changes, inform the system!"
    partprobe
    sleep 0.5

    echo -e "\n"
  done

  innerSeperator "Active Partitions are : "
  lsblk

  stepByStep "createPartitions"
}

function getPartUUIDofDisks() {
  dividerLine "Getting PARTUUID of Disks, it's never changes !"

  # /dev/sdX2 | part2
  BOOT_PARTITIONS=()
  BOOT_PARTITIONS_PARTUUID=()
  # /dev/sdX3 | part3
  BOOT_POOLS_PARTITIONS=()
  BOOT_POOLS_PARTITIONS_PARTUUID=()
  # /dev/sdX4 | part4
  ROOT_PARTITIONS=()
  ROOT_PARTITIONS_PARTUUID=()

  for i in "${BOOT_PARTED_DISKS[@]}"; do
    # Get Boot Partitions of disk
    BOOT_PARTITIONS+=("${i}2")
    partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}2")
    BOOT_PARTITIONS_PARTUUID+=("${partUuidvalue}")
    innerSeperator "PARTUUID of /dev/${i}2\t${partUuidvalue}"

    # Get Boot Pools of disk
    BOOT_POOLS_PARTITIONS+=("${i}3")
    partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}3")
    BOOT_POOLS_PARTITIONS_PARTUUID+=("${partUuidvalue}")
    innerSeperator "PARTUUID of /dev/${i}3\t${partUuidvalue}"

    # Get Root Pools of disk
    ROOT_PARTITIONS+=("${i}4")
    partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}4")
    ROOT_PARTITIONS_PARTUUID+=("${partUuidvalue}")
    innerSeperator "PARTUUID of /dev/${i}4\t${partUuidvalue}"
  done

  # /dev/sdX1 | part1 (full disk)
  POOL_PARTITIONS=()
  POOL_PARTITIONS_PARTUUID=()

  for i in "${POOL_PARTED_DISKS[@]}"; do
    # Get Pool Partitions of disk
    POOL_PARTITIONS+=("${i}1")
    partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}1")
    POOL_PARTITIONS_PARTUUID+=("${partUuidvalue}")
    innerSeperator "PARTUUID of /dev/${i}1\t${partUuidvalue}"
  done

  # sdX2
  export BOOT_PARTITIONS
  export BOOT_PARTITIONS_PARTUUID
  # sdX3
  export BOOT_POOLS_PARTITIONS
  export BOOT_POOLS_PARTITIONS_PARTUUID
  # sdX4
  export ROOT_PARTITIONS
  export ROOT_PARTITIONS_PARTUUID
  # sdX1
  export POOL_PARTITIONS
  export POOL_PARTITIONS_PARTUUID

  stepByStep "getPartUUIDofDisks"
}

function swapsOffline() {
  dividerLine "All swaps off!"
  swapoff --all
}

function checkMdadmArray() {
  dividerLine "Check mdadm raid configuration!"
  cat /proc/mdstat
  MDADM_CHECK=$(
    cat <<EOF
mdadm --stop /dev/md0							# If so, stop them (replace $()md0$() as required):
mdadm --zero-superblock --force ${DISK}			# For an array using the whole disk:
mdadm --zero-superblock --force ${DISK}-part2	# For an array using a partition:
EOF
  )
  echo -e "${MDADM_CHECK}"

  stepByStep "checkMdadmArray"
}

function selectPoolNames() {
  dividerLine "Set pool names"
  bPoolName="bpool"
  rPoolName="rpool"

  read -r -p "Default Boot pool name is - ${bPoolName} - if you want to change it, input the new name [a-z0-9] : " newBpoolName
  if [ ! -z "${newBpoolName}" ]; then
    unset bPoolName
    bPoolName="${newBpoolName}"
  fi

  read -r -p "Default Root pool name is - ${rPoolName} - if you want to change it, input the new name [a-z0-9] : " newRpoolName
  if [ ! -z "${newRpoolName}" ]; then
    unset rPoolName
    rPoolName="${newRpoolName}"
  fi

  export bPoolName
  export rPoolName
  innerSeperator "Boot Pool name is : ${bPoolName}\n\tRoot Pool name is : ${rPoolName}"
}

function setBpoolName() {
  read -r -p "Set new bpool name [a-z] : e.g [ bootpool ] " bPoolNameNew

  if [ -z "${bPoolNameNew}" ]; then
    bPoolNameNew="bootpool"
  fi

  read -r -p "New bpool name is ${bPoolNameNew} : [ Y / n ]" bPoolNameConfirm

  if [ -z "${bPoolNameConfirm}" ] || [ "${bPoolNameConfirm}" == "Y" ] || [ "${bPoolNameConfirm}" == "y" ]; then
    unset bPoolName
    bPoolName="${bPoolNameNew}"
    export bPoolName
  else
    setBpoolName
    return
  fi
}

function setRpoolName() {
  read -r -p "Set new rpool name [a-z] : e.g [ rootpool ] " rPoolNameNew

  if [ -z "${rPoolNameNew}" ]; then
    rPoolNameNew="rootpool"
  fi

  read -r -p "New rpool name is ${rPoolNameNew} : [ Y / n ]" rPoolNameConfirm

  if [ -z "${rPoolNameConfirm}" ] || [ "${rPoolNameConfirm}" == "Y" ] || [ "${rPoolNameConfirm}" == "y" ]; then
    unset rPoolName
    rPoolName="${rPoolNameNew}"
    export rPoolName
  else
    setRpoolName
    return
  fi
}

function checkSystemHaveZfsPool() {
  dividerLine "Check System ZFS Pools"
  innerSeperator "Default Pool Names : ${bPoolName} & ${rPoolName}"
  innerSeperator "Active : \n$(zpool list)"

  systemPools=$(zpool status 2>/dev/null | grep -iPo "pool: \K.*")

  if [ ! -z "${systemPools}" ]; then
    zpool status
    hasBpool=$(grep "${bPoolName}" <<<"${systemPools}")
    hasRpool=$(grep "${rPoolName}" <<<"${systemPools}")

    if [ ! -z "${hasBpool}" ]; then
      innerSeperator "Setting Boot Pool Name"
      setBpoolName
    fi

    if [ ! -z "${hasRpool}" ]; then
      innerSeperator "Setting Root Pool Name"
      setRpoolName
    fi
  fi
}

function createBootPool() {
#  BOOT_POOLS_PARTITIONS_PARTUUID

  dividerLine "Creating BOOT pool"

for i in "${BOOT_POOLS_PARTITIONS_PARTUUID[@]}"; do
  echo -e "$i"
done

echo "${BOOT_POOLS_PARTITIONS_PARTUUID[*]}"

exit

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
      "${bPoolName}" "${BOOT_POOLS_PARTITIONS_PARTUUID}"-part3

    innerSeperator "Listing ZFS Filesystem"
    zfs list -t filesystem
  else
    dividerLine "There must be an error! can't find : ${DISK}-part3"
    lsblk
    exit 1
  fi

  stepByStep "createBootPool"
}

selectSystemDisk
selectRaidType
selectInstallationDisks
labelClear
wipeDisks
createPartitions
labelClear  # if ZFS installed before on that partition, it's there, clean it again.
getPartUUIDofDisks
createBootPool

exit 0
function createRootPool() {
  dividerLine "Creating ROOT pool"

  if [ -L "${DISK}"-part4 ]; then
    zpool create -f \
      -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
      -O dnodesize=auto -O normalization=formD -O relatime=on \-O xattr=sa \
      -O mountpoint=/ -R /mnt "${rPoolName}" "${DISK}"-part4

    innerSeperator "Listing ZFS Filesystem"
    zfs list -t filesystem
  else
    dividerLine "There must be an error! can't find : ${DISK}-part4"
    lsblk
    exit 1
  fi

  stepByStep "createRootPool"
}

function createPoolsAndMounts() {
  dividerLine "Creating Mount Pools"

  innerSeperator "Creating ${rPoolName}/BOOT & ${bPoolName}/BOOT"
  zfs create -o canmount=off -o mountpoint=none ${rPoolName}/ROOT
  zfs create -o canmount=off -o mountpoint=none ${bPoolName}/BOOT

  innerSeperator "Creating and mounting root ( / ) filesystem"
  zfs create -o canmount=noauto -o mountpoint=/ ${rPoolName}/ROOT/debian
  zfs mount ${rPoolName}/ROOT/debian

  innerSeperator "Creating ${bPoolName}/BOOT/debian pool [ EFI system nesting directory]"
  zfs create -o mountpoint=/boot ${bPoolName}/BOOT/debian

  innerSeperator "Creating ${rPoolName}/home"
  zfs create ${rPoolName}/home
  innerSeperator "Creating and mounting ${rPoolName}/home/root to /root"
  zfs create -o mountpoint=/root ${rPoolName}/home/root
  chmod 700 /mnt/root
  innerSeperator "Creating ${rPoolName}/var"
  zfs create -o canmount=off ${rPoolName}/var
  innerSeperator "Creating ${rPoolName}/var/lib"
  zfs create -o canmount=off ${rPoolName}/var/lib
  innerSeperator "Creating ${rPoolName}/var/log"
  zfs create ${rPoolName}/var/log
  innerSeperator "Creating ${rPoolName}/var/mail"
  zfs create ${rPoolName}/var/mail
  innerSeperator "Creating ${rPoolName}/var/www"
  zfs create ${rPoolName}/var/www
  innerSeperator "Creating ${rPoolName}/var/spool"
  zfs create ${rPoolName}/var/spool
  innerSeperator "Creating ${rPoolName}/var/cache (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false ${rPoolName}/var/cache
  innerSeperator "Creating ${rPoolName}/var/tmp (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false ${rPoolName}/var/tmp
  innerSeperator "Setting sticky bit [ 1 ] for /mnt/var/tmp (only owner)"
  chmod 1777 /mnt/var/tmp
  innerSeperator "Creating ${rPoolName}/opt"
  zfs create ${rPoolName}/opt
  innerSeperator "Creating ${rPoolName}/usr"
  zfs create -o canmount=off ${rPoolName}/usr
  innerSeperator "Creating ${rPoolName}/usr/local"
  zfs create ${rPoolName}/usr/local
  innerSeperator "Creating ${rPoolName}/var/lib/docker (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false ${rPoolName}/var/lib/docker
  innerSeperator "Creating ${rPoolName}/var/lib/nfs (without auto snapshots)"
  zfs create -o com.sun:auto-snapshot=false ${rPoolName}/var/lib/nfs
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

function installBaseSystem() {
  dividerLine "Installing Debian bullseye base system !"
  debootstrap bullseye /mnt

  stepByStep "installBaseSystem"
}

function copyPoolCache() {
  dividerLine "Copy pool cache to base system"
  mkdir /mnt/etc/zfs
  cp /etc/zfs/zpool.cache /mnt/etc/zfs/

  stepByStep "copyPoolCache"
}

function changeHostNameBaseSystem() {
  dividerLine "Changing base system's hostname"
  read -r -p "What will be the name of your ZFS bullseye e.g. [ $(hostname)-zfs ? ] " newHostname
  if [ -z "${newHostname}" ]; then
    newHostname=$(hostname)-zfs
  fi

  sed '2 i 127.0.1.1\t'"${newHostname}" /etc/hosts >/mnt/etc/hosts

  stepByStep "changeHostNameBaseSystem"
}

function changeNetworkConfOfBaseSystem() {
  dividerLine "Changing base system's network configuration"
  CHANGE_NET_IF=$(
    cat <<EOF
auto eth0
iface eth0 inet dhcp
EOF
  )
  echo -e "${CHANGE_NET_IF}" >/mnt/etc/network/interfaces.d/eth0

  stepByStep "changeNetworkConfOfBaseSystem"
}

function addAptSourcesToBaseSystem() {
  dividerLine "Adding /etc/apt/sources.list to base system"
  aptSourcesHttp "mnt"

  stepByStep "addAptSourcesToBaseSystem"
}

function makePrivateDirectories() {
  mount --make-private --rbind /dev /mnt/dev
  mount --make-private --rbind /proc /mnt/proc
  mount --make-private --rbind /sys /mnt/sys

  stepByStep "makePrivateDirectories"
}

function chrootUpdate() {
  dividerLine "chroot and apt update the base system"
  chroot /mnt apt -qq update

  stepByStep "chrootUpdate"
}

function chrootUpgrade() {
  dividerLine "chroot and apt upgrade the base system"
  chroot /mnt apt -qq upgrade -y

  stepByStep "chrootUpgrade"
}

function chrootAutoremove() {
  dividerLine "chroot and apt autoremove the base system"
  chroot /mnt apt -qq autoremove -y

  stepByStep "chrootAutoremove"
}

function chrootInstallBaseApps() {
  dividerLine "Apt install chrooted system's applications"
  chroot /mnt apt -qq install -y sudo parted htop screen bash-completion apt-transport-https openssh-server \
    ca-certificates console-setup locales dosfstools grub-efi-amd64 shim-signed gdisk

  stepByStep "chrootInstallBaseApps"
}

function chrootSymlinkMounts() {
  dividerLine "Chroot Symlink Mounts"
  chroot /mnt ln -s /proc/self/mounts /etc/mtab

  stepByStep "chrootSymlinkMounts"
}

function chrootDpkgReconfigure() {
  dividerLine "Chroot DPKG reconfigure"
  chroot /mnt dpkg-reconfigure locales tzdata keyboard-configuration console-setup

  stepByStep "chrootDpkgReconfigure"
}

function chrootInstallKernelHeaders() {
  dividerLine "Chroot Install Kernel headers"
  chroot /mnt apt -qq install -y dpkg-dev linux-headers-amd64 linux-image-amd64
  chroot /mnt apt -qq install -y zfs-initramfs

  chroot /mnt echo REMAKE_INITRD=yes >/etc/dkms/zfs.conf

  stepByStep "chrootInstallKernelHeaders"
}

function chrootWriteUefiPart() {
  dividerLine "Chroot Write UEFI boot"

  innerSeperator "Grub Probe [ you should see 'zfs']"
  innerSeperator $(chroot /mnt grub-probe /boot)
  lsblk
  innerSeperator "mkdosfs EFI part"
  chroot /mnt /usr/bin/env DISK="${DISK}" mkdosfs -F 32 -s 1 -n EFI ${DISK}-part2
  innerSeperator "Create /boot/efi"
  chroot /mnt mkdir /boot/efi
  innerSeperator "Write /etc/fstab"
  #  chroot /mnt /usr/bin/env DISK="${DISK}" echo -e ${DISK}-part2" /boot/efi vfat defaults 0 0" >> /etc/fstab
  #bootEfiUuid=$(blkid -s UUID -o value ${DISK}-part2)
  bootEfiUuid=$(blkid -s PARTUUID -o value ${DISK}-part2)
  if [ ! -z "${bootEfiUuid}" ]; then
    innerSeperator "PARTUUID : ${bootEfiUuid}"
    echo -e "PARTUUID=\"${bootEfiUuid}\" /boot/efi vfat defaults 0 0" >>/mnt/etc/fstab
  else
    innerSeperator "DISK BY  ID : ${DISK}-part2"
    echo -e "${DISK}-part2 /boot/efi vfat defaults 0 0" >>/mnt/etc/fstab
  fi
  innerSeperator "Mount EFI"
  chroot /mnt mount /boot/efi
  innerSeperator "Purge os-prober [ Dual boot systems don't needed ]"
  chroot /mnt apt remove -y --purge os-prober

  stepByStep "chrootWriteUefiPart"
}

function chrootCreateRootPassword() {
  dividerLine "Chrooted System Change 'root' password"
  #  read -rs -p "Create root password : " chrootRootPassword
  chroot /mnt passwd

  stepByStep "chrootCreateRootPassword"
}

function chrootImportBpoolService() {
  dividerLine "Chroot Create and enable Bpool service"
  export BPOOL_SERVICE=$(
    cat <<EOF
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none ${bPoolName}
# Work-around to preserve zpool cache:
ExecStartPre=-/bin/mv /etc/zfs/zpool.cache /etc/zfs/preboot_zpool.cache
ExecStartPost=-/bin/mv /etc/zfs/preboot_zpool.cache /etc/zfs/zpool.cache

[Install]
WantedBy=zfs-import.target
EOF
  )

  innerSeperator "Write service file"
  echo -e "${BPOOL_SERVICE}" >/mnt/etc/systemd/system/zfs-import-${bPoolName}.service
  innerSeperator "Enable service"
  chroot /mnt /usr/bin/env bPoolName=${bPoolName} systemctl enable zfs-import-${bPoolName}.service
  innerSeperator "Enable tmp.mount service"
  chroot /mnt cp /usr/share/systemd/tmp.mount /etc/systemd/system/
  chroot /mnt systemctl enable tmp.mount

  stepByStep "chrootImportBpoolService"
}

function chrootUpdateInitRamFs() {
  dividerLine "Chroot Update Init Ram Filesystem"
  chroot /mnt update-initramfs -c -k all

  stepByStep "chrootUpdateInitRamFs"
}

function chrootChangeGrubDefaults() {
  dividerLine "Chroot set /etc/default/grub file"
  chroot /mnt sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/g' /etc/default/grub
  chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="console"/g' /etc/default/grub
  chroot /mnt /usr/bin/env rPoolName=${rPoolName} sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="root=ZFS='${rPoolName}'\/ROOT\/debian net.ifnames=0 biosdevname=0"/g' /etc/default/grub
  chroot /mnt update-grub

  stepByStep "chrootChangeGrubDefaults"
}

function chrootGrubInstall() {
  dividerLine "Chroot grub install"
  chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-floppy

  stepByStep "chrootGrubInstall"
}

function chrootZfsListCaches() {
  dividerLine "Chroot ZFS list caches"
  chroot /mnt mkdir /etc/zfs/zfs-list.cache
  chroot /mnt /usr/bin/env bPoolName=${bPoolName} touch /etc/zfs/zfs-list.cache/${bPoolName}
  chroot /mnt /usr/bin/env rPoolName=${rPoolName} touch /etc/zfs/zfs-list.cache/${rPoolName}
  chroot /mnt ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
  chroot /mnt zed -F &
  innerSeperator "When you see changes on the screen [ Ctrl + C ]"
  sleep 3
  chroot /mnt /usr/bin/env bPoolName=${bPoolName} watch -n1 cat /etc/zfs/zfs-list.cache/${bPoolName}
  innerSeperator "When you see changes on the screen [ Ctrl + C ]"
  sleep 3
  chroot /mnt /usr/bin/env rPoolName=${rPoolName} watch -n1 cat /etc/zfs/zfs-list.cache/${rPoolName}
  innerSeperator "Chroot get the zed application and exit [ Ctrl + C ]"
  chroot /mnt pkill -15 zed

  stepByStep "chrootZfsListCaches"
}

function chrootChangeMntDir() {
  dividerLine "Chroot change '/mnt/' to '/' root file system"
  sed -Ei "s|/mnt/?|/|" /mnt/etc/zfs/zfs-list.cache/*

  stepByStep "chrootChangeMntDir"
}

function afterReboot() {
  dividerLine "After the reboot you might want to start 'after-reboot.sh':"
  AFTER_REBOOT_SH=$(
    cat <<EOF
#!/usr/bin/env bash

function dividerLine() {
  echo -e "\\\n######################################################################"
  echo -e "#    \$1"
  echo -e "######################################################################\\\n"
}

function innerSeperator() {
  echo -e "----------------------------------------------------------------------"
  echo -e "    \$1"
  echo -e "----------------------------------------------------------------------"
}

function getUserPassword() {
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

function addNewUserToBaseSystem() {
  dividerLine "Add New User to System"
  read -r -p "Username : [ Username / N (continue without) ] " username

  if [ -z "\${username}" ]; then
    echo -e "You should give a username or 'N' to continue without one!"
    addNewUserToBaseSystem
  fi

  if [ ! "\${username}" == "n" ] || [ ! "\${username}" == "N" ]; then
    innerSeperator "The username is : \${username}"
    innerSeperator "ZFS Create \${username} 's pool"
    zfs create ${rPoolName}/home/\${username}
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

function startTaskSel() {
  dividerLine "TASKSEL"
  tasksel
}

addNewUserToBaseSystem
startTaskSel

EOF
  )
  innerSeperator "/root/after-reboot.sh script generated."
  echo -e "${AFTER_REBOOT_SH}" >/mnt/root/after-reboot.sh
  #  echo -e "${AFTER_REBOOT_SH}" > "$(pwd)"/after-reboot.sh
  chmod 700 /mnt/root/after-reboot.sh
  #  chmod 700 "$(pwd)"/after-reboot.sh

  stepByStep "afterReboot"
}

function chrootTakeInitialSnapshots() {
  dividerLine "Chroot take initial snapshots"
  chroot /mnt /usr/bin/env bPoolName=${bPoolName} zfs snapshot ${bPoolName}/BOOT/debian@initial
  chroot /mnt /usr/bin/env rPoolName=${rPoolName} zfs snapshot ${rPoolName}/ROOT/debian@initial

  stepByStep "chrootTakeInitialSnapshots"
}

function unmountAllFilesystems() {
  dividerLine "Unmount all ZFS /mnt partitions"
  mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} # LiveCD environment to unmount all filesystems

  stepByStep "unmountAllFilesystems"
}

function exportZfsPools() {
  dividerLine "Export ZFS Pools"
  zpool export -f "${bPoolName}"
  zpool export -f "${rPoolName}"

  stepByStep "exportZfsPools"
}

function rebootSystem() {
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

selectSystemDisk
selectRaidType
selectInstallationDisks
labelClear
wipeDisks
createPartitions
labelClear  # if ZFS installed before on that partition same name, it's there, clear it again.
getPartUUIDofDisks

swapsOffline
checkMdadmArray
selectPoolNames
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
