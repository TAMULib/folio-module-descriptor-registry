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
  local json=
  local null="/dev/null"
  local object=
  local pass=
  local path=
  local tenant="diku"
  local token=
  local user=
  local warn="y"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "
  local p_w="WARNING: "

  local -a files=()
  local -a ids=()

  local -i curl_error=0
  local -i login_eureka=0
  local -i login_print=0
  local -i result=0

  query_folio_load_environment ${*}

  if [[ ${do_eureka} -eq 0 ]] ; then
    case "${action}" in
      "deploy") query_folio_operate_deploy_okapi ;;
      "enable") query_folio_operate_enable_okapi ;;
      "disable") query_folio_operate_disable_okapi ;;
      "login") query_folio_operate_login_okapi ;;
      "register") query_folio_operate_register_okapi ;;
      "undeploy") query_folio_operate_undeploy_okapi ;;
      "unregister") query_folio_operate_unregister_okapi ;;
    esac
  else
    case "${action}" in
      "deploy") query_folio_operate_deploy_eureka ;;
      "enable") query_folio_operate_enable_eureka ;;
      "disable") query_folio_operate_disable_eureka ;;
      "login") query_folio_operate_login_eureka ;;
      "register") query_folio_operate_register_eureka ;;
      "undeploy") query_folio_operate_undeploy_eureka ;;
      "unregister") query_folio_operate_unregister_eureka ;;
    esac
  fi

  return ${result}
}

query_folio_curl_execute() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  curl --header "X-Okapi-Tenant: ${tenant}" --header 'X-Okapi-Token: ${token}' ${*} ${base}${path}

  # Let the caller handle the result via query_folio_handle_result_curl().
  let result=${?}
}

query_folio_curl_login() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  curl_output=$(curl --silent -X POST --header 'Accept: application/json' ${*} ${base}${path})

  # Let the caller handle the result via query_folio_handle_result_curl().
  let result=${?}
  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${login_print} -ne 0 ]] ; then
    echo "${curl_output}"
  fi
}

query_folio_curl_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_curl_execute --header 'Accept: application/json' --header 'Content-Type: application/json' ${*}
}

query_folio_curl_url_enc() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_curl_execute --header 'Accept: application/json' --header "Content-Type: application/x-www-form-urlencoded" ${*}
}

query_folio_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

query_folio_handle_result_curl() {

  local message="Curl to ${base}${path} for ${1} failed"

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${message} (system code ${result})."
    echo
  elif [[ ${curl_error} != "" ]] ; then
    echo "${p_e}${message} failed (curl error: ${curl_error})."
    echo
  fi
}

query_folio_json_append_to_array() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_append=". += ${append}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    json=$(jq -M "${jq_append}" <<< ${json})
  else
    json=$(jq -M "${jq_append}" <<< ${json} 2> ${null})
  fi

  query_folio_handle_result "Failed to load release IDs from JSON: ${file}"
}

query_folio_json_array_of_ids() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local append=
  local id=

  local -i i=0
  local -i total=${#ids[*]}

  json="[]"
  while [[ ${i} -lt ${total} ]] ; do
    id=${ids[${i}]}
    append=$(sed -e "s|_REPLACE_ID_|${id}|g" <<< ${object})

    query_folio_json_append_to_array
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

query_folio_load_environment() {
  local -i i=0

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

  if [[ ${QUERY_FOLIO_BASE_PATH} != "" ]] ; then
    base="${base}$(sed -e 's|/*$|/|g' <<< ${QUERY_FOLIO_BASE_PATH})"
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
    "discover" | "enable" | "disable" | "login" | "register" | "undeploy" | "unregister")
      action=${1}
      ;;
    *)
      echo "${p_e}The first argument '${1}' does not represent a supported action."

      let result=1
      return
      ;;
  esac

  if [[ ${action} == "login" ]] ; then
    if [[ ${2} == "eureka" || ${3} == "eureka" ]] ; then
      let login_eureka=1
    fi

    if [[ ${2} == "print" || ${3} == "print" ]] ; then
      let login_print=1
    fi
  elif [[ ${action} == "deploy" || ${action} == "register" ]] ; then
    let i=2
    while ${i} -lt ${#} ; do
      query_folio_verify_json "Input JSON" "${!i}"
      if [[ ${result} -ne 0 ]] ; then return ; fi

      files+=(${!i})
      let i++
    done
  elif [[ ${action} == "disable" || ${action} == "enable" || ${action} == "undeploy" || ${action} == "unregister" ]] ; then
    let i=2
    while ${i} -lt ${#} ; do
      if [[ $(grep -sho '"' <<< ${!i}) != "" ]] ; then
        echo "${p_e}The argument ${i} '${!i}' has a double quote, which is not allowed."

        let result=1
        return
      fi

      ids+=(${!i})
      let i++
    done

    if [[ ${2} == "" ]] ; then
      echo "An ID is required for the ${action} action."

      let result=1
      return
    fi

    id=${2}
  fi
}

query_folio_operate_deploy_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_deploy_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=

  local -i i=0
  local -i total=${#files[*]}

  path="_/discovery/modules"

  while [[ ${i} -lt ${total} ]] ; do
    file=${files[${i}]}

    query_folio_curl_json -X POST --data "@${file}"

    query_folio_handle_result_curl "OKAPI Deploy"
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

query_folio_operate_disable_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_disable_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  object='{ "action": "disable", "id": "_REPLACE_ID_" }'

  query_folio_json_array_of_ids

  path="_/proxy/tenants/${tenant}/install"

  query_folio_curl_json -X POST -d "${json}"

  query_folio_handle_result_curl "OKAPI Disable"
}

query_folio_operate_enable_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_enable_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  object='{ "action": "enable", "id": "_REPLACE_ID_" }'

  query_folio_json_array_of_ids

  path="_/proxy/tenants/${tenant}/install"

  query_folio_curl_json -X POST -d "${json}"

  query_folio_handle_result_curl "OKAPI Enable"
}

query_folio_operate_login_eureka() {

  if [[ ${result} -ne 0 || ${do_eureka} -ne 0 ]] ; then return ; fi

  local header_tenant=

  if [[ ${pass} == "" ]] ; then
    query_folio_print_warn "The pass is an empty string"
  fi

  if [[ ${tenant} == "" ]] ; then
    query_folio_print_warn "The tenant is an empty string"
  else
    header_tenant="x-okapi-tenant: ${tenant}"
  fi

  if [[ ${user} == "" ]] ; then
    query_folio_print_warn "The user is an empty string"
  fi

  path="realms/master/protocol/openid-connect/token"

  query_folio_curl_login  \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --header "${header_tenant}" \
    --data-urlencode "client_id=${user}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${pass}"
  # TODO: need to fetch the token from the response.

  query_folio_handle_result_curl "Eureka Login"
}

# TODO: should I make login automatic for each action rather than a separate action, then TOKEN doesn't need to be exported?
query_folio_operate_login_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_operate_login_okapi_escape_object
  query_folio_operate_login_okapi_curl
}

query_folio_operate_login_okapi_curl() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  path="authn/login-with-expiry"

  query_folio_curl_login --header "Content-Type: application/json" --data "${object}"
  # TODO: need to fetch the token from the response.

  query_folio_handle_result_curl "OKAPI Login"
}

query_folio_operate_login_okapi_escape_object() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_object='{ "username": $user, "password" : $pass, "tenant": $tenant }'

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    object=$(jq -n -M --arg user "${user}" --arg pass "${pass}" --arg tenant "${tenant}" "${jq_object}")
  else
    object=$(jq -n -M --arg user "${user}" --arg pass "${pass}" --arg tenant "${tenant}" "${jq_object}" 2> ${null})
  fi

  query_folio_handle_result "Failed construct escaped username and password JSON"
}

query_folio_operate_register_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # TODO
}

query_folio_operate_register_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=

  local -i i=0
  local -i total=${#files[*]}

  path="_/proxy/modules"

  while [[ ${i} -lt ${total} ]] ; do
    file=${files[${i}]}

    query_folio_curl_json -X POST --data "@${file}"

    query_folio_handle_result_curl "OKAPI Register"
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

query_folio_operate_undeploy_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local id=

  local -i i=0
  local -i total=${#ids[*]}

  while [[ ${i} -lt ${total} ]] ; do
    id=${ids[${i}]}
    path="_/discovery/modules/${id}"

    query_folio_curl_json -X DELETE

    query_folio_handle_result_curl "OKAPI Undeploy"
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

query_folio_operate_unregister_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local id=

  local -i i=0
  local -i total=${#ids[*]}

  while [[ ${i} -lt ${total} ]] ; do
    id=${ids[${i}]}
    path="_/proxy/modules/${id}"

    query_folio_curl_json -X DELETE

    query_folio_handle_result_curl "OKAPI Unregister"
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
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

query_folio_verify_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local file=${2}

  if [[ ${file} == "" || ! -f ${file} ]] ; then
    let result=1
  else
    if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
      jq < ${file}
    else
      jq < ${file} >> ${null} 2>&1
    fi

    let result=${?}
  fi

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}The ${name} '${file}' does not exist or is not a valid JSON file."
    echo
  fi
}

main ${*}
