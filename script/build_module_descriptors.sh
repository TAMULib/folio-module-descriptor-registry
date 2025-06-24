#!/bin/bash
#
# Build module descriptors, synthetically.
#
# This attempts to directly build the module descriptor using the ModuleDescriptor-template.json, without calling the normal build process.
# This is done to avoid the resource and time cost of calling something like "mvn clean package -DskipTests".
#
# This utilizes the install.json file to construct the Module Descriptor JSON files.
#
# This requires the following user-space programs:
#   - bash
#   - file
#   - grep
#   - jq
#   - mkdir
#   - sed
#   - yarn
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_MOD_DESCRIPTORS_DEBUG may be specifically set to "json" to include printing the json commands.
# The BUILD_MOD_DESCRIPTORS_DEBUG may be specifically set to "json_only" to only print the json commands, disabling all other debugging.
# The BUILD_MOD_DESCRIPTORS_DEBUG may be specifically set to "yarn" to include running yarn in verbose mode.
# The BUILD_MOD_DESCRIPTORS_DEBUG may be specifically set to "yarn_only" to only include running yarn in verbose mode, disabling all other debugging (does not pass -v).
#

# TODO:
# https://github.com/search?q=org%3Afolio-org%20ModuleDescriptor-template.json&type=code
# https://github.com/folio-org/mod-inventory-storage/blob/36177285d3197407d773c0712c8209ebc39d3a4b/descriptors/ModuleDescriptor-template.json#
# https://github.com/folio-org/Net-Z3950-FOLIO/blob/master/descriptors/ModuleDescriptor-template.json
# https://github.com/folio-org/mod-workflow/blob/e30398c15ac8cda846a17d20b6f2279002bbfa3f/service/descriptors/ModuleDescriptor-template.json
# https://github.com/folio-org/folio-helm-v2/blob/1bcbb2fbf5d0db45de395f0e5267eb316ea0e6c9/scripts/modify-values.py
# https://github.com/folio-org/ui-workflow
# https://github.com/folio-org/edge-fqm/blob/dd5cba11f35f9742e0fa7052ac146b4d29854cc5/descriptors/ModuleDescriptor-template.json
# https://github.com/folio-org/mod-login/blob/14a9628fc7afb378a998b8968a349d285329bf13/descriptors/ModuleDescriptor-template.json
# https://github.com/folio-org/mod-pubsub/blob/master/descriptors/ModuleDescriptor-template.json
# Handle UI as well via stripe-cli or appropriate yarn build.
#   yarn run build-mod-descriptor

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local debug_yarn=
  local file=
  local files="install.json"
  local input_path="template/descriptor/module/"
  local input_path_jq=
  local input_path_map=
  local json=
  local map_names=
  local null="/dev/null"
  local omit="okapi"
  local output_path="descriptors/" # TODO: add flower release name.
  local restrict_to="edge- folio_ mod-"
  local restrict_to_regex=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -A maps_data_jq=

  local -i result=0

  build_mod_desc_load_environment ${*}
  build_mod_desc_load_templates

  for file in ${files} ; do
    build_mod_desc_build

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done

  return ${result}
}

build_mod_desc_build() {

  if [[ ${debug} == "" ]] ; then return ; fi

  local id=
  local json=
  local method=
  local name=
  local reduced_json=
  local type=
  local value=

  local -i i=0
  local -i total=0
  local -i skip=0

  build_mod_desc_build_reduce
  build_mod_desc_load_json_total "length" ${file} ${reduced_json}

  if [[ ${total} -eq 0 && ${debug} != "" ]] ; then
    echo "${p_d}No modules found in the input file: ${file} ."
  else
    echo "Operating on ${total} items in input file: ${file} ."
  fi

  echo

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_desc_load_json_for "[${i}].name" ${file} ${names} "-r"
    id="${value}"
    method=
    type=

    build_mod_desc_build_get_name
    build_mod_desc_build_get_version
    build_mod_desc_build_omit

    if [[ ${result} -ne 0 ]] ; then return ; fi
    if [[ ${skip} -eq 1 ]] ; then continue ; fi

    build_mod_desc_print_debug "Processing id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

    build_mod_desc_load_json "map" ${input_path_map}

    build_mod_desc_build_get_method_and_type ".exact.\"${name}\"" ${json}
    build_mod_desc_build_get_pcre
    build_mod_desc_build_operate

    let i++
  done
}

build_mod_desc_build_get_method_and_type() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local json=${2}
  local match=${1}

  build_mod_desc_load_json_for "${match}.method" ${input_path_map} ${json}
  method=${value}

  build_mod_desc_load_json_for "${match}.type" ${input_path_map} ${json}
  type=${value}
}

build_mod_desc_build_get_pcre() {

  if [[ ${result} -ne 0 || ( ${method} != "" && ${method} != "null" ) ]] ; then return ; fi

  local pcre_json=
  local pcre_name=
  local pcre_query=

  local -i i=0
  local -i matched=0
  local -i total=0

  build_mod_desc_load_json_for "pcre | keys" ${input_path_map} ${json}
  pcre_json=${value}

  build_mod_desc_load_json_total "length" ${input_path_map} ${pcre_json}

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" ${input_path_map} ${pcre_json} "-r"
    pcre_query=${value}

    build_mod_desc_build_get_pcre_match_query

    if [[ ${result} -ne 0 || ${matched} -ne 0 ]] ; then return ; fi

    let i++
  done
}

build_mod_desc_build_get_pcre_match_query() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ $(echo -n "${name}" | grep -shoP "${pcre_query}") != "" ]] ; then
    let matched=1

    build_mod_desc_build_get_method_and_type ".pcre.\"${pcre_query}\"" ${json}
  else
    let matched=0
  fi

  if [[ ${?} -eq 2 ]] ; then
    echo "${p_e}Failed to operate PCRE query '${pcre_query}' from maps file: ${input_path_map} (system code ${result})."
    echo

    let result=1
  else
    let result=0
  fi
}

build_mod_desc_build_get_name() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  name=$(echo -n ${value} | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||")

  build_mod_desc_handle_result "Failed to extract name from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 && ${name} == "" ]] ; then
    echo "${p_e}Empty name from key '${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
  fi
}

build_mod_desc_build_get_version() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  version=$(echo -n "${value}" | sed -e "s|^${name}-||g")

  build_mod_desc_handle_result "Failed to extract version from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 && ${version} == "" ]] ; then
    echo "${p_e}Empty version from key '${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
  fi
}

build_mod_desc_build_omit() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  let skip=0

  for value in ${omit} ; do
    if [[ ${value} == ${omit} ]] ; then
      build_mod_desc_print_debug "Skipping id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

      let skip=1
      break
    fi
  done
}

build_mod_desc_build_operate() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${method} == "jq" ]] ; then
    build_mod_desc_build_operate_jq
  elif [[ ${method} == "yarn" ]] ; then
    build_mod_desc_build_operate_yarn_build
    build_mod_desc_build_operate_yarn_copy
  else
    build_mod_desc_print_debug "Skipping id=${id} at index ${i} because method='${method}' is unknown"
  fi
}

build_mod_desc_build_operate_jq() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  echo "TODO"
}

build_mod_desc_build_operate_yarn_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  yarn ${debug_yarn} run build-mod-descriptor

  build_mod_desc_handle_result "Failed to execute yarn run build-mod-descriptor for: ${id}"
}

build_mod_desc_build_operate_yarn_copy() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  #cp ${debug} module-descriptor.json
  echo "TODO: copy module-descriptor.json to destination path"
}

build_mod_desc_build_reduce() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_restrict="sort | .[] | select(.id | test(\"${restrict_to_regex}\"))"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    if [[ ${restrict_to_regex} == "" ]] ; then
      reduced_json=$(jq -r -M . ${file})
    else
      reduced_json=$(jq -r -M "${jq_restrict}" ${file} | jq -s -M '.')
    fi
  else
    if [[ ${restrict_to_regex} == "" ]] ; then
      reduced_json=$(jq -r -M . ${file} 2> ${null})
    else
      reduced_json=$(jq -r -M "${jq_restrict}" ${file} 2> ${null} | jq -s -M '.' 2> ${null})
    fi
  fi

  build_mod_desc_handle_result "Failed to reduce using '${restrict_to}' for JSON: ${file}"
}

build_mod_desc_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_mod_desc_load_environment() {
  local file=
  local i=
  local simplified=

  if [[ ${BUILD_MOD_DESCRIPTORS_DEBUG} != "" ]] ; then
    debug="-v"
    debug_json=
    debug_yarn="-s"

    if [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "^\s*yarn\s*$") != "" ]] ; then
      debug_yarn="--verbose"
    elif [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "^\s*yarn_only\s*$") != "" ]] ; then
      debug=
      debug_yarn="--verbose"
    elif [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi

      if [[ $(echo ${BUILD_MOD_DESCRIPTORS_DEBUG} | grep -sho "\<yarn\>") != "" ]] ; then
        debug_yarn="--verbose"
      fi
    fi
  fi

  if [[ $(echo ${BUILD_MOD_DESCRIPTORS_FILES} | sed -e 's|\s||g') != "" ]] ; then
    files=

    for i in ${BUILD_MOD_DESCRIPTORS_FILES} ; do
      file=$(echo ${BUILD_MOD_DESCRIPTORS_FILES} | sed -e 's|//*|/|g' -e 's|/*$||')

      build_mod_desc_print_debug "Using File: ${file}"

      files="${files}${file} "
    done
  fi

  if [[ ${BUILD_MOD_DESCRIPTORS_INPUT_PATH} != "" ]] ; then
    input_path=$(echo -n ${BUILD_MOD_DESCRIPTORS_INPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  input_path_jq="${input_path}jq.json"
  input_path_map="${input_path}maps.json"

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DESCRIPTORS_RESTRICT_TO ]] ; then
    restrict_to=${BUILD_MOD_DESCRIPTORS_RESTRICT_TO}
  fi

  restrict_to_regex=

  if [[ ${restrict_to} != "" ]] ; then
    for i in ${restrict_to} ; do
      simplified=$(echo ${i} | grep -shoP "[\w-]*")

      if [[ ${simplified} != "" ]] ; then
        if [[ ${restrict_to_regex} == "" ]] ; then
          restrict_to_regex="^${simplified}"
        else
          restrict_to_regex="${restrict_to_regex}|^${simplified}"
        fi
      fi
    done
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DESCRIPTORS_OMIT ]] ; then
    omit=${BUILD_MOD_DESCRIPTORS_OMIT}
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DESCRIPTORS_OUTPUT_PATH ]] ; then
    if [[ ${BUILD_MOD_DESCRIPTORS_OUTPUT_PATH} == "" ]] ; then
      output_path=
    else
      output_path=$(echo -n ${BUILD_MOD_DESCRIPTORS_OUTPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    fi
  fi
}

build_mod_desc_load_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=${2}
  local name=${1}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    json=$(jq -M . ${file})
  else
    json=$(jq -M . ${file} 2> ${null})
  fi

  build_mod_desc_handle_result "Failed to load ${name} from ${file}"
}

build_mod_desc_load_json_for() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_select_by=${1}
  local json=${3}
  local name=${2}
  local args=${4}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(jq ${args} -M "${jq_select_by}" <<< ${json})
  else
    value=$(jq ${args} -M "${jq_select_by}" <<< ${json} 2> ${null})
  fi

  build_mod_desc_handle_result "Failed to load JSON with select='${jq_select_by}' and args='${args}' for ${name}"
}

build_mod_desc_load_json_total() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local data=
  local jq_total=${1}
  local json=${3}
  local name=${2}
  local raw=${4}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -r -M "${jq_total}" <<< ${json})
  else
    data=$(jq -r -M "${jq_total}" <<< ${json} 2> ${null})
  fi

  build_mod_desc_handle_result "Failed to load JSON length with select='${jq_total}' for ${name}"

  if [[ ${result} -eq 0 && ${data} != "" && ${data} != "null" ]] ; then
    let total=${data}
  else
    let total=0
  fi
}

build_mod_desc_load_json_verify_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=

  for file in ${files} ; do
    build_mod_desc_verify_json "input file" ${file}

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  build_mod_desc_verify_json "jq setting file" ${input_path_jq}
  build_mod_desc_verify_json "map setting file" ${input_path_map}
}

build_mod_desc_load_templates() {

  if [[ ${debug} == "" ]] ; then return ; fi

  local name=
  local names=
  local value=

  local -i i=0
  local -i total=0

  build_mod_desc_load_json_verify_files

  build_mod_desc_load_json "JQ map" ${input_path_jq}
  build_mod_desc_load_json_for "keys" ${input_path_jq} ${json}
  names=${value}

  build_mod_desc_load_json_total "length" ${input_path_jq} ${names}

  while [[ ${i} -lt ${total} ]] ; do

    build_mod_desc_load_json_for "[${i}]" ${input_path_jq} ${names} "-r"
    name=${value}

    build_mod_desc_load_json_for ".\"${name}\"" ${input_path_jq} ${json} "-r"
    maps_data_jq["${name}"]=${value}

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

build_mod_desc_load_templates_jq_get() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_keys="keys"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    names=$(jq -M "${jq_keys}" <<< ${json})
  else
    names=$(jq -M "${jq_keys}" <<< ${json} 2> ${null})
  fi

  build_mod_desc_handle_result "Failed to load JQ map names from ${input_path_jq}"
}

build_mod_desc_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_mod_desc_verify_json() {

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
