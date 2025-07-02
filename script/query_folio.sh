#!/bin/bash
#
# Perform various FOLIO queries, using Curl.
#
# This requires the following user-space programs:
#   - bash
#   - curl
#   - grep
#   - jq
#   - mkdir
#   - sed
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# This uses QUERY_FOLIO_TOKEN for the authentication token.
# The login process may be used to create this token or this token must be creted using this script.
# If this script is being used to export this QUERY_FOLIO_TOKEN variable, then this must be sourced, like this:
#   source query_folio.sh login
# Otherwise, the login should support a print option to print this into a variable, such as:
#   export QUERY_FOLIO_TOKEN=$(bash query_folio.sh login print)
#
# The QUERY_FOLIO_DEBUG may be specifically set to "json" to include printing the json commands.
# The QUERY_FOLIO_DEBUG may be specifically set to "json_only" to only print the json commands, disabling all other debugging.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local action=
  local debug=
  local debug_json=
  local null="/dev/null"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0
  local -i login_print=0

  query_folio_load_environment ${*}

  if [[ ${action} == "deploy" ]] ; then
    query_folio_operate_deploy
  elif [[ ${action} == "enable" ]] ; then
    query_folio_operate_enable
  elif [[ ${action} == "login" ]] ; then
    query_folio_operate_login
  elif [[ ${action} == "register" ]] ; then
    query_folio_operate_register
  fi

  return ${result}
}

query_folio_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

query_folio_load_environment() {

  if [[ ${QUERY_FOLIO_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(grep -sho '^\s*json_only\s*$' <<< ${QUERY_FOLIO_DEBUG}) != "" ]] ; then
      debug_json="y"
    elif [[ $(grep -sho '_only' <<< ${QUERY_FOLIO_DEBUG}) != "" ]] ; then
      debug=
    else
      if [[ $(grep -sho '\<json\>' <<< ${QUERY_FOLIO_DEBUG}) != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi

  case "${1}" in
    "discover" | "enable" | "login" | "register")
      action=${1}
      ;;
    *)
      echo "${p_e}The first argument '${1}' does not represent a support action."

      let result=1
      return
      ;;
  esac

  if [[ ${action} == "login" ]] ; then
    if [[ ${2} == "print" ]] ; then
      let login_print=1
    fi
  fi
}

query_folio_operate_deploy() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_enable() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_login() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_register() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

main ${*}
