#!/bin/bash
#
# Build multiple deployment JSON files and a single deployment YAML file from JSON templates.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
#   - sed
#   - yq
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_DEPLOY_DEBUG may be specifically set to "json" to include printing the json commands.
# The BUILD_DEPLOY_DEBUG may be specifically set to "json_only" to only print the json commands, disabling all other debugging.
#
# Example "var" JSON:
#  {
#    "[VOLUMES]": {
#      "complex": {
#        "object": 1
#      }
#    },
#    "[WORKLOAD]": "my workload"
#  }
#
# Example "name" JSON:
#  [
#    "[VOLUMES]",
#    "[WORKLOAD]"
#  ]
#

main() {
  local combined_file="apps"
  local debug=
  local debug_json=
  local discovery_data=
  local discovery_file=
  local discovery_names=
  local field="name"
  local maps_name="maps"
  local input_base="base"
  local input_name="deployment"
  local input_path="template/deploy/input/"
  local input_path_launches="${input_path}launches/"
  local input_path_main="${input_path}main/"
  local input_path_specific="${input_path}specific/"
  local input_path_vars="${input_path}vars/"
  local jq_instruct
  local jq_merge_join=
  local jq_merge_replace=
  local jq_names=
  local jq_select_by=
  local jq_select_map=
  local jq_select_names=
  local json_vars=
  local json_vars_launches=
  local json_vars_main=
  local names=
  local names_base="names"
  local null="/dev/null"
  local only_these=
  local output_force=
  local output_path="template/deploy/output/"
  local output_path_yaml="${output_path}yaml/"
  local output_path_json="${output_path}json/"
  local vars_name="vars"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i do_combine=1
  local -i do_expand=1
  local -i result=0
  local -i passes=3

  build_depls_load_environment

  build_depls_load_instructions

  build_depls_load_json_sources
  build_depls_load_json_discovery
  build_depls_load_json_discovery_names

  build_depls_expand

  build_depls_combine

  return ${result}
}

build_depls_combine() {

  if [[ ${result} -ne 0 || ${do_combine} -eq 0 || ${names} == "" ]] ; then return ; fi

  local base=${input_path_main}${input_base}.json
  local name=
  local specific=
  local temp=${output_path_yaml}${combined_file}.json
  local yaml=${output_path_yaml}${combined_file}.yaml

  build_depls_combine_initialize

  for name in ${names} ; do

    if [[ ${only_these} != "" && $(echo ${only_these} | grep -sho "\<${name}\>") == "" ]] ; then
      build_depls_print_debug "Skipping combining of ${name} for not being in name restricton list: ${only_these}"

      continue
    fi

    specific=${output_path_json}${name}.json

    if [[ ! -f ${specific} ]] ; then
      build_depls_print_debug "Skipping combining of ${name}, becuase this file does not exist: ${specific}"

      continue
    fi

    build_depls_print_debug "Combining ${specific} with ${temp}"

    combined=

    build_depls_combine_append
    build_depls_combine_write

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done

  build_depls_combine_finalize

  # Always delete temporary JSON file.
  rm -f ${temp}
}

build_depls_combine_append() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_append='.items += [$item]'

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    combined=$(jq --argjson item "$(< ${specific})" -M "${jq_append}" ${temp})
  else
    combined=$(jq --argjson item "$(< ${specific})" -M "${jq_append}" ${temp} 2> ${null})
  fi

  build_depls_handle_result "Failed to append ${specific} with ${temp}"
}

build_depls_combine_finalize() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  build_depls_print_debug "Writing to ${yaml}"

  # Prevent yq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    yq -y -M '.' ${temp} > ${yaml}
  else
    yq -y -M '.' ${temp} > ${yaml} 2> ${null}
  fi

  build_depls_handle_result "Failed to finalize ${yaml}"
}

build_depls_combine_initialize() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq -M '.' ${base} > ${temp}
  else
    jq -M '.' ${base} > ${temp} 2> ${null}
  fi

  build_depls_handle_result "Failed to initialize ${temp}"
}

build_depls_combine_write() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    jq -M . <<< ${combined} > ${temp}
  else
    jq -M . <<< ${combined} > ${temp} 2> ${null}
  fi

  build_depls_handle_result "Failed to write combined ${specific} into ${temp}"
}

build_depls_expand() {

  if [[ ${result} -ne 0 || ${do_expand} -eq 0 ]] ; then return ; fi

  if [[ ${names} == "" ]] ; then
    if [[ ${only_these} == "" ]] ; then
      build_depls_print_debug "No names to process have been provided by the discovery file: ${discovery_file}"
    else
      build_depls_print_debug "No names to process have been provided by the discovery file ${discovery_file} that match the name restriction list"
    fi

    return
  fi

  local json=
  local name=
  local output=
  local what=

  local -i pass=0

  for name in ${names} ; do

    if [[ ${only_these} != "" && $(echo ${only_these} | grep -sho "\<${name}\>") == "" ]] ; then
      build_depls_print_debug "Skipping expansion of ${name} for not being in name restricton list: ${only_these}"

      continue
    fi

    let pass=0

    json=
    output=${output_path_json}${name}.json
    what=

    build_depls_expand_file_load_template

    build_depls_load_merge launches "${input_path_launches}" "${json_vars_main}"

    build_depls_load_merge specific "${input_path_vars}" "${json_vars_launches}"

    while [[ ${result} -eq 0 ]] ; do
      build_depls_expand_file
      build_depls_expand_file_regex

      let pass++

      if [[ ${pass} -lt ${passes} ]] ; then
        build_depls_expand_file_load_generated
      else
        break
      fi

      if [[ ${result} -ne 0 ]] ; then return ; fi
    done

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done
}

build_depls_expand_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  build_depls_print_debug "Expanding ${what} (pass ${pass}) into: ${output}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    echo ${json} | jq --argjson vars "${json_vars}" --argjson names "${jq_names}" "${jq_instruct}" 1> ${output}
  else
    echo ${json} | jq --argjson vars "${json_vars}" --argjson names "${jq_names}" "${jq_instruct}" 1> ${output} 2> ${null}
  fi

  build_depls_handle_result "Failed to expand ${what} into ${output}"
}

build_depls_expand_file_load_template() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local base=
  local specific=
  local template=${input_path_main}${input_name}.json

  build_depls_expand_file_load_template_maps
  build_depls_expand_file_load_template_base
  build_depls_expand_file_load_template_specific
  build_depls_expand_file_load_template_combine
}

build_depls_expand_file_load_template_base() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  base=$(< ${template})

  build_depls_handle_result "Failed to load ${template}"
}

build_depls_expand_file_load_template_combine() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${base} == "" || ${specific} == "" ]] ; then
    if [[ ${base} == "" && ${specific} == "" ]] ; then
      build_depls_print_debug "No data found in for ${name} in either ${input_path_main}${input_name}.json or ${input_path_main}${name}.json"

      return
    fi

    if [[ ${base} == "" ]] ; then
      json=${specific}
      what="${input_path_specific}${name}.json"
    else
      json=${base}
      what="${input_path_main}${input_name}.json"
    fi
  else
    # Prevent jq from printing JSON if ${null} exists when not debugging.
    if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
      json=$(echo "${base} ${specific}" | jq -s -M "${jq_merge_join}")
    else
      json=$(echo "${base} ${specific}" | jq -s -M "${jq_merge_join}" 2> ${null})
    fi

    build_depls_handle_result "Failed to merge ${input_path_main}${name}.json and ${input_path_specific}${name}.json files"

    what="${input_path_main}${input_name}.json and ${input_path_specific}${name}.json"
  fi
}

build_depls_expand_file_load_template_maps() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local alt_name=
  local maps_path=${input_path_main}${maps_name}.json

  build_depls_load_instructions_select_map ${name}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    alt_name=$(jq -r -M "${jq_select_map}" ${maps_path})
  else
    alt_name=$(jq -r -M "${jq_select_map}" ${maps_path} 2> ${null})
  fi

  build_depls_handle_result "Failed to load and parse maps file: ${maps_path}"

  if [[ ${result} -eq 0 && ${alt_name} != "" ]] ; then
    template=${input_path_main}${alt_name}.json

    if [[ ! -f ${template} ]] ; then
      echo "${p_e}The specified map file for ${name} is not a valid regular file: ${template} ."

      let result=1
    fi
  fi
}

build_depls_expand_file_load_template_specific() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local specific_path=${input_path_specific}${name}.json

  if [[ -f ${specific_path} ]] ; then
    specific=$(< ${specific_path})

    build_depls_handle_result "Failed to load ${specific_path}"
  fi
}

build_depls_expand_file_load_generated() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  what=${output}
  json=$(< ${what})

  build_depls_handle_result "Failed to load ${what}"
}

build_depls_expand_file_regex() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local n=

  build_depls_expand_file_regex_do

  for n in ${discovery_names} ; do
    build_depls_expand_file_regex_do ${n}

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done
}

build_depls_expand_file_regex_do() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local field=${1}
  local match=${1}
  local match_id="{id:${match}}"
  local match_location="{location:${match}}"
  local match_name="{name:${match}}"
  local match_version="{version:${match}}"
  local use=
  local use_id=
  local use_location=
  local use_name=
  local use_version=

  # Use the module name currently being operated on when the match field value is empty.
  if [[ ${field} == "" ]] ; then
    field=${name}
  fi

  build_depls_expand_file_regex_do_load id
  use_id=${use}

  build_depls_expand_file_regex_do_load location
  use_location=${use}

  build_depls_expand_file_regex_do_load name
  use_name=${use}

  build_depls_expand_file_regex_do_load version
  use_version=${use}

  build_depls_expand_file_regex_do_sed
}

build_depls_expand_file_regex_do_load() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}

  build_depls_load_instructions_select_by ${field} ${key}

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    use=$(jq -r -M "${jq_select_by}" <<< ${discovery_data})
  else
    use=$(jq -r -M "${jq_select_by}" <<< ${discovery_data} 2> ${null})
  fi

  build_depls_handle_result "Failed to load Discovery Data for field='${field}' and key='${key}' from ${discovery_file}"
}

build_depls_expand_file_regex_do_sed() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  sed -i -e "s|${match_id}|${use_id}|g" -e "s|${match_location}|${use_location}|g" -e "s|${match_name}|${use_name}|g" -e "s|${match_version}|${use_version}|g" ${output}

  build_depls_handle_result "Failed regex replace using sed for field='${field}' on ${output}"
}

build_depls_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_depls_load_environment() {
  if [[ ${BUILD_DEPLOY_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${BUILD_DEPLOY_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_DEPLOY_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${BUILD_DEPLOY_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi

  if [[ ${BUILD_DEPLOY_INPUT_PATH} != "" ]] ; then
    input_path=$(echo -n ${BUILD_DEPLOY_INPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    input_path_launches="${input_path}launches/"
    input_path_main="${input_path}main/"
    input_path_specific="${input_path}specific/"
    input_path_vars="${input_path}vars/"
  fi

  if [[ ${BUILD_DEPLOY_OUTPUT_PATH} != "" ]] ; then
    output_path=$(echo -n ${BUILD_DEPLOY_OUTPUT_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
    output_path_yaml="${output_path}yaml/"
    output_path_json="${output_path}json/"
  fi

  if [[ ${BUILD_DEPLOY_OUTPUT_FORCE} != "" ]] ; then
    output_force="force"
  fi

  if [[ ${BUILD_DEPLOY_OUTPUT_FILE} != "" ]] ; then
    combined_file=${BUILD_DEPLOY_OUTPUT_FILE}
  fi

  build_depls_verify_name ${combined_file} "combined name"

  if [[ ${BUILD_DEPLOY_PASSES} != "" ]] ; then
    let passes=${BUILD_DEPLOY_PASSES}
  fi

  if [[ ${passes} -lt 1 ]] ; then
    echo "${p_e}The number of passes must be greater than or equal to 1."

    let result=1
    return
  fi

  build_depls_verify_directory "input path" ${input_path} create
  build_depls_verify_directory "'main' input path" ${input_path_main} create
  build_depls_verify_directory "'specific' input path" ${input_path_specific} create
  build_depls_verify_directory "output path" ${output_path} create
  build_depls_verify_directory "'YAML' output path" ${output_path_yaml} create
  build_depls_verify_directory "'JSON' output path" ${output_path_json} create

  build_depls_verify_file "'base' input file" ${input_path_main}${input_name}.json
  build_depls_verify_file "'names' input file" ${input_path_main}${names_base}.json create array
  build_depls_verify_file "'vars' input file" ${input_path_main}${vars_name}.json create object
  build_depls_verify_file "'combined' output file" ${output_path_yaml}${combined_file}.yaml not ${output_force}

  build_depls_verify_json "'base' input file" ${input_path_main}${input_name}.json
  build_depls_verify_json "'names' input file" ${input_path_main}${names_base}.json
  build_depls_verify_json "'vars' input file" ${input_path_main}${vars_name}.json

  if [[ ${BUILD_DEPLOY_DISCOVERY} != "" ]] ; then
    discovery_file=${BUILD_DEPLOY_DISCOVERY}
  fi

  if [[ ${BUILD_DEPLOY_NAMES} != "" ]] ; then
    only_these=${BUILD_DEPLOY_NAMES}
  fi

  if [[ ${BUILD_DEPLOY_ACTIONS} != "" ]] ; then
    let do_combine=0
    let do_expand=0

    if [[ $(echo ${BUILD_DEPLOY_ACTIONS} | grep -sho '\<combine\>') != "" ]] ; then
      let do_combine=1
    fi

    if [[ $(echo ${BUILD_DEPLOY_ACTIONS} | grep -sho '\<expand\>') != "" ]] ; then
      let do_expand=1
    fi

    if [[ ${do_combine} -eq 0 && ${do_expand} -eq 0 ]] ; then
      echo "${p_e}The BUILD_DEPLOY_ACTIONS must specify either 'combine', 'expand', or both."

      let result=1
      return
    fi
  fi
}

build_depls_load_instructions() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Substitute template variables if defined, otherwise delete entire values with template.
  # To not delete a particular value intended to be empty, substitute it with either a literal null or an empty string.
  jq_instruct='def in_array($i): $names | index($i) ;
    def get_value($v): $vars[v] ;
    def expand_template(f):
      . as $in |
        if type == "object" then
          reduce keys[] as $key
            ( {}; . + { ($key): ($in[$key] | expand_template(f)) } )
        elif type == "array" then map( expand_template(f) )
        elif type == "string" then
          if in_array(f) then
            if in($vars) then get_value(f) else del(f) end
          else
            f
          end
        else
          f
        end;
    expand_template(.) | del(.. | select(. == null))'

  # Use jq -s to combine exactly two JSON files.
  # Both files must have either a single top-level object or a single top-level array.
  # Cannot mix/match an array and an object using this method.
  jq_merge_join='reduce .[] as $f ({}; . * $f)'
  jq_merge_replace='.[0] as $f1 | .[1] as $f2 | $f1 + $f2'
  jq_select_names=".discovery[].name"

  build_depls_load_instructions_names
  build_depls_load_instructions_vars
}

build_depls_load_instructions_names() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  jq_names=$(< ${input_path_main}${names_base}.json)

  build_depls_handle_result "Failed to load JQ names list from: ${input_path_main}${names_base}.json"
}

build_depls_load_instructions_select_by() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${2}
  local name=${1}

  jq_select_by=".discovery[] | select(.name==\"${name}\").${key}"
}

build_depls_load_instructions_select_map() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}

  jq_select_map=".\"${name}\" | select(. != \"\" and . != null)"
}

build_depls_load_instructions_vars() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  json_vars_main=$(< ${input_path_main}${vars_name}.json)

  build_depls_handle_result "Failed to load JQ vars from: ${input_path_main}${vars_name}.json"
}

build_depls_load_json_sources() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local sources=

  if [[ ! -f ${discovery_file} ]] ; then
    echo "${p_e}Cannot use file from \$BUILD_DEPLOY_DISCOVERY, because it is not a regular file: ${discovery_file}"

    let result=1
    return
  fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    sources=$(jq -r -M "${jq_select_names}" ${discovery_file})
  else
    sources=$(jq -r -M "${jq_select_names}" ${discovery_file} 2> ${null})
  fi

  build_depls_handle_result "Failed to load Discovery Module JSON file from \$BUILD_DEPLOY_DISCOVERY: ${discovery_file}"

  build_depls_load_json_sources_files ${sources}
}

build_depls_load_json_sources_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=

  for name in ${sources} ; do

    if [[ ${only_these} != "" && $(echo ${only_these} | grep -sho "\<${name}\>") == "" ]] ; then
      build_depls_print_debug "Skipping loading of ${name} for not being in name restricton list: ${only_these}"

      continue
    fi

    build_depls_verify_name ${name} "input file name"

    if [[ ${do_expand} -eq 1 ]] ; then
      build_depls_verify_file ${name} ${output_path_json}${name}.json not ${output_force}
      build_depls_verify_json ${name} ${output_path_json}${name}.json
    fi

    if [[ ${result} -ne 0 ]] ; then return ; fi

    names="${names}${name} "
  done
}

build_depls_load_json_discovery() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  discovery_data=$(< ${discovery_file})

  build_depls_handle_result "Failed to load into memory the Discovery Module JSON file from \$BUILD_DEPLOY_DISCOVERY: ${discovery_file}"
}

build_depls_load_json_discovery_names() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    discovery_names=$(echo ${discovery_data} | jq -r -M "${jq_select_names}")
  else
    discovery_names=$(echo ${discovery_data} | jq -r -M "${jq_select_names}" 2> ${null})
  fi

  build_depls_handle_result "Failed to load Discovery Module names from \$BUILD_DEPLOY_DISCOVERY: ${file}"
}

build_depls_load_merge() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local data=
  local file=${2}${name}.json
  local target=${1}
  local with=${3}

  if [[ -f ${file} ]] ; then
    build_depls_print_debug "Combining loaded template variables data with ${target} variables for ${what} from ${1}"

    build_depls_verify_json "'${target} vars' input file" ${file}

    # Prevent jq from printing JSON if ${null} exists when not debugging.
    if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
      data=$(echo "${with} $(< ${file})" | jq -M -s "${jq_merge_replace}")
    else
      data=$(echo "${with} $(< ${file})" | jq -M -s "${jq_merge_replace}" 2> ${null})
    fi

    build_depls_handle_result "Failed to combine loaded template variables data with ${target} variables from ${file}"
  else
    build_depls_print_debug "Using only loaded template variables data with ${target} variables for ${what}"

    data=${with}
  fi

  if [[ ${target} == "launches" ]] ; then
    json_vars_launches=${data}
  else
    json_vars=${data}
  fi
}

build_depls_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_depls_verify_directory() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local path=${2}
  local option=${3}

  # Optionally attempt create the directory if it does not exist.
  if [[ ${option} == "create" ]] ; then
    if [[ ! -e ${path} ]] ; then
      mkdir -p ${debug} ${path}

      build_depls_handle_result "Failed to create the ${name} directory: ${path}"

      if [[ ${result} -ne 0 ]] ; then return ; fi
    fi
  fi

  if [[ ! -d ${path} ]] ; then
    echo "${p_e}The ${name} is not a valid directory: ${path} ."

    let result=1
  fi
}

build_depls_verify_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local path=${2}
  local option=${3}
  local extra=${4}

  # Optionally create the file if it does not exist.
  if [[ ${option} == "create" ]] ; then
    if [[ ! -e ${path} ]] ; then
      if [[ ${extra} == "array" ]] ; then
        echo "[]" > ${path}
      elif [[ ${extra} == "object" ]] ; then
        echo "{}" > ${path}
      else
        touch ${path}
      fi

      build_depls_handle_result "Failed to create the ${name} regular file: ${path}"

      if [[ ${result} -ne 0 ]] ; then return ; fi
    fi
  fi

  # Optionally invert the check to check if the file does NOT exist.
  if [[ ${option} == "not" ]] ; then
    if [[ -f ${path} ]] ; then
      if [[ ${extra} == "force" ]] ; then
        build_depls_print_debug "The regular file ${name} already exists, but ignoring due to 'force' at: ${path}"
      else
        echo "${p_e}The ${name} regular file already exists at: ${path} ."

        let result=1
      fi
    fi
  else
    if [[ ! -f ${path} ]] ; then
      echo "${p_e}The ${name} is not a valid regular file: ${path} ."

      let result=1
    fi
  fi
}

build_depls_verify_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=${2}
  local name=${1}

  if [[ ${file} == "" || ! -f ${file} ]] ; then return ; fi

  code=$(< ${file})

  build_depls_handle_result "JSON Verification failed while loading ${name} file: ${file}"

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    echo ${code} | jq -M .
  else
    echo ${code} | jq -M . >> ${null} 2>&1
  fi

  build_depls_handle_result "JSON Verification failed for ${name} file: ${file}"
}

build_depls_verify_name() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=${1}
  local describe=${2}

  if [[ $(echo ${name} | grep -sho '[/\]') != "" ]] ; then
    echo "${p_e}The ${describe} '${name}' may not contain forward or backward slashes."

    let result=1
  fi
}

main ${*}
