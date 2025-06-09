#!/bin/bash
#
# Build the Module Discovery JSON file using an Application Descriptor JSON file as input.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
#   - sed
#
#  Parameters:
#    1) The input JSON file used as the source (specify overrides BUILD_MOD_DISCOVERY_INPUT).
#    2) The output JSON file used as the destination (specify overrides BUILD_MOD_DISCOVERY_OUTPUT).
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_MOD_DISCOVERY_DEBUG may be specifically set to "json" to include printing the JSON files.
# The BUILD_MOD_DISCOVERY_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local field="name"
  local file_input=
  local file_output=
  local file_force=0
  local null="/dev/null"
  local url_prefix="http://"
  local url_suffix=".folio-modules.svc"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  build_mod_disc_load_environment ${*}

  build_mod_disc_verify_json "input file" ${file_input}
  build_mod_disc_verify_output "output file" ${file_output}

  build_mod_disc_build

  return ${result}
}

build_mod_disc_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local field_name=
  local id=
  local json="{"
  local location=
  local name=
  local value=
  local version=

  local -i i=0
  local -i total=0

  build_mod_disc_build_total

  if [[ ${total} -eq 0 && ${debug} != "" ]] ; then
    echo "${p_d}No modules found in the input file: ${file_input} ."
  else
    echo "Operating on ${total} items in input file: ${file_input}"
  fi

  echo

  json="${json} \"discovery\": ["

  build_mod_disc_handle_result ${fail_message}

  if [[ ${result} -ne 0 ]] ; then return ; fi

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_disc_get_value_at ${i} id
    id=${value}

    build_mod_disc_get_value_at ${i} name
    name=${value}

    build_mod_disc_get_value_at ${i} version
    version=${value}

    build_mod_disc_print_debug "Processing id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

    if [[ ${result} -ne 0 ]] ; then return ; fi

    if [[ ${field} == "id" ]] ; then
      field_name="${id}"
    elif [[ ${field} == "name" ]] ; then
      field_name="${name}"
    elif [[ ${field} == "version" ]] ; then
      field_name="${version}"
    fi

    field_name=$(echo "${field_name}" | sed -e 's|\.|-|g')

    json="${json} {"
    json="${json} \"location\": \"${url_prefix}${field_name}${url_suffix}\","
    json="${json} \"id\": \"${id}\","
    json="${json} \"name\": \"${name}\","
    json="${json} \"version\": \"${version}\""
    json="${json} }"

    let i++

    if [[ ${i} -lt ${total} ]] ; then
      json="${json},"
    fi

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  json="${json} ] }"

  build_mod_disc_build_write

  if [[ ${result} -ne 0 ]] ; then return ; fi

  echo
  echo "Done: Module Discovery JSON built: ${file_output} ."
}

build_mod_disc_build_total() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_total=".modules | length"
  local data=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -r -M "${jq_total}" ${file_input})
  else
    data=$(jq -r -M "${jq_total}" ${file_input} 2> ${null})
  fi

  build_mod_disc_handle_result "Failed to load modules array length from JSON: ${file_input}"

  if [[ ${result} -eq 0 && ${data} != "" && ${data} != "null" ]] ; then
    let total=${data}
  fi
}

build_mod_disc_build_write() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq -r -M . > ${file_output} <<< ${json}
  else
    jq -r -M . > ${file_output} <<< ${json} 2> ${null}
  fi

  build_mod_disc_handle_result "Failed to write to the output JSON file: ${file_output}"
}

build_mod_disc_get_value_at() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local index=${1}
  local key=${2}
  local jq_key=".modules[${index}].${key}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(jq -r -M "${jq_key}" ${file_input})
  else
    value=$(jq -r -M "${jq_key}" ${file_input} 2> ${null})
  fi

  build_mod_disc_handle_result "Failed to load key '${key}' at index '${index}' from JSON: ${file_input}"
}

build_mod_disc_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_mod_disc_load_environment() {

  if [[ ${BUILD_MOD_DISCOVERY_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${BUILD_MOD_DISCOVERY_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_MOD_DISCOVERY_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_MOD_DISCOVERY_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    elif [[ $(echo ${BUILD_MOD_DISCOVERY_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
      debug_json="y"
    fi
  fi

  if [[ ${1} != "" ]] ; then
    file_input=${1}
  elif [[ ${BUILD_MOD_DISCOVERY_INPUT} != "" ]] ; then
    file_input=${BUILD_MOD_DISCOVERY_INPUT}
  fi

  if [[ ${2} != "" ]] ; then
    file_output=${2}
  elif [[ ${BUILD_MOD_DISCOVERY_OUTPUT} != "" ]] ; then
    file_output=${BUILD_MOD_DISCOVERY_OUTPUT}
  fi

  if [[ ${BUILD_MOD_DISCOVERY_FORCE} != "" ]] ; then
    let file_force=1
  fi

  if [[ ${BUILD_MOD_DISCOVERY_URL_PREFIX} != "" ]] ; then
    url_prefix=${BUILD_MOD_DISCOVERY_URL_PREFIX}
  fi

  if [[ ${BUILD_MOD_DISCOVERY_URL_SUFFIX} != "" ]] ; then
    url_suffix=${BUILD_MOD_DISCOVERY_URL_SUFFIX}
  fi

  if [[ ${BUILD_MOD_DISCOVERY_FIELD} == "id" || ${BUILD_MOD_DISCOVERY_FIELD} == "name" || ${BUILD_MOD_DISCOVERY_FIELD} == "version" ]] ; then
    field=${BUILD_MOD_DISCOVERY_FIELD}
  fi
}

build_mod_disc_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_mod_disc_verify_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local file=${2}

  if [[ ${file} == "" || ! -f ${file} ]] ; then
    let result=1
  else
    # Prevent jq from printing JSON if ${null} exists when not debugging.
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

build_mod_disc_verify_output() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=${2}
  local name=${1}

  if [[ -e ${file} ]] ; then
    if [[ -f ${file} ]] ; then
      if [[ ${file_force} -eq 0 ]] ; then
        echo "${p_e}The ${name} '${file}' already exists."
        echo

        let result=1
      fi
    else
      echo "${p_e}The ${name} '${file}' exists but is not a regular file."
      echo

      let result=1
    fi
  fi
}

main ${*}
