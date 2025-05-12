#!/bin/bash
#
# Build the Module Discovery JSON file using an Application Descriptor JSON file as input.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
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

  build_mod_disc_verify_output

  build_mod_disc_build

  return ${result}
}

build_mod_disc_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local -i total=$(jq '.modules | length' ${file_input})

  local id=
  local location=
  local name=
  local value=
  local version=

  local -i i=0

  if [[ ${total} -eq 0 && ${debug} != "" ]] ; then
    echo "${p_d}No modules found in the input file: ${file_input} ."
  fi

  echo "{" > ${file_output}
  echo "  \"discovery\": [" >> ${file_output}

  while [[ ${i} -lt ${total} ]] ; do
    id=$(build_mod_disc_get_value_at ${i} id)
    name=$(build_mod_disc_get_value_at ${i} name)
    version=$(build_mod_disc_get_value_at ${i} version)

    if [[ ${result} -ne 0 ]] ; then return ; fi

    echo "    {" >> ${file_output}
    echo -n "      \"location\": \"${url_prefix}" >> ${file_output}
    build_mod_disc_build_field | sed -e 's|\.|-|g' >> ${file_output}
    echo "${url_suffix}\"," >> ${file_output}
    echo "      \"id\": \"${id}\"," >> ${file_output}
    echo "      \"name\": \"${name}\"," >> ${file_output}
    echo "      \"version\": \"${version}\"" >> ${file_output}
    echo -n "    }" >> ${file_output}

    let i++

    if [[ ${i} -lt ${total} ]] ; then
       echo "," >> ${file_output}
    else
      echo >> ${file_output}
    fi
  done

  echo "  ]" >> ${file_output}
  echo "}" >> ${file_output}
}

build_mod_disc_build_field() {

  if [[ ${field} == "id" ]] ; then
    echo -n "${id}"
  elif [[ ${field} == "name" ]] ; then
    echo -n "${name}"
  elif [[ ${field} == "version" ]] ; then
    echo -n "${version}"
  fi
}

build_mod_disc_get_value_at() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local index=${1}
  local key=${2}

  value=$(jq ".modules[${index}].${key}" ${file_input})

  let result=${?}

  if [[ ${result} -ne 0 ]] ; then return ${result} ; fi

  echo -n "${value}" | sed -e 's|"||g'
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

build_mod_disc_verify_json() {

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

build_mod_disc_verify_output() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ -e ${file_output} && ${file_force} -eq 0 ]] ; then
    echo "${p_e}The output file '${file_output} already exists."
    echo

    let result=1
  fi
}

main ${*}
