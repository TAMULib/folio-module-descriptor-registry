#!/bin/bash
#
# Build the launch-specific parts of the deployment templates based on the module descriptor "launchDescriptor" settings.
#
# This essentially copies the launch specific properties "env" and "dockerArgs" into the build deployment templates directory for each module.
#
# This requires the following user-space programs:
#   - bash
#   - find
#   - grep
#   - jq
#   - sed
#   - sort
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_LAUNCHES_DEBUG may be specifically set to "json" to include printing the json commands.
# The BUILD_LAUNCHES_DEBUG may be specifically set to "json_only" to only print the json commands, disabling all other debugging.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local null="/dev/null"
  local input_file_instruct="instructions.json"
  local input_path="template/launch/input/"
  local input_path_instruct=
  local instruction_json=
  local instruction_length=
  local jq_length=
  local output_dir_launch="launches/"
  local output_path="template/deploy/input/" # This script generates the input template data for deployment and so it writes to the "deploy/input/" path.
  local output_path_launch=
  local release_path="release/snapshot/"
  local suffix="-latest"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -a instruction_map=
  local -a instruction_type=
  local -a instruction_value=

  local -i result=0

  build_launches_load_environment
  build_launches_load_instructions

  build_launches_build

  return ${result}
}

build_launches_build() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local docker_args=
  local environment=
  local input_file=
  local instruct_total=
  local launch_json="{}"
  local output_file=

  build_launches_print_debug "Processing Directory ${release_path} for suffix ${suffix}"

  find ${release_path} -mindepth 1 -maxdepth 1 -name "*${suffix}" ! -name '.*' \( -type l -o -type f \) -printf "%p\n" | sort -u | while read -d $'\n' input_file ; do

    echo "Operating on file: ${input_file} ."

    build_launches_build_launch
    build_launches_build_path
    build_launches_build_write

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  echo
  echo "Done: Launch JSON files are built."
}

build_launches_build_launch() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local map=
  local type=
  local value=

  local -i i=0

  while [[ ${i} -lt ${instruction_length} ]] ; do

    map=${instruction_map[${i}]}
    type=${instruction_type[${i}]}
    value=${instruction_value[${i}]}

    build_launches_print_debug "Processing map=${map}, type=${type}, value=${value} at index ${i} of ${instruction_length}"

    if [[ ${type} == "field" ]] ; then
      build_launches_build_launch_field
    elif [[ ${type} == "container_port" ]] ; then
      build_launches_build_launch_container_port
    elif [[ ${type} != "" ]] ; then
      build_launches_print_debug "Unknown type '${type}' for map '${map}' at index ${i} of instruction map."
    fi

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

build_launches_build_launch_combine() {

  if [[ ${result} -ne 0 || ${exists} != "true" ]] ; then return ; fi

  local field_json=${1}
  local jq_combine="${launch_json} * ${field_json}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    launch_json=$(jq -M -n "${jq_combine}")
  else
    launch_json=$(jq -M -n "${jq_combine}" 2> ${null})
  fi

  build_launches_handle_result "Failed to combine into item JSON, the following: ${field_json}"
}

build_launches_build_launch_field() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local exists=
  local field_value=

  build_launches_build_launch_field_exists
  build_launches_build_launch_field_extract
  build_launches_build_launch_field_process
}

build_launches_build_launch_field_exists() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # The ${value} must be in JQ syntax and must have a "." before the last field being selected.
  local last=$(echo "${value}" | sed -E 's|^.*\.([^.]+)$|\1|')
  local first=$(echo "${value}" | sed -e "s|\.${last}||")
  local jq_field="${first} | has(\"${last}\")"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    exists=$(jq -r -M "${jq_field}" ${input_file})
  else
    exists=$(jq -r -M "${jq_field}" ${input_file} 2> ${null})
  fi

  build_launches_handle_result "Failed to check if key '${value}' exists in input file: ${input_file}"
}

build_launches_build_launch_field_extract() {

  if [[ ${result} -ne 0 || ${exists} != "true" ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    field_value=$(jq -M "${value}" ${input_file})
  else
    field_value=$(jq -M "${value}" ${input_file} 2> ${null})
  fi

  build_launches_handle_result "Failed to extract value '${value}' from input file: ${input_file}"
}

build_launches_build_launch_field_process() {

  if [[ ${result} -ne 0 || ${exists} != "true" ]] ; then return ; fi

  build_launches_build_launch_combine "{ \"${map}\": ${field_value}}"
}

build_launches_build_launch_container_port() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local exists=
  local field_value=

  # This can use the same existence operations as "field".
  build_launches_build_launch_field_exists

  build_launches_build_launch_container_port_extract
  build_launches_build_launch_container_port_process
}

build_launches_build_launch_container_port_extract() {

  if [[ ${result} -ne 0 || ${exists} != "true" ]] ; then return ; fi

  local jq_keys="${value} | keys"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    field_value=$(jq -M "${jq_keys}" ${input_file})
  else
    field_value=$(jq -M "${jq_keys}" ${input_file} 2> ${null})
  fi

  build_launches_handle_result "Failed to extract port value '${value}' from input file: ${input_file}"
}

build_launches_build_launch_container_port_process() {

  if [[ ${result} -ne 0 || ${exists} != "true" || ${field_value} == "[]" || ${field_value} == "" ]] ; then return ; fi

  local map_value="[]"

  local -a ports_name=
  local -a ports_proto=
  local -a ports_proto_lower=
  local -a ports_number=

  local -i i=0
  local -i total=0

  build_launches_build_launch_container_port_process_count

  while [[ ${i} -lt ${total} ]] ; do
    build_launches_build_launch_container_port_process_reduce protocol ".*/" ".*"
    build_launches_build_launch_container_port_process_reduce number "/.*" "\d+"
    build_launches_build_launch_container_port_process_name
    build_launches_build_launch_container_port_process_join

    let i++

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  build_launches_build_launch_combine "{ \"${map}\": ${map_value}}"
}

build_launches_build_launch_container_port_process_count() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_length="length"
  local data=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -M -r "${jq_length}" <<< ${field_value})
  else
    data=$(jq -M -r "${jq_length}" <<< ${field_value} 2> ${null})
  fi

  build_launches_handle_result "Failed to extract total ports from loaded field value '${value}' of ${input_file}"

  if [[ ${data} != "" && ${data} != "null" ]] ; then
    let total=${data}
  else
    let total=0
  fi
}

build_launches_build_launch_container_port_process_join() {

  if [[ ${result} -ne 0 || ${ports_name[${i}]} == "" || ${ports_proto[${i}]} == "" || ${ports_number[${i}]} == "" ]] ; then return ; fi

  local object="{ \"containerPort\": ${ports_number[${i}]}, \"name\": \"${ports_name[${i}]}\", \"protocol\": \"${ports_proto[${i}]}\" }"
  local jq_append=". += [ ${object} ]"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    map_value=$(jq -M "${jq_append}" <<< ${map_value})
  else
    map_value=$(jq -M "${jq_append}" <<< ${map_value} 2> ${null})
  fi

  build_launches_handle_result "Failed to combine port data from loaded field value '${value}' of ${input_file}"
}

build_launches_build_launch_container_port_process_name() {

  if [[ ${result} -ne 0 || ${ports_proto[${i}]} == "" || ${ports_number[${i}]} == "" ]] ; then return ; fi

  ports_name[${i}]="${ports_number[${i}]}-${ports_proto_lower[${i}]}-${i}"
}

build_launches_build_launch_container_port_process_reduce() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local grep_match=${3}
  local jq_port=".[${i}]"
  local sed_match=${2}
  local target=${1}
  local data=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -M -r "${jq_port}" <<< ${field_value} | sed -E "s|${sed_match}||" | grep -shoiP "${grep_match}")
  else
    data=$(jq -M -r "${jq_port}" <<< ${field_value} 2> ${null} | sed -E "s|${sed_match}||" | grep -shoiP "${grep_match}")
  fi

  build_launches_handle_result "Failed to extract port ${target} at ${i} from loaded field value '${value}' of ${input_file}"

  if [[ ${target} == "number" ]] ; then
    if [[ ${data} == "" || ${data} == "null" ]] ; then
      ports_number[${i}]=
    else
      ports_number[${i}]=${data}
    fi
  else
    if [[ ${data} == "" || ${data} == "null" ]] ; then
      ports_proto[${i}]=
      ports_proto_lower[${i}]=
    elif [[ $(echo ${data} | grep -shoi "tcp") != "" ]] ; then
      ports_proto[${i}]="TCP"
      ports_proto_lower[${i}]="tcp"
    elif [[ $(echo ${data} | grep -shoi "udp") != "" ]] ; then
      ports_proto[${i}]="UDP"
      ports_proto_lower[${i}]="udp"
    else
      ports_proto[${i}]=
      ports_proto_lower[${i}]=

      build_launches_print_debug "Unknown protocol ${data} for ${target} at ${i} from loaded field value '${value}' of ${input_file}"
    fi
  fi
}

build_launches_build_path() {

  # Clear output file before each run regardless of state.
  output_file=

  if [[ ${result} -ne 0 || ${launch_json} == "{}" || ${launch_json} == "" ]] ; then return ; fi

  local release=$(echo -n ${input_file} | sed -E 's|.*/+([^/]+)$|\1|' | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||")

  build_launches_handle_result "Failed to build release path from path: ${input_file}"

  output_file="${output_path_launch}${release}.json"
}

build_launches_build_write() {

  if [[ ${result} -ne 0 || ${output_file} == "" ]] ; then return ; fi

  build_launches_print_debug "Writing to: ${output_file}"

  echo "${launch_json}" > ${output_file}

  build_launches_handle_result "Failed to write to release path: ${output_file}"
}

build_launches_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_launches_load_environment() {
  if [[ ${BUILD_LAUNCHES_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${BUILD_LAUNCHES_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_LAUNCHES_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${BUILD_LAUNCHES_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi

  if [[ ${BUILD_LAUNCHES_INPUT_PATH} != "" ]] ; then
    input_path=$(echo -n ${BUILD_LAUNCHES_INPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')

    if [[ -e ${input_path} ]] ; then
      if [[ ! -d ${input_path} ]] ; then
        echo "${p_e}The following path is not a valid directory: ${input_path} ."

        let result=1
      fi
    fi
  fi

  input_path_instruct="${input_path}${input_file_instruct}"

  if [[ ${BUILD_LAUNCHES_OUTPUT_PATH} != "" ]] ; then
    output_path=$(echo -n ${BUILD_LAUNCHES_OUTPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')

    if [[ -e ${output_path} ]] ; then
      if [[ ! -d ${output_path} ]] ; then
        echo "${p_e}The following path is not a valid directory: ${output_path} ."

        let result=1
      fi
    fi
  fi

  output_path_launch="${output_path}${output_dir_launch}"

  if [[ ${BUILD_LAUNCHES_RELEASE_PATH} != "" ]] ; then
    release_path=$(echo -n ${BUILD_LAUNCHES_RELEASE_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')

    if [[ -e ${release_path} ]] ; then
      if [[ ! -d ${release_path} ]] ; then
        echo "${p_e}The following path is not a valid directory: ${release_path} ."

        let result=1
      fi
    fi
  fi

  if [[ ${BUILD_LAUNCHES_VERSION} != "" ]] ; then
    suffix="-${BUILD_LAUNCHES_VERSION}"
  fi
}

build_launches_load_instructions() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  jq_length='. | length'

  build_launches_load_instructions_map
  build_launches_load_instructions_length
  build_launches_load_instructions_array
}

build_launches_load_instructions_array() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local -i i=0

  while [[ ${i} -lt ${instruction_length} ]] ; do
    build_launches_load_instructions_array_item map
    build_launches_load_instructions_array_item type
    build_launches_load_instructions_array_item value

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

build_launches_load_instructions_array_item() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}
  local jq_key=".[${i}].${key}"
  local value=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(jq -r -M "${jq_key}" <<< ${instruction_json})
  else
    value=$(jq -r -M "${jq_key}" <<< ${instruction_json} 2> ${null})
  fi

  build_launches_handle_result "Failed to load key '${key}' at index ${i} from instruction map"

  if [[ ${key} == "map" ]] ; then
    instruction_map[${i}]=${value}
  elif [[ ${key} == "type" ]] ; then
    instruction_type[${i}]=${value}
  else
    instruction_value[${i}]=${value}
  fi
}

build_launches_load_instructions_map() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    instruction_json=$(jq -r -M '.' ${input_path_instruct})
  else
    instruction_json=$(jq -r -M '.' ${input_path_instruct} 2> ${null})
  fi

  build_launches_handle_result "Failed to load instruction map from JSON: ${input_path_instruct}"
}

build_launches_load_instructions_length() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local data=

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    data=$(jq -r -M "${jq_length}" <<< ${instruction_json})
  else
    data=$(jq -r -M "${jq_length}" <<< ${instruction_json} 2> ${null})
  fi

  build_launches_handle_result "Failed to load instruction map length"

  if [[ ${result} -eq 0 && ${data} != "" && ${data} != "null" ]] ; then
    let instruction_length=${data}
  else
    let instruction_length=0
  fi
}

build_launches_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

main ${*}
