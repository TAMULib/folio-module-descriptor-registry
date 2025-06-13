#!/bin/bash
#
# Build the Application Descriptor JSON file for use when building the Module Discovery in situations where there is no existing Application Descriptor JSON file.
#
# This is primarily needed in legacy OKAPI cases and should not be needed in a Eureka environment.
# In the Eureka environment the Application Descriptor JSON files should already be provided.
#
# This utilizes the install.json file to construct the Application Descriptor JSON file.
#
# NOTE: This does not build a complete and proper Eureka Application Descriptor JSON file.
#       Instead, this builds the bare minimal needed to construct a Module Discovery JSON file.
#
# This requires the following user-space programs:
#   - bash
#   - date (optional, used if available)
#   - grep
#   - jq
#   - mkdir
#   - sed
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_APP_DESCRIPTOR_DEBUG may be specifically set to "json" to include printing the JSON files.
# The BUILD_APP_DESCRIPTOR_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local descriptor_name="application"
  local descriptor_version="0.0.0-SNAPSHOT"
  local files="install.json"
  local null="/dev/null"
  local output_path=
  local output_path_json=
  local output_path_name=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i file_force=0
  local -i result=0

  build_app_desc_load_environment ${*}

  build_app_desc_verify_files

  build_app_desc_build

  return ${result}
}

build_app_desc_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local description="Generated application descriptor"
  local file=
  local json="{"

  if [[ $(type -p date) != "" ]] ; then
    description="${description} on $(date -u)."
  else
    description="."
  fi

  json="${json} \"id\": \"${descriptor_name}-${descriptor_version}\","
  json="${json} \"name\": \"${descriptor_name}\","
  json="${json} \"version\": \"${descriptor_version}\", "
  json="${json} \"description\": \"${description}\", "
  json="${json} \"modules\": ["

  local -i first=1

  for file in ${files} ; do
    build_app_desc_build_file

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let first=0
  done

  json="${json} ] }"

  build_app_desc_build_write

  if [[ ${result} -ne 0 ]] ; then return ; fi

  echo
  echo "Done: Application Descriptor JSON built: ${output_path_json} ."
}

build_app_desc_build_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key="id"
  local id=
  local name=
  local value=
  local version=

  local -i i=0
  local -i total=0

  build_app_desc_build_total

  if [[ ${total} -eq 0 && ${debug} != "" ]] ; then
    echo "${p_d}No modules found in the input file: ${file} ."
  else
    echo "Operating on ${total} items in input file: ${file} ."
  fi

  echo

  while [[ ${i} -lt ${total} ]] ; do
    build_app_desc_get_load
    build_app_desc_get_name
    build_app_desc_get_version

    if [[ ${result} -ne 0 ]] ; then return ; fi

    id="${name}-${version}"

    build_app_desc_print_debug "Processing id=${id}, name=${name}, version=${version} at index ${i} of ${total}"

    if [[ ${first} -eq 0 ]] ; then
      json="${json}, "
    fi

    json="${json} { \"id\": \"${id}\", \"name\": \"${name}\", \"version\": \"${version}\" }"

    let i++

    if [[ ${i} -lt ${total} ]] ; then
      json="${json}, "
    fi
  done
}

build_app_desc_build_total() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_total="length"
  local data=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -r -M "${jq_total}" ${file})
  else
    data=$(jq -r -M "${jq_total}" ${file} 2> ${null})
  fi

  build_app_desc_handle_result "Failed to load array length from JSON: ${file}"

  if [[ ${result} -eq 0 && ${data} != "" && ${data} != "null" ]] ; then
    let total=${data}
  fi
}

build_app_desc_build_write() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq . > ${output_path_json} <<< ${json}
  else
    jq . > ${output_path_json} <<< ${json} 2> ${null}
  fi

  build_app_desc_handle_result "Failed to write to the output JSON file: ${output_path_json}"
}

build_app_desc_get_load() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_key=".[${i}].${key}"
  local data=

  name=
  version=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(jq -r -M "${jq_key}" ${file})
  else
    value=$(jq -r -M "${jq_key}" ${file} 2> ${null})
  fi

  build_app_desc_handle_result "Failed to load key '${key}' at index '${i}' from JSON: ${file}"
}

build_app_desc_get_name() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  name=$(echo -n ${value} | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||")

  build_app_desc_handle_result "Failed to extract name from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 && ${name} == "" ]] ; then
    echo "${p_e}Empty name from key '${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
  fi
}

build_app_desc_get_version() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  version=$(echo -n "${value}" | sed -e "s|^${name}-||g")

  build_app_desc_handle_result "Failed to extract version from key '${key}' at index ${i} from JSON: ${file}"

  if [[ ${result} -eq 0 && ${version} == "" ]] ; then
    echo "${p_e}Empty version from key '${key}' at index ${i} from JSON: ${file} ."
    echo

    let result=1
  fi
}

build_app_desc_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_app_desc_load_environment() {

  if [[ ${BUILD_APP_DESCRIPTOR_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${BUILD_APP_DESCRIPTOR_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_APP_DESCRIPTOR_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_APP_DESCRIPTOR_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    elif [[ $(echo ${BUILD_APP_DESCRIPTOR_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
      debug_json="y"
    fi
  fi

  if [[ $(echo ${BUILD_APP_DESCRIPTOR_FILES} | sed -e 's|\s||g') != "" ]] ; then
    files=

    for i in ${BUILD_APP_DESCRIPTOR_FILES} ; do
      file=$(echo ${BUILD_APP_DESCRIPTOR_FILES} | sed -e 's|//*|/|g' -e 's|/*$||')

      build_app_desc_print_debug "Using File: ${file}"

      files="${files}${file} "
    done
  fi

  if [[ ${BUILD_APP_DESCRIPTOR_NAME} != "" ]] ; then
    descriptor_name=${BUILD_APP_DESCRIPTOR_NAME}
  fi

  if [[ $(echo -n ${descriptor_name} | grep -sho "[/\\\"\']") != "" ]] ; then
    echo "${p_e}The descriptor name must not contain '/', '\', ''', or '\"' characters: ${descriptor_name} ."

    let result=1
    return
  fi

  if [[ ${BUILD_APP_DESCRIPTOR_VERSION} != "" ]] ; then
    descriptor_version=${BUILD_APP_DESCRIPTOR_VERSION}
  fi

  if [[ $(echo -n ${descriptor_version} | grep -sho "[/\\\"\']") != "" ]] ; then
    echo "${p_e}The descriptor version must not contain '/', '\', ''', or '\"' characters: ${descriptor_version} ."

    let result=1
    return
  fi

  if [[ ${BUILD_APP_DESCRIPTOR_FORCE} != "" ]] ; then
    let file_force=1
  fi

  output_path_name="${descriptor_name}-${descriptor_version}"

  if [[ ${BUILD_APP_DESCRIPTOR_OUTPUT_NAME} != "" ]] ; then
    output_path_name=${BUILD_APP_DESCRIPTOR_OUTPUT_NAME}
  fi

  if [[ $(echo -n ${output_path_name} | grep -sho "[/\\\"\']") != "" ]] ; then
    echo "${p_e}The output path name must not contain '/', '\', ''', or '\"' characters: ${output_path_name} ."

    let result=1
    return
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_APP_DESCRIPTOR_OUTPUT_PATH ]] ; then
    if [[ ${BUILD_APP_DESCRIPTOR_OUTPUT_PATH} == "" ]] ; then
      output_path=
    else
      output_path=$(echo -n ${BUILD_APP_DESCRIPTOR_OUTPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    fi
  fi

  output_path_json="${output_path}${output_path_name}.json"
}

build_app_desc_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_app_desc_verify_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=

  for file in ${files} ; do
    build_app_desc_verify_json "input file" ${file}

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  build_app_desc_verify_directory "output path" ${output_path} create
  build_app_desc_verify_output "output file" ${output_path_json}
}

build_app_desc_verify_directory() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local path=${2}
  local option=${3}

  # Optionally attempt create the directory if it does not exist.
  if [[ ${option} == "create" ]] ; then
    if [[ ! -e ${path} ]] ; then
      mkdir -p ${debug} ${path}

      build_app_desc_handle_result "Failed to create the ${name} directory: ${path}"

      if [[ ${result} -ne 0 ]] ; then return ; fi
    fi
  fi

  if [[ ! -d ${path} ]] ; then
    echo "${p_e}The ${name} is not a valid directory: ${path} ."

    let result=1
  fi
}

build_app_desc_verify_json() {

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

build_app_desc_verify_output() {

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
