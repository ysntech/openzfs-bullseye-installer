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

function getPath {
	FULL="$1"
	F_PATH=${FULL%/*}
	F_BASE=${FULL##*/}
	F_NAME=${F_BASE%.*}
	F_EXT=${F_BASE##*.}
#	echo $F_PATH
#	echo $F_BASE
#	echo $F_NAME
#	echo $F_EXT
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
  dividerLine "APT Sources HTTP"
  if [ ! -z $1 ]; then
    echo -e "${APT_SOURCES_HTTP}" >/mnt/etc/apt/sources.list
  else
    echo -e "${APT_SOURCES_HTTP}" >/etc/apt/sources.list
  fi

  stepByStep "aptSourcesHttp"
}

function aptSourcesHttps() {
  dividerLine "APT Sources HTTPS"
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
  isAliveSystem=$(lsblk | grep -Po "^loop[0-9]+")
  if [ -z "${isAliveSystem}" ]; then
    apt -qq upgrade -y
    apt -qq autoremove -y
  fi
  stepByStep "aptUpdateUpgrade"
}

function installBaseApps() {
  dividerLine "System ZFS Build Applications Installation"
  apt -qqq update -y
  apt -qq install -y bash-completion debootstrap dpkg-dev dkms gdisk parted mdadm ovmf
  apt -qq install -y zfsutils-linux
  modprobe zfs

  stepByStep "installBaseApps"
}

function selectSystemDisk() {
  dividerLine "Selecting System Disk"
  lsblk | grep -v -P "sr[0-9]+"
  echo -e "\n"
  read -r -p "Select the system disk wich is you are using right now e.g ( sda | vda | nvme ) without /dev/ : " SYSTEM_DISK

  echo -e "\n"

  if [ -z "${SYSTEM_DISK}" ]; then
    unset SYSTEM_DISK
    selectSystemDisk
    return
  fi

  checkIsThereAdisk=$(lsblk | grep -v -P "sr[0-9]+" | grep -Po "^[a-z0-9]{3,}")
  thereIs=0
  for i in $checkIsThereAdisk; do
    if [ $i == "${SYSTEM_DISK}" ]; then
      thereIs=1
    fi
  done

  if [[ $thereIs -eq 0 ]]; then
    dividerLine "There is no such a disk like ${SYSTEM_DISK}"
    unset SYSTEM_DISK
    sleep 3
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
  disksExceptSystemDisk=$(lsblk | grep -v -P "sr[0-9]+" | grep -v "loop*" | grep -v "${SYSTEM_DISK}" | grep -Po '^[a-z0-9]+')

  DISKS_EXCEPT_SYSTEM_DISK=()
  DISKS_EXCEPT_SYSTEM_DISK_BY_ID=()
  DISKS_EXCEPT_SYSTEM_DISK_BY_PATH=()

#  innerSeperator "Disk Name\tDisk by-path\t\t\tDisk by-id"
  DISK_COUNT=0
  for i in ${disksExceptSystemDisk}; do
#    diskById=$(ls -l /dev/disk/by-id/ | grep -v "part[0-9]*" | grep -P "$i" | awk '{print $9}')
    diskByPath=$(ls -l /dev/disk/by-path/ | grep -v "part[0-9]*" | grep -P "$i" | awk '{print $9}' | head -n 1)
#    DISKS_EXCEPT_SYSTEM_DISK_BY_ID+=("${diskById}")
    DISKS_EXCEPT_SYSTEM_DISK_BY_PATH+=("${diskByPath}")
#    echo -e " $DISK_COUNT : $i\t${diskBypath}\t${diskById}\n"
    DISK_COUNT=$((DISK_COUNT + 1))
  done
  innerSeperator "Total : ( $DISK_COUNT ) disks except System Disk (${SYSTEM_DISK})"

#  IFS=$'\n' sorted=($(sort <<<"${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[*]}"))
#  unset IFS
#  DISKS_EXCEPT_SYSTEM_DISK_BY_ID=("${sorted[@]}")

  IFS=$'\n' sorted=($(sort <<<"${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[*]}"))
  unset IFS
  DISKS_EXCEPT_SYSTEM_DISK_BY_PATH=("${sorted[@]}")

#  for i in "${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[@]}"; do
#    DISKS_EXCEPT_SYSTEM_DISK+=($(ls -l /dev/disk/by-id/$i | grep -iPo "[a-z]{3,}$"))
#  done

  for i in "${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[@]}"; do
#    echo -e $(ls -l /dev/disk/by-path/$i | grep -iPo "[a-z]{3,}$|[n]vme[0-9][a-z][0-9]$")
    DISKS_EXCEPT_SYSTEM_DISK+=($(ls -l /dev/disk/by-path/$i | grep -iPo "[a-z]{3,}$|[n]vme[0-9][a-z][0-9]$"))
  done

#echo -e "${DISKS_EXCEPT_SYSTEM_DISK[*]} \n"
#echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[*]} \n"
#echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[*]} \n"

  export SYSTEM_DISK
  export DISK_COUNT
  export DISKS_EXCEPT_SYSTEM_DISK
#  export DISKS_EXCEPT_SYSTEM_DISK_BY_ID
  export DISKS_EXCEPT_SYSTEM_DISK_BY_PATH

  innerSeperator "Disk Name\t\tDisk by-path"
  cnt=0
  for i in "${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[@]}"; do
    echo -e "$cnt : ${DISKS_EXCEPT_SYSTEM_DISK[$cnt]}\t\t\t${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[$cnt]}"
    cnt=$((cnt+1))
  done

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

*** All disks of 1st array has boot partition and boot pool.

*** striped (raid0 and all striped) configurations is exception,
First disk of the array has boot partition and boot pool,
\n"

  innerSeperator "Disk By Dev Name"
  for i in $(seq 0 $((${#DISKS_EXCEPT_SYSTEM_DISK[@]} - 1))); do
#    echo -e "$i : ${DISKS_EXCEPT_SYSTEM_DISK[$i]}\t\t${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[$i]}\n"
    echo -e "$i : ${DISKS_EXCEPT_SYSTEM_DISK[$i]}\t\t${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[$i]}\n"
  done

  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK[@]}"
  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_ID[@]}"
  #  echo -e "${DISKS_EXCEPT_SYSTEM_DISK_BY_PATH[@]}"

  read -r -p "Select Installation Disks ($settedupDiskCount of them, use sdX names) [ Enter / input ] : " selectedDisks

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

      if [[ $a -eq 1 ]] && [ "${RAID_TAGS[$selectedRaid]}" != "" ]; then
        BOOT_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -gt 1 ]] && [ "${RAID_TAGS[$selectedRaid]}" != "" ]; then
        POOL_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -eq 1 ]] && [[ $d -eq 0 ]] && [ "${RAID_TAGS[$selectedRaid]}" == "" ]; then
        BOOT_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -eq 1 ]] && [[ $d -gt 0 ]] && [ "${RAID_TAGS[$selectedRaid]}" == "" ]; then
        POOL_PARTED_DISKS+=("${SELECTED_DISKS[$count]}")
      fi

      if [[ $a -gt 1 ]] && [[ $d -gt 0 ]] && [ "${RAID_TAGS[$selectedRaid]}" == "" ]; then
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

  ARRAY_COUNT=$x
  export ARRAY_COUNT
  export BOOT_PARTED_DISKS
  stepByStep "selectInstallationDisks"
}

function labelClear() {
  dividerLine "ZFS Label Clear If Exist on Selected Disks"

  for i in "${BOOT_PARTED_DISKS[@]}"; do
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      diskType="${i}p[0-9]+"
    else
      diskType="${i}[0-9]+"
    fi
    for d in $(lsblk | grep -v -P "sr[0-9]+" | grep -iPo "${diskType}"); do
      innerSeperator "ZFS Label Clear on /dev/$d"
      zpool labelclear -f "/dev/$d"
      echo -e "\n"
    done
  done

  for i in "${POOL_PARTED_DISKS[@]}"; do
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      diskType="${i}p[0-9]+"
    else
      diskType="${i}[0-9]+"
    fi
    for d in $(lsblk | grep -v -P "sr[0-9]+" | grep -iPo "${diskType}"); do
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
    sgdisk -n1:0:0 -t1:BF00 "/dev/$i" # root pool sdX1|nvme0n1
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
#    nvme disks implementation
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      BOOT_PARTITIONS+=("/dev/${i}p2")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}p2")
      innerSeperator "PARTUUID of /dev/${i}p2\t${partUuidvalue}"
    else
      BOOT_PARTITIONS+=("/dev/${i}2")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}2")
      innerSeperator "PARTUUID of /dev/${i}2\t${partUuidvalue}"
    fi
    BOOT_PARTITIONS_PARTUUID+=("${partUuidvalue}")

    # Get Boot Pools of disk
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      BOOT_POOLS_PARTITIONS+=("/dev/${i}p3")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}p3")
      innerSeperator "PARTUUID of /dev/${i}p3\t${partUuidvalue}"
    else
      BOOT_POOLS_PARTITIONS+=("/dev/${i}3")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}3")
      innerSeperator "PARTUUID of /dev/${i}3\t${partUuidvalue}"
    fi
    BOOT_POOLS_PARTITIONS_PARTUUID+=("${partUuidvalue}")

    # Get Root Pools of disk
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      ROOT_PARTITIONS+=("/dev/${i}p4")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}p4")
      innerSeperator "PARTUUID of /dev/${i}p4\t${partUuidvalue}"
    else
      ROOT_PARTITIONS+=("/dev/${i}4")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}4")
      innerSeperator "PARTUUID of /dev/${i}4\t${partUuidvalue}"
    fi
    ROOT_PARTITIONS_PARTUUID+=("${partUuidvalue}")
  done

  # /dev/sdX1 | part1 (full disk)
  POOL_PARTITIONS=()
  POOL_PARTITIONS_PARTUUID=()

  for i in "${POOL_PARTED_DISKS[@]}"; do
    # Get Pool Partitions of disk
    if [ ! -z $(grep "nvme[0-9][a-z][0-9]" <<< $i) ]; then
      POOL_PARTITIONS+=("/dev/${i}p1")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}p1")
      innerSeperator "PARTUUID of /dev/${i}p1\t${partUuidvalue}"
    else
      POOL_PARTITIONS+=("/dev/${i}1")
      partUuidvalue=$(blkid -s PARTUUID -o value "/dev/${i}1")
      innerSeperator "PARTUUID of /dev/${i}1\t${partUuidvalue}"
    fi
    POOL_PARTITIONS_PARTUUID+=("${partUuidvalue}")
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

function cloneableUefiPart() {

  BOOT_DISK_PARTUUID="/dev/disk/by-partuuid/${BOOT_PARTITIONS_PARTUUID[0]}"
  BOOT_CLONES=()

  count=$((${#BOOT_PARTITIONS_PARTUUID[@]} - 1))
  for i in $(seq 1 $count); do
    BOOT_CLONES+=("/dev/disk/by-partuuid/${BOOT_PARTITIONS_PARTUUID[$i]}")
  done

  export BOOT_DISK_PARTUUID
  export BOOT_CLONES
}

function cloneUefiPartFunctionBuilder() {
  if [[ "${#BOOT_CLONES[@]}" -gt 0 ]]; then
    CLONE_FUNCTION=$(cat <<EOF

function cloneUefiPart() {
  dividerLine "Clone UEFI Partition"

  umount /boot/efi
  count=2
  PARTITIONS=(${BOOT_CLONES[@]})
  for i in \${PARTITIONS[@]}; do
    dd if=${BOOT_DISK_PARTUUID} of=\$i status=progress
    sync
    sleep 0.5
    disk=\$(ls -l \$i | grep -iPo "[a-z]+[0-9]+$" | grep -Po "[a-z]+")
    diskById=\$(ls -l /dev/disk/by-id/ | grep -P "\$disk$" | awk '{print \$9}')
    efibootmgr -c -g -d /dev/\$disk -p 2 -L "debian-\$count" -l '\\\EFI\debian\grubx64.efi'
    sleep 0.5
    count=\$((count + 1))
  done
  mount /boot/efi
}

EOF
)
  else
    CLONE_FUNCTION=""
  fi

  export CLONE_FUNCTION
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
mdadm --zero-superblock --force /dev/sdX			# For an array using the whole disk:
mdadm --zero-superblock --force /dev/sdX2     # For an array using a partition:
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
  innerSeperator "
Boot Pool name is : ${bPoolName}
Root Pool name is : ${rPoolName}
"

  stepByStep "selectPoolNames"
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

  stepByStep "checkSystemHaveZfsPool"
}

function createBootPool() {
#  BOOT_POOLS_PARTITIONS_PARTUUID

  settedupDiskCount=${#BOOT_POOLS_PARTITIONS_PARTUUID[@]}

  count=0
  setupString="${bPoolName} ${RAID_TAGS[$selectedRaid]} "
  for d in $(seq 0 $settedupDiskCount ); do
    setupString+="${BOOT_POOLS_PARTITIONS_PARTUUID[$count]} "
    count=$((count + 1))
  done

  dividerLine "Creating BOOT pool"
  innerSeperator "${setupString}"

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
    ${setupString}

  innerSeperator "Listing ZFS Filesystem"
  zfs list -t filesystem

  stepByStep "createBootPool"
}

function createRootPool() {

  mergedArray=("${ROOT_PARTITIONS_PARTUUID[@]}")
  mergedArray+=("${POOL_PARTITIONS_PARTUUID[@]}")
  settedupDiskCount="${#mergedArray[@]}"

  count=0
  setupString="${rPoolName} "
  for a in $(seq 1 $ARRAY_COUNT); do
    setupString+="${RAID_TAGS[$selectedRaid]} "
    for d in $(seq 0 $((settedupDiskCount / ARRAY_COUNT - 1))); do
      setupString+="${mergedArray[$count]} "
      count=$((count + 1))
    done
  done

  dividerLine "Creating ROOT pool"
  innerSeperator "${setupString}"

  zpool create -f \
    -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \-O xattr=sa \
    -O mountpoint=/ -R /mnt \
    ${setupString}

  innerSeperator "Listing ZFS Filesystem"
  zfs list -t filesystem

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

  stepByStep "createPoolsAndMounts"
}

function askAndCreateDataset() {

#  echo -e "${DATASET_DIRS[@]}"
#  echo -e "${DATASET_OPTS[@]}"

  if [[ ${#DATASET_DIRS[@]} -gt 0 ]]; then

    count=0
    echo -e "----------------------------------------------------------"
    for i in "${DATASET_DIRS[@]}"; do
      read -r -p "Create ZFS Dataset ( ${rPoolName}$i ) ? [ Y / n ] " zfsDataset
        case $zfsDataset in
        "" | "Y" | "y")
            echo -e "zfs create ${DATASET_OPTS[$count]} ${rPoolName}$i"
            zfs create ${DATASET_OPTS[$count]} ${rPoolName}$i
          ;;
        "N" | "n")
          if [[ $count -eq 0 ]]; then
            return
          fi
          ;;
        *)
#          selectInstallationDisks
          return
          ;;
        esac
      count=$((count+1))
      echo -e "----------------------------------------------------------"
    done
  fi
  unset DATASET_DIRS
  unset DATASET_OPTS
}

function createOtherDatasets() {
  dividerLine "Creating Other ZFS Datasets"

  DATASET_DIRS=("/var" \
  "/var/lib" \
  "/var/log"  \
  "/var/mail"  \
  "/var/vmail"  \
  "/var/www"  \
  "/var/spool"  \
  "/var/cache"  \
  "/var/tmp"  \
  "/var/opt")

  DATASET_OPTS=("-o canmount=off -o mountpoint=none"  \
  "-o canmount=off"  \
  ""  \
  ""  \
  ""  \
  "" \
  ""  \
  "-o com.sun:auto-snapshot=false"  \
  "-o com.sun:auto-snapshot=false"  \
  "")
  export DATASET_DIRS
  export DATASET_OPTS
  askAndCreateDataset

  getPath "/var/lib/docker"
  upperDir=$(zfs list | grep "${F_PATH}")
  echo "$upperDir"
  if [ ! -z "$upperDir" ]; then
    DATASET_DIRS=("/var/lib/docker" \
    "/var/lib/nfs")
    DATASET_OPTS=("-o com.sun:auto-snapshot=false" \
    "-o com.sun:auto-snapshot=false")
    export DATASET_DIRS
    export DATASET_OPTS
    askAndCreateDataset
  fi

  DATASET_DIRS=("/opt")
  DATASET_OPTS=("")
  export DATASET_DIRS
  export DATASET_OPTS
  askAndCreateDataset

  DATASET_DIRS=("/usr" \
  "/usr/local")
  DATASET_OPTS=("-o canmount=off" \
  "")
  export DATASET_DIRS
  export DATASET_OPTS
  askAndCreateDataset

  innerSeperator "Creating /mnt/run"
  mkdir /mnt/run
  innerSeperator "Mounting /mnt/run using tmp filesystem"
  mount -t tmpfs tmpfs /mnt/run
  innerSeperator "Creating /mnt/run/lock"
  mkdir /mnt/run/lock

  innerSeperator "Listing ZFS Filesystem"
  zfs list -t filesystem

  stepByStep "createOtherDatasets"
}

function installBaseSystem() {
  dividerLine "Installing Debian bullseye base system !"
  sleep 2
  if [ -f "/root/debootstrap/bullseye.tar.gz" ]; then
    tar -xvzf /root/debootstrap/bullseye.tar.gz -C /mnt/
  elif [ -f "/root/debootstrap/bullseye_clean.tar.gz" ]; then
	tar -xvzf /root/debootstrap/bullseye_clean.tar.gz -C /mnt/
  else
    debootstrap bullseye /mnt
  fi

  chmod 1777 /mnt/var/tmp
  stepByStep "installBaseSystem"
}

function copyPoolCache() {
  dividerLine "Copy pool cache to base system"
  if [ ! -d /mnt/etc/zfs ]; then
    mkdir /mnt/etc/zfs
  fi
  cp /etc/zfs/zpool.cache /mnt/etc/zfs/

  stepByStep "copyPoolCache"
}

function changeHostNameBaseSystem() {
  dividerLine "Changing base system's hostname"
  read -r -p "What will be the name of your ZFS bullseye e.g. [ $(hostname)-zfs ? ] " newHostname
  if [ -z "${newHostname}" ]; then
    newHostname=$(hostname)-zfs
  fi

  sed '2 i 127.0.1.1\t'"${newHostname}" /etc/hosts > /mnt/etc/hosts

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

  if [ ! -d /mnt/etc/network/interfaces.d/ ]; then
    mkdir /mnt/etc/network/interfaces.d/
  fi

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
  chroot /mnt apt -qq install -y sudo parted htop screen net-tools dnsutils whois curl wget bash-completion \
    apt-transport-https openssh-server ca-certificates console-setup locales dosfstools grub-efi-amd64 \
    shim-signed gdisk iproute2 mdadm ovmf lsof

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
  chroot /mnt apt -qq install -y dkms
  chroot /mnt apt -qq install -y zfs-initramfs

  chroot /mnt echo REMAKE_INITRD=yes >/etc/dkms/zfs.conf

  stepByStep "chrootInstallKernelHeaders"
}

function chrootWriteUefiPart() {
#BOOT_PARTED_DISKS
#BOOT_PARTITIONS
#BOOT_PARTITIONS_PARTUUID

  dividerLine "Chroot Write UEFI boot"

  innerSeperator "Grub Probe [ you should see 'zfs']"
  innerSeperator $(chroot /mnt grub-probe /boot)
  read -p " [ Enter ] " keypress

  lsblk
  innerSeperator "mkdosfs EFI part"
  partUuid=${BOOT_PARTITIONS_PARTUUID[0]}
  export partUuid
  chroot /mnt /bin/bash -c 'echo "/dev/disk/by-partuuid/$partUuid"; mkdosfs -F 32 -s 1 -n EFI /dev/disk/by-partuuid/$partUuid'
  read -p " [ Enter ] " keypress

  innerSeperator "Create /boot/efi"
  chroot /mnt mkdir /boot/efi
  read -p " [ Enter ] " keypress

  innerSeperator "Write /etc/fstab"
  chroot /mnt echo -e "PARTUUID=\"${BOOT_PARTITIONS_PARTUUID[0]}\" /boot/efi vfat defaults 0 0" >> /mnt/etc/fstab
  unset partUuid

  innerSeperator "Mount EFI"
  chroot /mnt mount /boot/efi
  read -p " [ Enter ] " keypress

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
  BPOOL_SERVICE=$(
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
  chroot /mnt echo -e "GRUB_SAVEDEFAULT=false\nGRUB_DEFAULT=saved" >> /etc/default/grub
  chroot /mnt update-grub

  stepByStep "chrootChangeGrubDefaults"
}

function chrootGrubInstall() {
  # after reboot all boot disks...
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
  innerSeperator "Chroot get the zed application and exit automatically ( pkill -15 zed)"
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
${CLONE_FUNCTION}

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
#    getUserPassword
#    echo "\${username}:\${userPass}" | chpasswd
    innerSeperator "\${username} 's Password has Changed"
  fi
}

function startTaskSel() {
  dividerLine "TASKSEL"
  tasksel
}

cloneUefiPart
read -p "To Continue [ Enter ] " keypress
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

function copyZfsCompletion {
  dividerLine "Copy zfs bash completion to zpool | Activates zpool completion"
  chroot /mnt cp /usr/share/bash-completion/completions/zfs /usr/share/bash-completion/completions/zpool
  stepByStep "copyZfsCompletion"
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
  zfs unmount -a

  stepByStep "unmountAllFilesystems"
}

function exportZfsPools() {
  dividerLine "Export ZFS Pools"

  zpool export "${bPoolName}"
  zpool export "${rPoolName}"

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

##### START #####
amiAllowed
aptSourcesHttp
installBaseApps
aptSourcesHttps
aptUpdateUpgrade
selectPoolNames
checkSystemHaveZfsPool
selectSystemDisk
selectRaidType
selectInstallationDisks
labelClear
wipeDisks
createPartitions
labelClear  # if ZFS installed before on that partition same name, it's there, clear it again.
getPartUUIDofDisks
cloneableUefiPart
cloneUefiPartFunctionBuilder
swapsOffline
checkMdadmArray
createBootPool
createRootPool
createPoolsAndMounts
createOtherDatasets
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
copyZfsCompletion
chrootTakeInitialSnapshots
unmountAllFilesystems
exportZfsPools
rebootSystem
