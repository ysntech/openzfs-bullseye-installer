#!/usr/bin/env bash

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
    zfs create rpool/home/\${username}
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
#  echo -e "${AFTER_REBOOT_SH}" > /root/after-reboot.sh
  echo -e "${AFTER_REBOOT_SH}" > "$(pwd)"/after-reboot.sh
#  chmod 700 /root/after-reboot.sh
  chmod 700 "$(pwd)"/after-reboot.sh
}

afterReboot
