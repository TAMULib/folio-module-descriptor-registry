#!/bin/bash
#
# Build module and deployment descriptors, either synthetically or normally.
#
# This attempts to directly build the module descriptor using the ModuleDescriptor-template.json, without calling the normal build process.
# This is done to avoid the resource and time cost of calling something like "mvn clean package -DskipTests".
#
# This utilizes the install.json file to construct the Module Descriptor JSON files.
#
# This requires the following user-space programs:
#   - bash
#   - file
#   - find
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

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local debug_yarn=
  local deploy_descriptor="DeploymentDescriptor-template.json"
  local file=
  local files="install.json"
  local flower="snapshot"
  local input_path="template/descriptor/"
  local input_path_jq=
  local input_path_map=
  local json=
  local map_names=
  local module_descriptor="ModuleDescriptor-template.json"
  local null="/dev/null"
  local omit="okapi"
  local output_path="descriptors/"
  local output_path_deploy=
  local output_path_flower=
  local output_path_module=
  local restrict_to="edge- folio_ mod-"
  local restrict_to_regex=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -A maps_data_jq=
  local -A maps_keys_jq=
  local -A maps_size_jq=

  local -i map_names_length=0
  local -i result=0

  build_mod_desc_load_environment ${*}
  build_mod_desc_load_templates

  for file in ${files} ; do
    build_mod_desc_build

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done

  if [[ ${result} -eq 0 ]] ; then
    echo
    echo "Done: Module and Deployment Descriptor JSON files are built ."
  fi

  return ${result}
}

build_mod_desc_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local deploy_desc=
  local id=
  local json=
  local method=
  local module_desc=
  local name=
  local reduced_json=
  local type=
  local value=

  local -i i=0
  local -i total=0
  local -i skip=0

  build_mod_desc_build_reduce
  build_mod_desc_load_json_total "length" "${file}" "${reduced_json}"

  if [[ ${total} -eq 0 && ${debug} != "" ]] ; then
    echo "${p_d}No modules found in the input file: ${file} ."
  else
    echo "Operating on ${total} items in input file: ${file} ."
  fi

  echo

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_desc_load_json_for "[${i}].name" "${file}" "${names}" "-r"
    id="${value}"
    method=
    type=

    build_mod_desc_build_get_name
    build_mod_desc_build_get_version
    build_mod_desc_build_omit
    build_mod_desc_build_skip_unknown

    if [[ ${result} -ne 0 ]] ; then return ; fi

    if [[ ${skip} -eq 1 ]] ; then
      let i++;
      continue
    fi

    deploy_desc=${output_path_deploy}${name}
    module_desc=${output_path_module}${name}

    if [[ -f ${deploy_desc} && -f ${module_desc} ]] ; then
      build_mod_desc_print_debug "Descriptors found, skipping id=${id}, name=${name}, version=${version} at index ${i} of ${total}"
    else
      build_mod_desc_print_debug "Processing id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

      build_mod_desc_load_json "map" ${input_path_map}

      build_mod_desc_build_get_method_and_type ".exact.\"${name}\"" "${json}"
      build_mod_desc_build_get_pcre
      build_mod_desc_build_operate
    fi

    let i++
  done
}

build_mod_desc_build_get_method_and_type() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local json=${2}
  local match=${1}

  build_mod_desc_load_json_for "${match}.method" "${input_path_map}" "${json}"
  method=${value}

  build_mod_desc_load_json_for "${match}.type" "${input_path_map}" "${json}"
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

  build_mod_desc_load_json_for "pcre | keys" "${input_path_map}" "${json}"
  pcre_json=${value}

  build_mod_desc_load_json_total "length" "${input_path_map}" "${pcre_json}"

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" "${input_path_map}" "${pcre_json}" "-r"
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

  local source_module="descriptors/${module_descriptor}"
  local source_deploy="descriptors/${deploy_descriptor}"

  if [[ ${method} == "jq" ]] ; then
    build_mod_desc_build_operate_jq_find module "${source_module}" "${module_descriptor}"
    build_mod_desc_build_operate_jq_find deploy "${source_deploy}" "${deploy_descriptor}"

    build_mod_desc_build_operate_jq_build module "${source_module}" "${module_descriptor}"
    build_mod_desc_build_operate_jq_build deploy "${source_deploy}" "${deploy_descriptor}"
  elif [[ ${method} == "yarn" ]] ; then
    build_mod_desc_build_operate_yarn_build
    build_mod_desc_build_operate_yarn_copy
  else
    build_mod_desc_print_debug "Skipping id=${id} at index ${i} because method='${method}' is unknown"
  fi
}

build_mod_desc_build_operate_jq_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local destination=
  local file=${2}
  local name=${3}
  local key=
  local kind=${1}
  local with=

  local -i i=0
  local -i maps_total=${maps_size_jq["${type}"]}

  if [[ ${kind} == "module" ]] ; then
    destination=${module_desc}
  else
    destination=${deploy_desc}
  fi

  # Skip already created descriptors.
  if [[ -f ${module_desc} ]] ; then return ; fi

  build_mod_desc_load_json "${kind} descriptor template" ${file}

  while [[ ${i} -lt ${maps_total} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" "Template Key for '${type}' at ${i}" "${maps_keys_jq["${type}"]}" "-r"
    key=${value}

    build_mod_desc_load_json_for ".\"${key}\"" "Template Value for '${type}' at ${i}" "${maps_data_jq["${type}"]}" "-r"
    with=${value}

    build_mod_desc_build_operate_jq_build_sed

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  build_mod_desc_build_operate_jq_build_write
}

build_mod_desc_build_operate_jq_build_sed() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local data=

  data=$(sed -e "s|${key}|${with}|g" <<< ${json})

  build_mod_desc_handle_result "Failed to replace '${key}' with '${with}' using sed for: ${name}"

  if [[ ${result} -eq 0 ]] ; then
    json=${data}
  fi
}

build_mod_desc_build_operate_jq_build_write() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq -M . <<< ${json} > ${destination}
  else
    jq -M . <<< ${json} > ${destination} 2> ${null}
  fi

  build_mod_desc_handle_result "Failed to write ${name} ${kind} descriptor to: ${destination}"
}

build_mod_desc_build_operate_jq_find() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local data=
  local file=${2}
  local name=${3}
  local kind=${1}

  if [[ ! -e ${file} && ! -f ${file} ]] ; then
    echo "${p_e}The following path is not a valid file: ${file} ."

    let result=1
    return
  fi

  build_mod_desc_build_operate_jq_find_search
  build_mod_desc_build_operate_jq_find_assign
}

build_mod_desc_build_operate_jq_find_assign() {

  if [[ ${result} -ne 0 || ${data} == "" || ! -f ${data} ]] ; then return ; fi

  if [[ ${kind} == "module" ]] ; then
    source_module=${data}
  else
    source_deploy=${data}
  fi
}

build_mod_desc_build_operate_jq_find_search() {

  if [[ ${result} -ne 0 || -f ${file} ]] ; then return ; fi

  data=$(find -name ${name} -print -quit)

  build_mod_desc_handle_result "Failed to find the ${kind} descriptor file: ${name}"
}

build_mod_desc_build_operate_yarn_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  yarn ${debug_yarn} run build-mod-descriptor

  build_mod_desc_handle_result "Failed to execute yarn run build-mod-descriptor for: ${id}"
}

build_mod_desc_build_operate_yarn_copy() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local source="module-descriptor.json"

  cp ${debug} ${source} ${output_path_flower}

  build_mod_desc_handle_result "Failed to copy '${source}' to: ${output_path_flower}"
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

build_mod_desc_build_skip_unknown() {

  if [[ ${result} -ne 0 || ${skip} -ne 0 || ${type} == "" ]] ; then return ; fi

  if [[ ${maps_data_jq["${type}"]} == "" ]] ; then
    build_mod_desc_print_debug "Skipping unknown type='${type}' for id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

    let skip=1
  fi
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

  if [[ ${BUILD_MOD_DESCRIPTORS_FLOWER} != "" ]] ; then
    flower=$(echo ${BUILD_MOD_DESCRIPTORS_FLOWER} | sed -e 's|/||g')
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DESCRIPTORS_OUTPUT_PATH ]] ; then
    if [[ ${BUILD_MOD_DESCRIPTORS_OUTPUT_PATH} == "" ]] ; then
      output_path=
    else
      output_path=$(echo -n ${BUILD_MOD_DESCRIPTORS_OUTPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    fi
  fi

  if [[ ${flower} != "" ]] ; then
    output_path_flower="${output_path}${flower}/"
  else
    output_path_flower="${output_path}"
  fi

  output_path_deploy="${output_path_flower}deploy/"
  output_path_module="${output_path_flower}module/"

  build_mod_desc_verify_directory "output deploy path" "${output_path_deploy}" create
  build_mod_desc_verify_directory "output module path" "${output_path_module}" create
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
    build_mod_desc_verify_json "input file" "${file}"

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  build_mod_desc_verify_json "jq setting file" "${input_path_jq}"
  build_mod_desc_verify_json "map setting file" "${input_path_map}"
}

build_mod_desc_load_templates() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_merge='reduce .[] as $f ({}; . * $f)'
  local name=
  local names=
  local value=

  local -i i=0
  local -i total=0

  build_mod_desc_load_json_verify_files

  build_mod_desc_load_json "JQ map" "${input_path_jq}"
  build_mod_desc_load_json_for "keys" "${input_path_jq}" "${json}"
  names=${value}

  build_mod_desc_load_json_total "length" "${input_path_jq}" "${names}"

  while [[ ${i} -lt ${total} ]] ; do

    build_mod_desc_load_json_for ".[${i}]" "${input_path_jq}" "${names}" "-r"
    name=${value}

    build_mod_desc_load_json_for ".\"${name}\"" "${input_path_jq}" "${json}" "-r"
    maps_data_jq["${name}"]=${value}

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done

  build_mod_desc_load_json_for "keys" "${input_path_jq}" "${json}"
  map_names=${value}

  build_mod_desc_load_json_total "length" "${input_path_jq}" "${json}"
  map_names_length=${total}

  let i=0
  while [[ ${i} -lt ${map_names_length} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" "${input_path_jq}" "${map_names}"
    name=${value}

    # Ignore the reserved key.
    if [[ ${name} == "all" ]] ; then
      let i++
      continue;
    fi

    build_mod_desc_load_json_for "${jq_merge}" "${input_path_jq}" "${json}"
    maps_data_jq["${name}"]=${value}

    build_mod_desc_load_json_for "keys" "${input_path_jq}" "${maps_data_jq["${name}"]}"
    maps_keys_jq["${name}"]=${value}

    build_mod_desc_load_json_total "length" "${input_path_jq}" "${maps_keys_jq["${name}"]}"
    maps_size_jq["${name}"]=${total}

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done

  build_mod_desc_load_json_for "${jq_merge}" "${input_path_jq}" "${json}"
  maps_data_jq["all"]=${value}

  build_mod_desc_load_json_for "keys" "${input_path_jq}" "${maps_data_jq["all"]}"
  maps_keys_jq["all"]=${value}

  build_mod_desc_load_json_total "length" "${input_path_jq}" "${maps_keys_jq["all"]}"
  maps_size_jq["all"]=${total}
}

build_mod_desc_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_mod_desc_verify_directory() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local path=${2}
  local option=${3}

  # Optionally attempt create the directory if it does not exist.
  if [[ ${option} == "create" ]] ; then
    if [[ ! -e ${path} ]] ; then
      mkdir -p ${debug} ${path}

      build_mod_desc_handle_result "Failed to create the ${name} directory: ${path}"

      if [[ ${result} -ne 0 ]] ; then return ; fi
    fi
  fi

  if [[ ! -d ${path} ]] ; then
    echo "${p_e}The ${name} is not a valid directory: ${path} ."

    let result=1
  fi
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
