NETWORK_INTERFACE=${NETWORK_INTERFACE:-"ue0"}

init_network() {
  prompt_yn "Initialize ${NETWORK_INTERFACE} using DHCP?" || return
  print_header "Initializing network"
  exec_no_promt "ifconfig ${NETWORK_INTERFACE} up"
  exec_no_promt "dhclient ${NETWORK_INTERFACE}"
}

print_header() {
  printf '[38;5;45m *** %s ***[0m\r\n' "$*"
}

print_info() {
  printf '[38;5;251m%s[0m\r\n' "$*"
}

print_exec() {
  printf '[38;5;246m%s[0m\r\n' "$*"
}

print_debug() {
  $DEBUG || return
  printf '[38;5;242mDEBUG: %s[0m\r\n' "$*"
}

print_error() {
  printf '[38;5;9mERROR: %s[0m\r\n' "$*"
}

exec_no_promt() {
  print_exec "$@"
  $@
  local rc=$?
  print_debug "RC: ${rc}"

  if [ "${rc}" -ne 0 ]; then
    print_error "RC=${rc}"
    if ! prompt_yn "Continue?"; then
      exit 1
    fi
  fi
}

prompt_yn() {
  local question=$1; shift
  local response
  local old_stty_config
  printf "[38;5;255m%s [y|n] " "${question}"

  old_stty_config=$(stty -g)
  stty raw -echo
  response=$( while ! head -c 1 | grep -i '[yn]'; do true; done )
  stty ${old_stty_config}
  
  if [ "${response}" == "y" ]; then
    echo ${response}
    printf "[0m"
    return 0
  else
    echo ${response}
    printf "[0m"
    return 1
  fi
}
