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
# The QUERY_FOLIO_NO_WARN may be specified to suppress custom script warnings.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local action=
  local base=
  local curl_output=
  local debug=
  local debug_json=
  local null="/dev/null"
  local pass=
  local path=
  local tenant=
  local token=
  local user=
  local warn="y"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "
  local p_w="WARNING: "

  local -i curl_error=0
  local -i login_eureka=0
  local -i login_print=0
  local -i result=0

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

query_folio_curl_login() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  curl_output=$(curl ${*})

  # Let the caller handle the result via query_folio_handle_result_existing().
  let result=${?}
  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${login_print} ]] ; then
    echo "${curl_output}"
  fi
}

query_folio_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

query_folio_handle_result_curl() {
  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  elif [[ ${curl_error} != "" ]] ; then
    echo "${p_e}${1} (curl error: ${curl_error})."
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

  if [[ ${QUERY_FOLIO_NO_WARN} != "" ]] ; then
    warn=
  fi

  if [[ ${QUERY_FOLIO_BASE_URL} != "" ]] ; then
    base=$(sed -e 's|/*$|/|g' <<< ${QUERY_FOLIO_BASE_URL})
  fi

  if [[ ${base} == "" ]] ; then
    echo "A base URL is required, please define the QUERY_FOLIO_BASE_URL environment variable."

    let result=1
    return
  fi

  if [[ ${QUERY_FOLIO_LOGIN_PASS} != "" ]] ; then
    pass=${QUERY_FOLIO_LOGIN_PASS}
  fi

  if [[ ${QUERY_FOLIO_URL_PATH} != "" ]] ; then
    path=$(sed -e 's|/*$|/|g' <<< ${QUERY_FOLIO_URL_PATH})
  fi

  if [[ ${QUERY_FOLIO_TENANT} != "" ]] ; then
    tenant=${QUERY_FOLIO_TENANT}
  fi

  if [[ ${QUERY_FOLIO_TOKEN} != "" ]] ; then
    token=${QUERY_FOLIO_TOKEN}
  fi

  if [[ ${QUERY_FOLIO_USER} != "" ]] ; then
    user=${QUERY_FOLIO_USER}
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
    if [[ ${2} == "print" || ${3} == "print" ]] ; then
      let login_print=1
    fi

    if [[ ${2} == "eureka" || ${3} == "eureka" ]] ; then
      let login_eureka=1
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

  query_folio_operate_login_eureka
  query_folio_operate_login_okapi

  # TODO
}

query_folio_operate_login_eureka() {

  if [[ ${result} -ne 0 || ${do_eureka} -ne 0 ]] ; then return ; fi

  local header_tenant=

  if [[ ${pass} == "" ]] ; then
    query_folio_print_warn "The pass is an empty string"
  fi

  if [[ ${path} == "" ]] ; then
    path="realms/master/protocol/openid-connect/token"
  fi

  if [[ ${tenant} == "" ]] ; then
    query_folio_print_warn "The tenant is an empty string"
  else
    header_tenant="x-okapi-tenant: ${tenant}"
  fi

  if [[ ${user} == "" ]] ; then
    query_folio_print_warn "The user is an empty string"
  fi

  query_folio_curl_login \
    --header "Content-Type: application/x-www-form-urlencoded"
    --header "${header_tenant}"
    --data-urlencode "client_id=${user}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${pass}" \
    ${base}${path}

  query_folio_handle_result_curl "Eureka login curl to ${base}${path} failed"
}

query_folio_operate_login_okapi() {

  if [[ ${result} -ne 0 || ${do_eureka} -eq 0 ]] ; then return ; fi
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

query_folio_print_warn() {

  if [[ ${warn} == "" ]] ; then return ; fi

  echo "${p_w}${1} ." >&2
  echo >&2
}

main ${*}
