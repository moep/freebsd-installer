#!/usr/bin/env sh

#    ████ ██                   ██   ██                    ██              ██  ██
#   ░██░ ░██                  ░██  ░░                    ░██             ░██ ░██
#  ██████░██       ██████     ░██   ██ ███████   ██████ ██████  ██████   ░██ ░██
# ░░░██░ ░██████  ██░░░░   ██████  ░██░░██░░░██ ██░░░░ ░░░██░  ░░░░░░██  ░██ ░██
#   ░██  ░██░░░██░░█████  ██░░░██  ░██ ░██  ░██░░█████   ░██    ███████  ░██ ░██
#   ░██  ░██  ░██ ░░░░░██░██  ░██  ░██ ░██  ░██ ░░░░░██  ░██   ██░░░░██  ░██ ░██
#   ░██  ░██████  ██████ ░░██████  ░██ ███  ░██ ██████   ░░██ ░░████████ ███ ███
#   ░░   ░░░░░   ░░░░░░   ░░░░░░   ░░ ░░░   ░░ ░░░░░░     ░░   ░░░░░░░░ ░░░ ░░░ 

. $(dirname $0)/functions.sh

# Partition options
TARGET_DEV="/dev/ada0"
ROOT_PARTITION_SIZE="300G"
EFI_PARTITION_SIZE="256M"
ZPOOL_NAME="zroot"

# Network options
export HOST_NAME="m0epstation"
export NETWORK_INTERFACE="ue0"
export HOST_IP="192.168.0.6"
export NETMASK="255.255.255.0"
export DEFAULT_ROUTER="192.168.0.1"

# Misc options
export NUM_CPUS=16

DEBUG=false


clear_disk() {
  if  prompt_yn "Delete all partitions and rewrite GPT for ${TARGET_DEV}?"; then
    print_info "Clearing ${TARGET_DEV}"
    exec_no_promt "zpool labelclear -f ${TARGET_DEV}p3"
    exec_no_promt "gpart delete -i 3 ${TARGET_DEV}"
    exec_no_promt "gpart delete -i 2 ${TARGET_DEV}"
    exec_no_promt "gpart delete -i 1 ${TARGET_DEV} "
    exec_no_promt "gpart destroy ${TARGET_DEV}"
  fi
}

create_partitions() {
  print_info "Creating disk partitions"
  exec_no_promt "gpart create -s GPT ${TARGET_DEV}"
  exec_no_promt "gpart add -a 4k -s ${EFI_PARTITION_SIZE} -t efi -l nixefi ${TARGET_DEV}"
  exec_no_promt "newfs_msdos -F 32 -c 1 ${TARGET_DEV}p1"

  exec_no_promt "gpart add -t freebsd-boot  -s 5M -l freebsd-boot ${TARGET_DEV}"
  exec_no_promt "gpart add -t freebsd-zfs -l freebsd-system -s ${ROOT_PARTITION_SIZE} ${TARGET_DEV}"

  print_info "Creating ZFS vdev, pool and datasets"

  exec_no_promt "mkdir -p /tmp/zfs"
  #zfs import
  exec_no_promt "zpool create -m  / -R /tmp/zfs ${ZPOOL_NAME} ${TARGET_DEV}p3"
  exec_no_promt "zpool set bootfs=${ZPOOL_NAME} ${ZPOOL_NAME}"
  exec_no_promt "zfs create -V 8G ${ZPOOL_NAME}/swap"
  exec_no_promt "zfs set org.freebsd:swap=on ${ZPOOL_NAME}/swap"

  # optional zfs setup
  exec_no_promt mkdir -p /tmp/zfs/usr
  exec_no_promt zfs create ${ZPOOL_NAME}/home

  exec_no_promt zfs create -o mountpoint=/usr/ports -o compression=on -o setuid=off ${ZPOOL_NAME}/ports
  exec_no_promt zfs create -o compression=off -o exec=off -o setuid=off ${ZPOOL_NAME}/ports/distfiles
  exec_no_promt zfs create -o compression=off -o exec=off -o setuid=off ${ZPOOL_NAME}/ports/packages

  exec_no_promt zfs create -o mountpoint=/usr/local ${ZPOOL_NAME}/local
  exec_no_promt zfs create -o mountpoint=/usr/src -o compression=on ${ZPOOL_NAME}/src
  exec_no_promt zfs create -o mountpoint=/usr/doc -o compression=on ${ZPOOL_NAME}/doc

  exec_no_promt zfs create ${ZPOOL_NAME}/var
  exec_no_promt zfs create -o exec=off -o setuid=off ${ZPOOL_NAME}/var/db
  exec_no_promt zfs create -o compression=on -o exec=on -o setuid=off ${ZPOOL_NAME}/var/db/pkg
  exec_no_promt zfs create -o compression=on -o exec=on -o setuid=on ${ZPOOL_NAME}/var/db/mail
  exec_no_promt zfs create -o compression=on -o exec=on -o setuid=on ${ZPOOL_NAME}/var/db/log
  exec_no_promt zfs create -o exec=off -o setuid=off ${ZPOOL_NAME}/var/run
  exec_no_promt zfs create -o exec=off -o setuid=off ${ZPOOL_NAME}/var/tmp
  exec_no_promt zfs create -o exec=off -o setuid=off ${ZPOOL_NAME}/tmp
  exec_no_promt chmod 1777 /tmp/zfs/tmp /tmp/zfs/var/tmp

  exec_no_promt zfs create ${ZPOOL_NAME}/opt
}

install_base_system() {
  exec_no_promt cd /tmp/zfs 
  local file_location="/usr/freebsd-dist"

  print_header "Installing base system"

  print_info "Extracting base system"
  exec_no_promt "tar xf ${file_location}/base.txz -C /tmp/zfs"
  exec_no_promt "tar xf ${file_location}/kernel.txz -C /tmp/zfs"
  exec_no_promt "tar xf ${file_location}/lib32.txz -C /tmp/zfs"

  if prompt_yn "Install ports?"; then
    exec_no_promt "tar xf ${file_location}/ports.txz -C /tmp/zfs"
  fi

  if prompt_yn "Install src?"; then
    exec_no_promt "tar xf ${file_location}/src.txz -C /tmp/zfs"
  fi
}

configure_boot() {
  print_header "Configuring boot"
 
  if prompt_yn "Copy EFI bootloader to ${TARGET_DEV}p1:/EFI/FreeBSD ?"; then
    print_info "Copying EFI bootloader"
    exec_no_promt "mkdir /tmp/efi"
    exec_no_promt "mount -t msdosfs -o longnames ${TARGET_DEV}p1 /tmp/efi"
    exec_no_promt "mkdir -p /tmp/efi/EFI/FreeBSD"
    exec_no_promt "cp /tmp/zfs/boot/loader.efi /tmp/efi/EFI/FreeBSD/"

    if prompt_yn "Add EFI boot entry to NVRAM?"; then
      exec_no_promt "efibootmgr --create --activate --label FreeBSD --loader ${TARGET_DEV}p1:/EFI/FreeBSD/loader.efi"
    fi
  fi

  print_info "Writing configs"
  do_envsubst /tmp/loader.conf.in > /tmp/zfs/boot/loader.conf
  vi /tmp/zfs/boot/loader.conf
  do_envsubst /tmp/rc.conf.in > /tmp/zfs/etc/rc.conf
  vi /tmp/zfs/etc/rc.conf
  do_envsubst /tmp/rc.conf.local.in > /tmp/zfs/etc/rc.conf.local
  vi /tmp/zfs/etc/rc.conf.local
}

configure_ssh() {
  if prompt_yn "Copy ssh keys to installation?"; then
    print_header "Deleting old keys"
    chroot /tmp/zfs/ /bin/csh -c "rm /etc/ssh/ssh_host*"
    print_header "Copying new keys"
    exec_no_promt cp /etc/ssh/ssh_host_ecdsa_key /tmp/zfs/etc/ssh/ssh_host_ecdsa_key
    exec_no_promt cp /etc/ssh/ssh_host_ecdsa_key.pub /tmp/zfs/etc/ssh/ssh_host_ecdsa_key.pub
    exec_no_promt cp /etc/ssh/ssh_host_ed25519_key /tmp/zfs/etc/ssh/ssh_host_ed25519_key
    exec_no_promt cp /etc/ssh/ssh_host_ed25519_key.pub /tmp/zfs/etc/ssh/ssh_host_ed25519_key.pub
    exec_no_promt cp /etc/ssh/ssh_host_rsa_key /tmp/zfs/etc/ssh/ssh_host_rsa_key
    exec_no_promt cp /etc/ssh/ssh_host_rsa_key.pub /tmp/zfs/etc/ssh/ssh_host_rsa_key.pub
  fi
}

do_envsubst() {
  local file=$1

  while read line; do
    eval echo ${line}
  done < "${file}"
}

do_chroot() {
  print_header "Chrooting into new environment"

  print_info "Mounting pseudo file systems"
  exec_no_promt "mount -t procfs proc /tmp/zfs/proc"
  exec_no_promt "mount -t devfs /dev /tmp/zfs/dev"

  print_info "Copying files for post installation"
  exec_no_promt cp /etc/resolv.conf /tmp/zfs/etc/resolv.conf
  copy_file_if_exists /tmp/post-install.sh /tmp/zfs/root/post-install.sh
  copy_file_if_exists /tmp/functions.sh /tmp/zfs/root/functions.sh
  copy_file_if_exists /tmp/driver-nvidia.conf /tmp/zfs/root/driver-nvidia.conf

  configure_ssh

  print_header "Executing chroot commands"
  chmod 700 /tmp/zfs/root/post-install.sh
  chroot /tmp/zfs/ /bin/csh -c "/root/post-install.sh"
  print_info "Back to installer shell"

}

copy_file_if_exists() {
  local from=$1; shift
  local to=$1; 

  if [ -f "${from}" ]; then
    exec_no_promt "cp ${from} ${to}"
  fi
}

main() {
  print_header "Setting up disk"
  clear_disk
  create_partitions
  
  install_base_system
  configure_boot

  do_chroot

  print_header "FINISHED"
  print_info "You can now restart via 'init 6'."
}

main $@
