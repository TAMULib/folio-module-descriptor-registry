#!/bin/bash
#
# Perform various FOLIO queries, using Curl.
#
# This requires the following user-space programs:
#   - bash
#   - curl
#   - grep
#   - jq
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
  local auth_header=
  local auth_header_sidecar=
  local base=
  local beep_char=$(echo -ne "\007") # Use beep character to represent newlines give bash's lack of support in variables.
  local client_id_master="folio-backend-admin-client"
  local client_id_sidecar="sidecar-module-access-client"
  local client_secret_master=
  local client_secret_sidecar=
  local curl_error=
  local curl_header=
  local curl_output=
  local debug=
  local debug_json=
  local json=
  local null="/dev/null"
  local object=
  local pass=
  local path=
  local tenant="diku"
  local token= # For both master token and OKAPI token.
  local token_sidecar=
  local user=
  local warn="y"
  local what=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "
  local p_w="WARNING: "

  local -a files=()
  local -a ids=()

  local -i do_export=0
  local -i is_eureka=0
  local -i login_print=0
  local -i result=0

  query_folio_load_environment ${*}

  # Enable exporting on login to allow for sourcing the script to expose the tokens to the caller.
  if [[ ${action} == "login" ]] ; then
    let do_export=1
  fi

  if [[ ${is_eureka} -eq 0 ]] ; then
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
      "login") query_folio_operate_login_eureka ;;
      "register") query_folio_operate_register_eureka ;;
      "unregister") query_folio_operate_unregister_eureka ;;
    esac
  fi

  return ${result}
}

query_folio_curl_execute() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # For splitting curl header from payload.
  local sed_separate="${beep_char}-----separate-----${beep_char}"
  local silent=

  if [[ ${debug} != "" ]] ; then
    silent="-s"
  fi

  curl_output=$(
    curl ${silent} -H "X-Okapi-Tenant: ${tenant}" -D - "${@}" ${base}${path} |
      sed -e "s|^\r$|${sed_separate}|" -e "s|\r||g" -e "s|\$|${beep_char}|g"
  )

  # Let the caller handle the result via query_folio_handle_result_curl().
  let result=${?}

  # Headers will maintain beep for EOL but the output will not utilize beep.
  curl_header=$(sed -e 's|\n||g' -e "s|${sed_separate}.*\$||" <<< ${curl_output})
  curl_output=$(sed -e 's|\n||g' -e "s|^.*${sed_separate}||" -e "s|${beep_char}|\n|g" <<< ${curl_output})

  if [[ $(grep -shoP "^HTTP[^${beep_char}]*\s+2\d+${beep_char}" <<< ${curl_header}) == "" ]] ; then
    curl_error=$(grep -shoP "^HTTP[^${beep_char}]*${beep_char}" <<< ${curl_output} | sed -e "s|${beep_char}||g")
  else
    curl_error=
  fi
}

query_folio_curl_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_curl_execute -H 'Accept: application/json' -H 'Content-Type: application/json' -H "${auth_header}" ${*}
}

query_folio_curl_url_enc() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_curl_execute -H 'Accept: application/json' -H "Content-Type: application/x-www-form-urlencoded" -H "${auth_header}" ${*}
}

query_folio_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

query_folio_handle_result_curl() {

  if [[ ${result} -eq 0 ]] ; then return ; fi

  echo -n "${p_e}Curl to ${base}${path} for ${1} failed "

  if [[ ${result} -eq 0 && ${curl_error} != "" ]] ; then
    echo -n "with curl error: ${curl_error} and "

    let result=1
  fi

  echo "with payload: ${curl_output} ."
  echo
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

  local action=${1}
  local append=
  local id=

  local -i i=0
  local -i total=${#ids[*]}

  json="[]"
  while [[ ${i} -lt ${total} ]] ; do
    id=${ids[${i}]}
    append='{ "action": "${action}", "id": "${id}" }'

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

  if [[ ${QUERY_FOLIO_IS_EUREKA} != "" ]] ; then
    let is_eureka=1
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

  if [[ ${QUERY_FOLIO_BASE_PATH} != "" ]] ; then
    base="${base}$(sed -e 's|/*$|/|g' <<< ${QUERY_FOLIO_BASE_PATH})"
  fi

  if [[ ${QUERY_FOLIO_CLIENT_ID_MASTER} != "" ]] ; then
    client_id_master=${QUERY_FOLIO_CLIENT_ID_MASTER}
  fi

  if [[ ${QUERY_FOLIO_CLIENT_ID_SIDECAR} != "" ]] ; then
    client_id_sidecar=${QUERY_FOLIO_CLIENT_ID_SIDECAR}
  fi

  if [[ ${QUERY_FOLIO_CLIENT_SECRET_MASTER} != "" ]] ; then
    client_secret_master=${QUERY_FOLIO_CLIENT_SECRET_MASTER}
  fi

  if [[ ${QUERY_FOLIO_CLIENT_SECRET_SIDECAR} != "" ]] ; then
    client_secret_sidecar=${QUERY_FOLIO_CLIENT_SECRET_SIDECAR}
  fi

  if [[ ${QUERY_FOLIO_LOGIN_PASS} != "" ]] ; then
    pass=${QUERY_FOLIO_LOGIN_PASS}
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
    "deploy" | "enable" | "disable" | "login" | "register" | "undeploy" | "unregister")
      action=${1}
      ;;
    *)
      echo "${p_e}The first argument '${1}' does not represent a supported action."

      let result=1
      return
      ;;
  esac

  if [[ ${action} == "login" ]] ; then
    if [[ ${2} == "print" ]] ; then
      let login_print=1
    fi
  else
    if [[ ${is_eureka} -ne 0 ]] ; then
      if [[ ${action} != "register" && ${action} != "unregister" ]] ; then
        echo "${p_e}The action '${action}' is not supported by Eureka."

        let result=1

        return
      fi
    fi

    what=${2}
    query_folio_load_environment_verify_action_what
    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i=3

    if [[ ${action} == "deploy" || ${action} == "register" ]] ; then
      while ${i} -lt ${#} ; do
        query_folio_verify_json "Input JSON" "${!i}"
        if [[ ${result} -ne 0 ]] ; then return ; fi

        files+=(${!i})
        let i++
      done
    else
      while ${i} -lt ${#} ; do
        if [[ $(grep -sho '"' <<< ${!i}) != "" ]] ; then
          echo "${p_e}The argument ${i} '${!i}' has a double quote, which is not allowed."

          let result=1
          return
        fi

        ids+=(${!i})
        let i++
      done
    fi
  fi
}

query_folio_load_environment_verify_action_what() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${what} == "application" || ${what} == "discovery" ]] ; then
    if [[ ${is_eureka} -eq 0 ]] ; then
      echo "${p_e}The argument '${what}' is not supported for OKAPI action: ${action} ."

      let result=1
    fi
  elif [[ ${what} == "module" ]] ; then
    if [[ ${is_eureka} -ne 0 ]] ; then
      if [[ ${action} == "register" || ${action} == "unregister" ]] ; then
        echo "${p_e}The argument '${what}' is not supported for Eureka action: ${action} ."

        let result=1
      fi
    fi
  else
    echo "${p_e}The argument '${what}' is not supported for action: ${action} ."

    let result=1
  fi
}

query_folio_operate_deploy_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path="_/discovery/modules"

  query_folio_operate_login_if_needed

  query_folio_process_files POST "OKAPI Deploy"
}

query_folio_operate_disable_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_operate_login_if_needed

  query_folio_json_array_of_ids "disable"

  path="_/proxy/tenants/${tenant}/install"

  query_folio_curl_json -X POST -d "${json}"
  query_folio_handle_result_curl "OKAPI Disable"
}

query_folio_operate_enable_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_operate_login_if_needed

  query_folio_json_array_of_ids "enable"

  path="_/proxy/tenants/${tenant}/install"

  query_folio_curl_json -X POST -d "${json}"
  query_folio_handle_result_curl "OKAPI Enable"
}

query_folio_operate_login_if_needed() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${token} == "" ]] ; then
    if [[ ${is_eureka} -eq 0 ]] ; then
      query_folio_operate_login_okapi
    else
      query_folio_operate_login_eureka
    fi
  fi

  if [[ ${auth_header} == "" ]] ; then
    if [[ ${is_eureka} -eq 0 ]] ; then
      auth_header="X-Okapi-Token: ${token}"
    else
      auth_header="Authorization: Bearer ${token}"
      auth_header_sidecar="Authorization: Bearer ${token_sidecar}"
    fi
  fi
}

query_folio_operate_login_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

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

  query_folio_operate_login_eureka_for "master" "${client_id_master}"
  query_folio_operate_login_eureka_extract_token "master"

  query_folio_operate_login_eureka_for "sidecar" "${client_id_sidecar}"
  query_folio_operate_login_eureka_extract_token "sidecar"

  query_folio_operate_login_print_token
}

query_folio_operate_login_eureka_for() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local client_id=${2}
  local client_secret=${3}
  local target=${1}

  path="realms/${target}/protocol/openid-connect/token"

  query_folio_curl_execute \
    -X POST \
    -H 'Accept: application/json'  \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "${header_tenant}" \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${client_secret}"

  query_folio_handle_result_curl "Eureka Login"
}

query_folio_operate_login_eureka_extract_token() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_token='.access_token'
  local target=${1}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    object=$(jq -M "${jq_token}" <<< ${curl_output})
  else
    object=$(jq -M "${jq_token}" <<< ${curl_output} 2> ${null})
  fi

  query_folio_handle_result "Failed construct escaped username and password JSON"
}

query_folio_operate_login_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  query_folio_operate_login_okapi_escape_object
  query_folio_operate_login_okapi_curl
}

query_folio_operate_login_okapi_curl() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  path="authn/login-with-expiry"

  query_folio_curl_execute -X POST -H 'Accept: application/json' -H "Content-Type: application/json" -d "${object}"
  query_folio_handle_result_curl "OKAPI Login"

  query_folio_operate_login_okapi_extract_token
  query_folio_operate_login_print_token

  # Cannot export token as ${token} due to the "local" definition.
  # Furthermore, the upper case should be used as per recommended ENV practices.
  if [[ ${do_export} -ne 0 ]] ; then
    export FOLIO_TOKEN=${token}
    export FOLIO_TOKEN_SIDECAR=${token_sidecar}
  fi
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

query_folio_operate_login_okapi_extract_token() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  token=$(grep -shoP "set-cookie:\s*folioAccessToken=[^;]+" <<< ${curl_header} | sed -e 's|set-cookie:\s*folioAccessToken=||')

  query_folio_handle_result "Failed extract the token from the JSON response"
}

query_folio_operate_login_print_token() {

  if [[ ${result} -ne 0 || ${login_print} -eq 0 ]] ; then return ; fi

  local jq_object=

  if [[ ${is_eureka} -eq 0 ]] ; then
    jq_object='{ "token": $token }'
  else
    jq_object='{ "master": $token, "sidecar": $token_sidecar }'
  fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq -n -M --arg token "${token}" --arg token_sidecar "${token_sidecar}" "${jq_object}"
  else
    jq -n -M --arg token "${token}" --arg token_sidecar "${token_sidecar}" "${jq_object}" 2> ${null}
  fi

  query_folio_handle_result "Failed construct token using JQ for printing"
}

query_folio_operate_register_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path=

  if [[ ${what} == "application" ]] ; then
    base_path="applications"
  elif [[ ${what} == "discovery" ]] ; then
    base_path="modules/discovery"
  fi

  query_folio_operate_login_if_needed

  query_folio_process_files POST "Eureka Register"
}

query_folio_operate_register_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path="_/proxy/modules"

  query_folio_operate_login_if_needed

  query_folio_process_files POST "OKAPI Register"
}

query_folio_operate_undeploy_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path="_/discovery/modules/${id}"

  query_folio_operate_login_if_needed

  query_folio_process_ids DELETE "OKAPI Undeploy"
}

query_folio_operate_unregister_eureka() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path=

  if [[ ${what} == "application" ]] ; then
    base_path="applications/${id}"
  elif [[ ${what} == "discovery" ]] ; then
    base_path="modules/${id}/discovery"
  fi

  query_folio_operate_login_if_needed

  query_folio_process_ids DELETE "Eureka Unregister"
}

query_folio_operate_unregister_okapi() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base_path="_/proxy/modules/${id}"

  query_folio_operate_login_if_needed

  query_folio_process_ids DELETE "OKAPI Unregister"
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

query_folio_process_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=
  local message=${2}
  local path=${base_path}
  local rest=${1}

  local -i i=0
  local -i total=${#files[*]}

  while [[ ${i} -lt ${total} ]] ; do
    file=${files[${i}]}

    query_folio_curl_json -X "${rest}" -d "@${file}"
    query_folio_handle_result_curl "${message}"

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

query_folio_process_ids() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local id=
  local message=${2}
  local path=
  local rest=${1}

  local -i i=0
  local -i total=${#ids[*]}

  while [[ ${i} -lt ${total} ]] ; do
    id=${ids[${i}]}
    path="${base_path}/${id}"

    query_folio_curl_json -X "${rest}"
    query_folio_handle_result_curl "${message}"

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
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
