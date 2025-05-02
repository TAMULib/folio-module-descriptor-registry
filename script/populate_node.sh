#!/bin/bash
#
# Populate part of a release based on a Node package.
#
# This is intended to act as a supplement to the populate_release.sh script for packages that are in the Node package system and are not defined in an install.json file or similar.
# This should only be used for packages not in an existing install.json file or similar.
#
# The Node/NPM/Yarn registry provides a way to fetch projects as dependencies but does not provide a way to fetch as a project.
# This, therefore, fetches as dependencies, then changes into the dependency directories and builds the module descriptor using stripes-cli.
# Using GitHub to clone the repository does not work as intended because GitHub does not provide the custom detailed build version, such as 2.0.10990000000060.
# Simply downloading the GitHub repository and changing the version number may result in discrepancies as well.
#
# Note that the version of any package can be determined using: `yarn info @folio/authorization-roles version --json`.
#
# This script currently only understands packages prefixed with `@folio/` in the package.json.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
#   - sed
#   - stripes-cli
#   - yarn
#
# See the repository `README.md` for the listing of the environment variables.
#
# The POPULATE_NODE_DEBUG may be specifically set to "json" to include printing the JSON files.
# The POPULATE_NODE_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
# The POPULATE_NODE_DEBUG may be specifically set to "yarn" to include running yarn in verbose mode.
# The POPULATE_NODE_DEBUG may be specifically set to "yarn_only" to only include running yarn in verbose mode, disabling all other debugging (does not pass -v).
#
# A workspace `package.json` file looks like:
#   ```json
#     {
#       "name": "workspace",
#       "private": true,
#       "version": "1.0.0",
#       "workspaces": [ "*" ],
#       "dependencies": { }
#     }
#   ```
#

main() {
  local debug=
  local debug_json=
  local debug_yarn="-s"
  local destination=
  local npm_dir=$(echo ${PWD} | sed -e 's|/*$|/|')
  local npm_file="npm.json"
  local null="/dev/null"
  local projects="@folio/authorization-policies @folio/authorization-roles"
  local workspace="${PWD}/workspace/"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0
  local -i skip_bad=0

  destination=${npm_dir}release/snapshot/

  pop_node_load_environment

  pop_node_verify_files

  pop_node_process_projects

  return ${result}
}

pop_node_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

pop_node_load_environment() {
  local project=

  if [[ ${POPULATE_NODE_DEBUG} != "" ]] ; then
    debug="-v"
    debug_json=
    debug_yarn="-s"

    if [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "^\s*yarn\s*$") != "" ]] ; then
      debug_yarn="--verbose"
    elif [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "^\s*yarn_only\s*$") != "" ]] ; then
      debug=
      debug_yarn="--verbose"
    elif [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi

      if [[ $(echo ${POPULATE_NODE_DEBUG} | grep -sho "\<yarn\>") != "" ]] ; then
        debug_yarn="--verbose"
      fi
    fi
  fi

  if [[ $(echo -n ${POPULATE_NODE_DESTINATION} | sed -e 's|\s||g') != "" ]] ; then
    destination=$(echo -n ${POPULATE_NODE_DESTINATION} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ $(echo -n ${POPULATE_NODE_NPM_DIR} | sed -e 's|\s||g') != "" ]] ; then
    npm_dir=$(echo -n ${POPULATE_NODE_NPM_DIR} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ ${POPULATE_NODE_NPM_FILE} != "" ]] ; then
    npm_file=$(echo -n ${POPULATE_NODE_NPM_FILE} | sed -e 's|//*|/|g' -e 's|/*$||g')
  fi

  if [[ $(echo -n ${POPULATE_NODE_PROJECTS} | sed -e 's|\s||g') != "" ]] ; then
    projects=

    for project in ${POPULATE_NODE_PROJECTS} ; do
      projects="${projects}${project} "
    done
  fi

  if [[ $(echo -n ${POPULATE_NODE_SKIP_BAD} | sed -e 's|\s||g') != "" ]] ; then
    let skip_bad=1
  fi

  if [[ ${POPULATE_NODE_WORKSPACE} != "" ]] ; then
    workspace=$(echo -n ${POPULATE_NODE_WORKSPACE} | sed -e 's|//*|/|g' -e 's|/*$|/|g')

    # If the workspace path is relative, make it absolute.
    if [[ $(echo ${workspace} | grep -sho '^/') == "" ]] ; then
      workspace="${PWD}/${workspace}"
    elif [[ $(echo ${workspace} | grep -sho '^\./') != "" ]] ; then
      workspace=$(echo -n ${workspace} | sed -e "s|^\./|${PWD}/|")
    fi
  fi
}

pop_node_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

pop_node_process_projects() {
  local project=
  local project_simple=
  local version=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Use pushd/popd from bash to better control directory transitioning and restoration on error.
  pushd ${workspace}

  pop_node_handle_result "Failed to change into workspace directory: ${workspace}"

  if [[ ${result} -ne 0 ]] ; then return ; fi

  for project in ${projects} ; do

    project_simple=$(echo -n ${project} | sed -e 's|^.*/||')
    version=

    echo
    echo "Operating on ${project} (simple: ${project_simple})."

    pop_node_process_projects_fetch

    pop_node_process_projects_into_project

    pop_node_process_projects_build_descriptor

    pop_node_process_projects_extract_version

    pop_node_process_projects_copy_descriptor

    pop_node_process_projects_update_npm_json

    pop_node_process_projects_into_workspace

    if [[ ${result} -ne 0 ]] ; then
      if [[ ${skip_bad} -ne 0 ]] ; then continue ; fi

      break
    fi
  done

  # Always pop the directory stack to return to the starting directory.
  popd
}

pop_node_process_projects_build_descriptor() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  yarn ${debug_yarn} run --non-interactive build-mod-descriptor

  pop_node_handle_result "Failed to build module descriptor for the project: ${project} (simple: ${project_simple})"
}

pop_node_process_projects_copy_descriptor() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local name=folio_${project}
  local release="${destination}folio_${project_simple}-${version}"

  cp ${debug} module-descriptor.json ${release}

  pop_node_handle_result "Failed to copy the module descriptor for the ${project} (simple: ${project_simple}) to: ${release}"
}

pop_node_process_projects_extract_version() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file="package.json"

  if [[ ! -f ${file} ]] ; then
    echo "${p_e}The ${file} file is either missing or not a valid regular file for: ${project} (simple: ${project_simple})."

    let result=1

    return;
  fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    releases=$(jq -r -M '.version' ${file} | sed -e 's|\s||g')
  elif [[ ${debug} != "" ]] ; then
    releases=$(jq -r -M '.version' ${file} >> ${null} | sed -e 's|\s||g')
  else
    releases=$(jq -r -M '.version' ${file} &> ${null} | sed -e 's|\s||g')
  fi

  if [[ ${version} == "" ]] ; then
    echo "${p_e}The ${file} file has no valid version ('${version}') for: ${project} (simple: ${project_simple})."

    let result=1
  fi
}

pop_node_process_projects_fetch() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  yarn ${debug_yarn} add -W --non-interactive ${project}

  pop_node_handle_result "Failed to fetch the project: ${project} (simple: ${project_simple})"
}

pop_node_process_projects_into_project() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  pop_node_print_debug "cd \"node_modules/${project}/\""

  cd "node_modules/${project}/"

  pop_node_handle_result "Failed to change into project directory: node_modules/${project}/"
}

pop_node_process_projects_into_workspace() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  pop_node_print_debug "cd ${workspace}"

  cd ${workspace}

  pop_node_handle_result "Failed to change into workspace directory: ${workspace}"
}

pop_node_process_projects_update_npm_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Work around JQ's problems with empty arrays when appending files.
  if [[ ! -f ${npm_dir}${npm_file} ]] ; then
    pop_node_print_debug "echo \"[{ \\\"id\\\": \\\"folio_${project_simple}-${version}\\\", \\\"action\\\": \\\"enable\\\" }]\" > ${npm_dir}${npm_file}"

    echo "[{ \"id\": \"folio_${project_simple}-${version}\", \"action\": \"enable\" }]" > ${npm_dir}${npm_file}
  else
    # Work around JQ's problems with using the input as the output.
    local json=$(cat ${npm_dir}${npm_file})

    pop_node_print_debug "echo ${json} | jq \". |= . + [{ \\\"id\\\": \\\"folio_${project_simple}-${version}\\\", \\\"action\\\": \\\"enable\\\" }]\" > ${npm_dir}${npm_file}"

    echo ${json} | jq ". |= . + [{ \"id\": \"folio_${project_simple}-${version}\", \"action\": \"enable\" }]" > ${npm_dir}${npm_file}
  fi

  pop_node_handle_result "Failed to add the version (${version}) for the project ${project} (simple: ${project_simple}) to: ${npm_dir}${npm_file}"
}

pop_node_verify_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local workspace_file=${workspace}package.json
  local workspace_json="{ \"name\": \"workspace\", \"private\": true, \"version\": \"1.0.0\", \"workspaces\": [ \"*\" ], \"dependencies\": { } }"

  pop_node_verify_files_workspace

  pop_node_verify_files_workspace_file

  pop_node_verify_files_workspace_file_json

  pop_node_verify_files_npm_file

  pop_node_verify_files_destination
}

pop_node_verify_files_destination() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ -e ${destination} ]] ; then
    if [[ ! -d ${destination} ]] ; then
      echo "${p_e}The NPM JSON file is not and must be a directory file: ${destination} ."

      let result=1
    fi

    return
  fi

  mkdir ${debug} -p ${destination}

  pop_node_handle_result "Failed to create destination directory: ${destination}"
}

pop_node_verify_files_npm_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ -e ${npm_dir}${npm_file} ]] ; then
    if [[ ! -f ${npm_dir}${npm_file} ]] ; then
      echo "${p_e}The NPM JSON file is not and must be a regular file: ${npm_dir}${npm_file} ."

      let result=1

      return
    fi
  fi

  # Re-create the NPM file on each run of this script.
  rm ${debug} -f ${npm_dir}${npm_file}

  pop_node_handle_result "Failed to create NPM JSON file: ${npm_dir}${npm_file}"
}

pop_node_verify_files_workspace() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  pop_node_print_debug "Verifying workspace directory: ${workspace}"

  if [[ -e ${workspace} ]] ; then
    if [[ ! -d ${workspace} ]] ; then
      echo "${p_e}The workspace is not and must be a directory: ${workspace} ."

      let result=1
    fi
  elif [[ ! -d ${workspace} ]] ; then
    mkdir ${debug} -p ${workspace}

    pop_node_handle_result "Failed to create workspace directory: ${workspace}"
  fi
}

pop_node_verify_files_workspace_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ -e ${workspace_file} ]] ; then
    if [[ ! -f ${workspace_file} ]] ; then
      echo "${p_e}The workspace JSON file is not and must be a regular file: ${workspace_file} ."

      let result=1
    fi
  else
    echo ${workspace_json} > ${workspace_file}

    pop_node_handle_result "Failed to create workspace file: ${workspace_file}"
  fi
}

pop_node_verify_files_workspace_file_json() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    cat ${workspace_file} | jq
  else
    cat ${workspace_file} | jq >> ${null}
  fi

  pop_node_handle_result "Invalid workspace JSON file: ${workspace_file}"
}

main ${*}
