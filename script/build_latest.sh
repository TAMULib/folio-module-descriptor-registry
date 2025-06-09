#!/bin/bash
#
# Determine the latest version and make symbolic links with a suffix like "-latest" in place of the version suffix.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - jq
#   - sed
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_LATEST_DEBUG may be specifically set to "json" to include printing the JSON files.
# The BUILD_LATEST_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
#
# If neither the BUILD_LATEST_FILES nor the command line parameter files are passed then the default file is used.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_json=
  local files="install.json eureka-platform.json npm.json"
  local null="/dev/null"
  local path="release/snapshot/"
  local suffix="-latest"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0
  local -i skip_not_found=0

  build_latest_load_environment ${*}

  build_latest_verify_files

  build_latest_operate

  return ${result}
}

build_latest_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_latest_load_environment() {
  local i=
  local file=

  if [[ ${BUILD_LATEST_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${BUILD_LATEST_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_LATEST_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_LATEST_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    elif [[ $(echo ${BUILD_LATEST_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
      debug_json="y"
    fi
  fi

  if [[ $(echo ${BUILD_LATEST_FILES} | sed -e 's|\s||g') != "" ]] ; then
    files=

    for i in ${BUILD_LATEST_FILES} ; do
      file=$(echo ${i} | sed -e 's|//*|/|g' -e 's|/*$||')

      if [[ -f ${file} ]] ; then
        build_latest_print_debug "Using File: ${file}"

        files="${files}${file} "
      else
        echo "${p_e}The following path is not a valid file: ${file} ."

        let result=1

        return
      fi
    done

    file=
  fi

  if [[ ${BUILD_LATEST_SKIP_NOT_FOUND} != "" ]] ; then
    let skip_not_found=1
  fi

  if [[ ${BUILD_LATEST_PATH} != "" ]] ; then
    path=$(echo -n ${BUILD_LATEST_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')

    if [[ ${path} != "" ]] ; then
      if [[ -e ${path} ]] ; then
        if [[ ! -d ${path} ]] ; then
          echo "${p_e}The following path is not a valid directory: ${path} ."

          let result=1
        fi
      else
        mkdir ${debug} -p ${path}

        build_latest_handle_result "The following path could not be created: ${path}"
      fi
    fi
  fi
}

build_latest_operate() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=
  local release=
  local releases=
  local i=
  local version=

  for file in ${files} ; do

    build_latest_operate_releases_prepare

    if [[ ${result} -ne 0 ]] ; then return ; fi

    for i in ${releases} ; do

      # Skip any files without the dash in the name used to provide a version.
      if [[ $(echo ${i} | grep -sho '-') == "" ]] ; then
        continue
      fi

      release=$(echo -n ${i} | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||")

      if [[ ! -f ${path}${i} ]] ; then
        if [[ ${skip_not_found} -ne 0 ]] ; then
          build_latest_print_debug "Cannot find the version file in ${file} for ${release} to link against, skipping file: ${path}${i}"

          continue
        fi

        echo "${p_e}Cannot find the version file in ${file} for ${release} to link to: ${path}${i} ."

        let result=1

        return
      fi

      ln -vsf ${i} ${path}${release}${suffix}

      build_latest_handle_result "Failed create symbolic link to '${i}' from '${path}${release}${suffix}'"

      if [[ ${result} -ne 0 ]] ; then return ; fi
    done
  done

  echo
  echo "Done: Latest versions are built."
}

build_latest_operate_releases_prepare() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    releases=$(jq -r -M '.[].id' ${file})
  else
    releases=$(jq -r -M '.[].id' ${file} 2> ${null})
  fi

  pop_rel_handle_result "Failed to load release IDs from JSON: ${file}"
}

build_latest_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_latest_verify_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local i=
  local problems=

  if [[ ${files} != "" ]] ; then
    for i in ${files} ; do
      build_latest_print_debug "Verifying File: ${i}"

      if [[ ! -f ${i} ]] ; then
        problems="${problems}${i} "

        continue
      fi

      # Prevent jq from printing JSON if ${null} exists when not debugging.
      if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
        jq . ${i}
      else
        jq . ${i} >> ${null}
      fi

      if [[ ${?} -ne 0 ]] ; then
        problems="${problems}${i} "
      fi
    done
  fi

  if [[ ${problems} != "" ]] ; then
    echo "${p_e}Build Latest failed, the following are either missing or invalid files: ${problems}."

    if [[ ${result} -eq 0 ]] ; then
      let result=1
    fi
  fi
}

main ${*}
