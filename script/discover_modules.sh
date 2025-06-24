#!/bin/bash
#
# Discover modules (register modules to the discovery end point).
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
#   - mkdir
#   - sed
#   - yq
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The REGISTER_MOD_DEBUG may be specifically set to "json" to include printing the json commands.
# The REGISTER_MOD_DEBUG may be specifically set to "json_only" to only print the json commands, disabling all other debugging.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local null="/dev/null"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  discover_mod_load_environment ${*}

  # perform operate here

  return ${result}
}

discover_mod_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

discover_mod_load_environment() {

  if [[ ${REGISTER_MOD_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${REGISTER_MOD_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${REGISTER_MOD_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${REGISTER_MOD_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi
}

discover_mod_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

main ${*}
