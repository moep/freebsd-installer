#!/bin/sh

ESSENTIAL_PKGS="bash bat curl fish fzf git glow gnuls gmake ncdu neovim ripgrep tmux ufetch "
DEBUG=false
ZPOOL_NAME="zroot"

. $(dirname $0)/functions.sh

setup_time_zone() {
  if prompt_yn "Use timezone Europe/Berlin without UTC?"; then
    exec_no_promt touch /etc/wall_cmos_clock
    exec_no_promt cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  else
    tzsetup
  fi
}

install_pkgs() {
  print_header "Installing essential packages"
  exec_no_promt pkg update
  exec_no_promt pkg install ${ESSENTIAL_PKGS} 
}

add_users() {
  print_header "Performing user setup"

  if prompt_yn "Set root password?"; then
    passwd
  fi
  
  if prompt_yn "Add one or more users?"; then
    adduser
  fi
}


create_ports_index() {
  if [ ! -d /usr/ports ]; then 
    return
  fi

  if prompt_yn "Create ports index?"; then
    cd /usr/ports
    make index
  fi
}

install_x() {
  prompt_yn "Install X11?" || return

  print_header "Installing X11"
  exec_no_promt "pkg install xorg-minimal i3 i3blocks alacritty dmenu fehbg xrandr"

  if prompt_yn "Install NVIDIA driver?"; then
    exec_no_promt "pkg install nvidia-driver nvidia-settings"
    print_info 'Adding kldload entry to rc.conf'
    echo 'kldload_nvidia="nvidia"' >> /etc/rc.conf
    print_info 'Adding xorg setting'
    exec_no_promt "cp /root/driver-nvidia.conf /usr/local/share/X11/xorg.conf.d/driver-nvidia.conf"
  fi

}

create_snapshot() {
  if prompt_yn "Create zfs snapshot of ${ZPOOL_NAME}?"; then
    exec_no_promt zfs snapshot -r ${ZPOOL_NAME}@initial
  fi
}

main() {
  setup_time_zone
  init_network
  install_pkgs
  add_users
  create_ports_index
  install_x
  create_snapshot

  print_header "END OF POST INSTALL"

  ufetch
}

main $@
