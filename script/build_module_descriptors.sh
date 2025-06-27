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
#   - git
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
  local checkout_path="checkout/"
  local debug=
  local debug_json=
  local debug_yarn=
  local default_branch=
  local default_repository="https://github.com/folio-org/"
  local deploy_descriptor="DeploymentDescriptor-template.json"
  local file=
  local files="install.json"
  local flower="snapshot"
  local input_path="template/descriptor/"
  local input_path_jq=
  local input_path_map=
  local json=
  local map_json=
  local map_names=
  local module_descriptor="ModuleDescriptor-template.json"
  local null="/dev/null"
  local output_path="descriptors/"
  local output_path_deploy=
  local output_path_flower=
  local output_path_module=
  local restrict_to="edge- folio_ mod-"
  local restrict_to_regex=
  local yarn_cache="cache/yarn/" # TODO: add env var configuration.

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -A maps_data_jq=
  local -A maps_keys_jq=
  local -A maps_size_jq=

  local -i map_names_length=0
  local -i pcre_matched=0
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

  local branch=
  local destination_deploy=
  local destination_module=
  local id=
  local into_path=
  local json=
  local method=
  local module=
  local module_raw=
  local module_type=
  local original_path="${PWD}/"
  local pcre_key=".pcre"
  local pcre_value=
  local reduced_json=
  local repository=
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
    method=
    repository=
    type=

    let skip=0

    build_mod_desc_build_get_id
    build_mod_desc_build_get_module
    build_mod_desc_build_get_version

    # Alter ID based on possibly modified module name and version.
    id="${module}-${version}"

    build_mod_desc_build_rename
    build_mod_desc_build_omit
    build_mod_desc_build_skip_unknown

    if [[ ${result} -ne 0 ]] ; then return ; fi

    if [[ ${skip} -eq 1 ]] ; then
      let i++;
      continue
    fi

    destination_deploy="${output_path_deploy}${id}.json"
    destination_module="${output_path_module}${id}.json"

    branch="${default_branch}"
    into_path="${checkout_path}${module}/"

    let skip=0
    if [[ -f ${destination_module} ]] ; then
      if [[ -f ${destination_deploy} || $(grep -sho "^folio_" <<< ${module_raw}) != "" ]] ; then
        let skip=1
      else
        build_mod_desc_print_debug "Module Descriptor found, but deployment descriptor was not for: ${id}"
      fi
    fi

    if [[ ${skip} -eq 1 ]] ; then
      build_mod_desc_print_debug "Descriptors found, skipping id=${id}, module=${module}, version=${version} at index ${i} of ${total}"
    else
      build_mod_desc_print_debug "Processing id=${id}, module=${module}, version=${version} at index ${i} of ${total}"

      build_mod_desc_build_get_map_data ".exact.\"${module_raw}\"" "${map_json}"

      if [[ ${method} == "" ]] ; then
        build_mod_desc_build_get_map_pcre "${pcre_key}" "${map_json}"
        build_mod_desc_build_get_map_pcre_match_module "${pcre_key}" "${map_json}"

        if [[ ${pcre_matched} -eq 1 ]] ; then
          method=${value}

          let pcre_matched=0
        fi
      fi

      build_mod_desc_build_clone
      build_mod_desc_build_operate
      build_mod_desc_build_cleanup
    fi

    let i++
  done
}

build_mod_desc_build_clone() {

  if [[ ${result} -ne 0 || -d ${into_path} ]] ; then return ; fi

  if [[ ${branch} == "" ]] ; then
    git clone ${debug} --depth 1 --no-tags "${repository}" "${into_path}"
  else
    git clone ${debug} -b "${branch}" --depth 1 --no-tags "${repository}" "${into_path}"
  fi

  build_mod_desc_handle_result "Failed to clone repository ${module} using branch '${branch}' into path '${into_path}' for repository: ${repository}"

  # Add a new line to make the logs easier to read when removing verbosely.
  if [[ ${result} -eq 0 && ${debug} != "" ]] ; then
    echo
  fi
}

build_mod_desc_build_cleanup() {

  if [[ ${result} -ne 0 || ${into_path} == "" || ${into_path} == "/" || ${into_path} == "." || ${into_path} == "./" ]] ; then return ; fi
  if [[ ${into_path} == ".." || ${into_path} == "../" || "${PWD}/" != ${original_path} ]] ; then return ; fi

  if [[ -d ${into_path} ]] ; then
    rm ${debug} -Rf "${into_path}"

    # Ignore remove failures.
    let result=${?}

    # Add a new line to make the logs easier to read when removing verbosely.
    if [[ ${debug} != "" ]] ; then
      echo
    fi

    if [[ ${result} -ne 0 ]] ; then
      build_mod_desc_print_debug "Failed to recursively remove directory for ${module} (system code ${result}): ${into_path}"

      let result=0
    fi
  fi
}

build_mod_desc_build_get_id() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=".[${i}].id"

  build_mod_desc_load_json_for "${key}" "${file}" "${reduced_json}" "-r"
  id="${value}"

  if [[ ${result} -eq 0 && ${id} == "" ]] ; then
    echo "${p_e}Empty id for key='${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
    return
  fi
}

build_mod_desc_build_get_map_data() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local json=${2}
  local match=${1}
  local repo_type=

  build_mod_desc_load_json_for "${match}.repository.branch" "${input_path_map}" "${json}" "-r" yes

  if [[ ${value} != "null" ]] ; then
    branch=${value}
  fi

  build_mod_desc_load_json_for "${match}.method" "${input_path_map}" "${json}" "-r"

  if [[ ${value} != "" ]] ; then
    method=${value}
  fi

  build_mod_desc_load_json_for "${match}.repository.type" "${input_path_map}" "${json}" "-r"

  if [[ ${value} != "" ]] ; then
    repo_type=${value}
  fi

  build_mod_desc_load_json_for "${match}.repository.url" "${input_path_map}" "${json}" "-r"

  if [[ ${value} == "" ]] ; then
    repository=${default_repository}${module}
  else
    if [[ ${repo_type} == "partial" ]] ; then
      repository=${value}${module}
    elif [[ ${repo_type} == "full" || ${repo_type} == "" ]] ; then
      repository=${value}
    fi
  fi

  build_mod_desc_load_json_for "${match}.type" "${input_path_map}" "${json}" "-r"

  if [[ ${value} != "" ]] ; then
    type=${value}

    if [[ ${maps_data_jq["${type}"]} == "" ]] ; then
      echo "${p_e}Unknown JQ type of '${type}' for: ${input_path_jq} ."
      echo

      let result=1
      return
    fi
  fi
}

build_mod_desc_build_get_map_pcre() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local json=${3}
  local pcre_json=
  local section=${1}

  local -i i=0
  local -i total=0

  pcre_value=

  let pcre_matched=0

  build_mod_desc_load_json_for "${section} | keys" "${input_path_map}" "${json}"
  pcre_json=${value}

  build_mod_desc_load_json_total "length" "${input_path_map}" "${pcre_json}"

  while [[ ${i} -lt ${total} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" "${input_path_map}" "${pcre_json}" "-r"
    pcre_value=${value}

    if [[ ${pcre_value} != "" && $(echo -n "${module_raw}" | grep -shoP "${pcre_value}") != "" ]] ; then
      let pcre_matched=1
    fi

    if [[ ${result} -ne 0 || ${pcre_matched} -eq 1 ]] ; then return ; fi

    let i++
  done
}

build_mod_desc_build_get_map_pcre_match_module() {

  if [[ ${result} -ne 0 || ${pcre_matched} -ne 1 ]] ; then return ; fi

  local json=${2}
  local section=${1}

  build_mod_desc_build_get_map_data "${section}.\"${pcre_value}\"" "${json}"
}

build_mod_desc_build_get_map_pcre_match_value() {

  if [[ ${result} -ne 0 || ${pcre_matched} -ne 1 ]] ; then return ; fi

  local json=${3}
  local section=${1}
  local subsection=${2}

  build_mod_desc_load_json_for "${section}.\"${pcre_value}\"${subsection}" "${input_path_map}" "${json}" "-r"
}

build_mod_desc_build_get_module() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${id} == "" ]] ; then
    echo "${p_e}Empty id at index ${i} from JSON: ${file} ."
    echo

    let result=1
    return
  fi

  module=
  module_type=
  module_raw=$(echo -n "${id}" | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||")

  build_mod_desc_handle_result "Failed to extract module name from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 ]] ; then
    if [[ $(grep -sho "^folio_" <<< ${module_raw}) == "" ]] ; then
      module=${module_raw}
      module_type="normal"
    else
      module=$(sed -e "s|^folio_|ui-|" <<< ${module_raw})
      module_type="ui"
    fi

    if [[ ${module_raw} == "" ]] ; then
      echo "${p_e}Empty module name from key '${id}' at index ${i} from JSON: ${file} ."
      echo

      let result=1
    fi
  fi
}

build_mod_desc_build_get_version() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  version=$(echo -n "${id}" | sed -e "s|^${module_raw}-||g")

  build_mod_desc_handle_result "Failed to extract version from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 && ${version} == "" ]] ; then
    echo "${p_e}Empty version from key '${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
  fi
}

build_mod_desc_build_omit() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=".override.omit.pcre"
  local omit=
  local subsection=".type"

  build_mod_desc_load_json_for ".override.omit.exact.\"${module}\"${subsection}" "${input_path_map}" "${map_json}" "-r"
  omit=${value}

  if [[ ${omit} == "" ]] ; then
    build_mod_desc_build_get_map_pcre "${key}" "${map_json}"
    build_mod_desc_build_get_map_pcre_match_value "${key}" "${subsection}" "${map_json}"

    if [[ ${pcre_matched} -eq 1 ]] ; then
      omit=${value}

      let pcre_matched=0
    fi
  fi

  if [[ ${omit} == "always" ]] ; then
    build_mod_desc_print_debug "Skipping id=${id}, module=${module}, version=${version} at index ${i} of ${total}"

    let skip=1
  fi
}

build_mod_desc_build_operate() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local source_module="${into_path}descriptors/${module_descriptor}"
  local source_deploy="${into_path}descriptors/${deploy_descriptor}"

  if [[ ${method} == "jq" ]] ; then
    build_mod_desc_build_operate_jq_find module "${source_module}" "${module_descriptor}" "${destination_module}"
    build_mod_desc_build_operate_jq_find deploy "${source_deploy}" "${deploy_descriptor}" "${destination_deploy}"

    build_mod_desc_build_operate_jq_build module "${source_module}" "${destination_module}"
    build_mod_desc_build_operate_jq_build deploy "${source_deploy}" "${destination_deploy}" yes
  elif [[ ${method} == "yarn" ]] ; then
    build_mod_desc_build_operate_yarn_change_into
    #build_mod_desc_build_operate_yarn_install
    build_mod_desc_build_operate_yarn_build
    build_mod_desc_build_operate_yarn_copy

    # Always change back to the original path regardless of the error state.
    cd ${original_path}
  else
    build_mod_desc_print_debug "Skipping id=${id} at index ${i} because method='${method}' is unknown"
  fi
}

build_mod_desc_build_operate_jq_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local destination=${3}
  local key=
  local kind=${1}
  local optional=${4}
  local source=${2}
  local with=

  local -i i=0
  local -i maps_total=${maps_size_jq[${type}]}

  # Skip already created descriptors.
  if [[ -f ${destination} ]] ; then return ; fi

  if [[ ${optional} != "" && ! -e ${source} ]] ; then
    build_mod_desc_print_debug "Skipping missing ${kind} descriptor due to being optional: ${source}"
    return
  fi

  build_mod_desc_load_json "${kind} descriptor template" "${source}"

  while [[ ${i} -lt ${maps_total} ]] ; do
    build_mod_desc_load_json_for ".[${i}]" "Template Key for '${type}' at ${i}" "${maps_keys_jq[${type}]}" "-r"
    key=${value}

    build_mod_desc_load_json_for ".\"${key}\"" "Template Value for '${type}' at ${i}" "${maps_data_jq[${type}]}" "-r"
    with=${value}

    build_mod_desc_build_operate_jq_build_sed

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done

  build_mod_desc_build_operate_jq_build_write
}

build_mod_desc_build_operate_jq_build_sed() {

  if [[ ${result} -ne 0 || ${key} == "" ]] ; then return ; fi

  local data=
  local value=

  if [[ ${with} == "description" ]] ; then
    # There is no value in the install.json for description, so always evaluate to an empty string.
    value=
  elif [[ ${with} == "id" ]] ; then
    value=${id}
  elif [[ ${with} == "module" ]] ; then
    value=${module}
  elif [[ ${with} == "version" ]] ; then
    value=${version}
  else
    build_mod_desc_print_debug "Unknown type identifier while processing ${module} with key='${key}': ${with}"

    return
  fi

  data=$(sed -e "s|${key}|${value}|g" <<< ${json})

  build_mod_desc_handle_result "Failed to replace '${key}' with ${with} '${value}' using sed for: ${module}"

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

  build_mod_desc_handle_result "Failed to write ${module} ${kind} descriptor to: ${destination}"
}

build_mod_desc_build_operate_jq_find() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local destination=${4}
  local expect_at=${2}
  local find_file=${3}
  local found_at=
  local kind=${1}

  if [[ -e ${expect_at} && ! -f ${expect_at} ]] ; then
    build_mod_desc_print_debug "The ${kind} descriptor for ${module} is not a valid JSON file: ${expect_at}"

    return
  fi

  build_mod_desc_build_operate_jq_find_search
  build_mod_desc_build_operate_jq_find_assign
}

build_mod_desc_build_operate_jq_find_assign() {

  if [[ ${result} -ne 0 || ${found_at} == "" || ! -f ${found_at} ]] ; then return ; fi

  if [[ ${kind} == "module" ]] ; then
    source_module=${found_at}
  else
    source_deploy=${found_at}
  fi
}

build_mod_desc_build_operate_jq_find_search() {

  if [[ ${result} -ne 0 || -f ${expect_at} ]] ; then return ; fi

  found_at=$(find ${into_path} -name ${find_file} -print -quit)

  build_mod_desc_handle_result "Failed to find the ${kind} descriptor file for ${module}: ${find_file}"
}

build_mod_desc_build_operate_yarn_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  yarn ${debug_yarn} run build-mod-descriptor

  build_mod_desc_handle_result "Failed to execute yarn run build-mod-descriptor for: ${id}"
}

build_mod_desc_build_operate_yarn_change_into() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  cd ${into_path}

  build_mod_desc_handle_result "Failed to change to directory for ${module}: ${into_path}"
}

build_mod_desc_build_operate_yarn_copy() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local destination="${original_path}${output_path_module}${id}.json"
  local source="module-descriptor.json"

  cp ${debug} "${source}" "${destination}"

  build_mod_desc_handle_result "Failed to copy '${source}' to: ${destination}"

  # Add a new line to make the logs easier to read when removing verbosely.
  if [[ ${result} -eq 0 && ${debug} != "" ]] ; then
    echo
  fi
}

build_mod_desc_build_operate_yarn_install() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  YARN_CACHE_FOLDER="${original_path}${yarn_cache}" yarn ${debug_yarn} install

  build_mod_desc_handle_result "Failed to execute yarn install for: ${id}"
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

build_mod_desc_build_rename() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=".override.rename.pcre"
  local to=
  local subsection=".to"

  build_mod_desc_load_json_for ".override.rename.exact.\"${module}\"${subsection}" "${input_path_map}" "${map_json}" "-r"
  to=${value}

  if [[ ${omit} == "" ]] ; then
    build_mod_desc_build_get_map_pcre "${key}" "${map_json}"
    build_mod_desc_build_get_map_pcre_match_value "${key}" "${subsection}" "${map_json}"

    if [[ ${pcre_matched} -eq 1 ]] ; then
      to=${value}

      let pcre_matched=0
    fi
  fi

  if [[ ${to} != "" ]] ; then
    module=${to}
  fi
}

build_mod_desc_build_skip_unknown() {

  if [[ ${result} -ne 0 || ${skip} -ne 0 || ${type} == "" ]] ; then return ; fi

  echo "checking for type $type is: ${maps_data_jq[${type}]}".

  if [[ ${maps_data_jq[${type}]} == "" ]] ; then
    build_mod_desc_print_debug "Skipping unknown type='${type}' for id=${id}, module=${module}, version=${version} at index ${i} of ${total}"

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

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DEFAULT_BRANCH ]] ; then
    default_branch=${BUILD_MOD_DEFAULT_BRANCH}
  fi

  if [[ $(echo -n "${default_branch}" | grep -sho "[/\\\"\']") != "" ]] ; then
    echo "${p_e}The default branch must not contain '/', '\', ''', or '\"' characters: ${default_branch} ."

    let result=1
    return
  fi

  if [[ ${BUILD_MOD_DEFAULT_REPOSITORY} != "" ]] ; then
    default_repository=$(echo -n ${BUILD_MOD_DEFAULT_REPOSITORY} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
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

  if [[ ${BUILD_MOD_DESCRIPTORS_FLOWER} != "" ]] ; then
    flower=$(echo ${BUILD_MOD_DESCRIPTORS_FLOWER} | sed -e 's|/||g')
  fi

  if [[ $(echo -n ${flower} | grep -sho "[/\\\"\']") != "" ]] ; then
    echo "${p_e}The flower must not contain '/', '\', ''', or '\"' characters: ${flower} ."

    let result=1
    return
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

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_MOD_DESCRIPTORS_CHECKOUT_PATH ]] ; then
    if [[ ${BUILD_MOD_DESCRIPTORS_CHECKOUT_PATH} == "" ]] ; then
      checkout_path=
    else
      checkout_path=$(echo -n ${BUILD_MOD_DESCRIPTORS_CHECKOUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    fi
  fi

  build_mod_desc_verify_directory "check out path" "${checkout_path}" create
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

  local args=${4}
  local jq_select_by=${1}
  local json=${3}
  local keep_null=${5}
  local name=${2}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(jq ${args} -M "${jq_select_by}" <<< ${json})
  else
    value=$(jq ${args} -M "${jq_select_by}" <<< ${json} 2> ${null})
  fi

  build_mod_desc_handle_result "Failed to load JSON with select='${jq_select_by}', args='${args}', and keep_null='${keep_null}' for ${name}"

  # JQ returns the literal "null" for not found, replace with empty string.
  if [[ ${keep_null} == "" && ${value} == "null" ]] ; then
    value=
  fi
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
  local names=
  local type=
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
    type=${value}

    build_mod_desc_load_json_for ".\"${type}\"" "${input_path_jq}" "${json}" "-r"
    maps_data_jq["${type}"]=${value}

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
    type=${value}

    # Ignore the reserved key.
    if [[ ${type} == "all" ]] ; then
      let i++
      continue;
    fi

    build_mod_desc_load_json_for "${jq_merge}" "${input_path_jq}" "${json}"
    maps_data_jq[${type}]=${value}

    build_mod_desc_load_json_for "keys" "${input_path_jq}" "${maps_data_jq[${type}]}"
    maps_keys_jq[${type}]=${value}

    build_mod_desc_load_json_total "length" "${input_path_jq}" "${maps_keys_jq[${type}]}"
    maps_size_jq[${type}]=${total}

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done

  build_mod_desc_load_json_for "${jq_merge}" "${input_path_jq}" "${json}"
  maps_data_jq[all]=${value}

  build_mod_desc_load_json_for "keys" "${input_path_jq}" "${maps_data_jq[all]}"
  maps_keys_jq[all]=${value}

  build_mod_desc_load_json_total "length" "${input_path_jq}" "${maps_keys_jq[all]}"
  maps_size_jq[all]=${total}

  build_mod_desc_load_json "map" "${input_path_map}"
  map_json=${json}
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
      mkdir -p ${debug} "${path}"

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
