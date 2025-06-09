#!/bin/bash
#
# Populate a release directory based on a platform-complete release tag.
#
# This requires the following user-space programs:
#   - bash
#   - curl
#   - grep
#   - jq
#   - sed
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The following POPULATE_RELEASE_REPOSITORY_PART are known to work in GitHub:
#   - 'tags':  Designate that this uses a tag name that is specified via the POPULATE_RELEASE_TAG.
#   - 'heads': Designate that this uses a branch name that is specified via the POPULATE_RELEASE_TAG (the default).
#   - '':      Set to an empty string for when using a commit hash, in which case the POPULATE_RELEASE_TAG must be a valid hash.
#
# The POPULATE_RELEASE_DEBUG may be specifically set to "json" to include printing the JSON files.
# The POPULATE_RELEASE_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
#
# The POPULATE_RELEASE_DEBUG may be specifically set to "curl" to include printing the curl commands.
# The POPULATE_RELEASE_DEBUG may be specifically set to "curl_only" to only print the curl commands, disabling all other debugging (does not pass -v to curl).
#
# The POPULATE_RELEASE_CURL_FAIL designate the fail mode of either "fail" or "continue".
#
# When the fail mode is "fail", then the "--fail" parameter is passed to curl.
# This should result in a failure on 404.
#
# When the fail mode is "none", then the "--fail" parameter is not passed to curl.
# This can result in bad data in the release files (non JSON data) on any 4xx error, such as a 404.
#
# When the fail mode is "report", then the "--fail" parameter is passed to curl, but the errors are printed and the script continues to operate, ignoring the failure.
# There should be no release file created.
#

main() {
  local IFS=$' \t\n' # Protect IFS from security issue before anything is done.
  local debug=
  local debug_curl=
  local debug_curl_silent="-s"
  local debug_json=
  local destination="release/"
  local curl_fail="--fail"
  local fail_mode="report"
  local files="install.json eureka-platform.json"
  local flower="snapshot"
  local null="/dev/null"
  local part="heads"
  local registry="https://folio-registry.dev.folio.org/_/proxy/modules/"
  local releases=
  local repository="https://raw.githubusercontent.com/folio-org/platform-complete/"
  local tag="snapshot"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  pop_rel_load_environment

  if [[ ${POPULATE_RELEASE_FILE_REUSE} != "" ]] ; then
    if [[ ! -f ${file} ]] ; then
      echo "${p_e}The install JSON file is either missing or is not a regular file: ${file} ."

      let result=1
    fi
  else
    pop_rel_process_sources
  fi

  pop_rel_process_files

  return ${result}
}

pop_rel_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

pop_rel_load_environment() {
  local i=
  local file=

  if [[ ${POPULATE_RELEASE_DEBUG} != "" ]] ; then
    debug="-v"
    debug_curl=
    debug_json=

    if [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "^\s*curl\s*$") != "" ]] ; then
      debug_curl="y"
      debug_curl_silent=
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "^\s*curl_only\s*$") != "" ]] ; then
      debug=
      debug_curl="y"
      debug_curl_silent=
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "\<curl\>") != "" ]] ; then
        debug_curl="y"
        debug_curl_silent=
      fi

      if [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi

  if [[ ${POPULATE_RELEASE_CURL_FAIL} != "" ]] ; then
    if [[ ${POPULATE_RELEASE_CURL_FAIL} == "fail" ]] ; then
      curl_fail="--fail"
      fail_mode="fail"
    elif [[ ${POPULATE_RELEASE_CURL_FAIL} == "none" ]] ; then
      curl_fail=
      fail_mode="none"
    elif [[ ${POPULATE_RELEASE_CURL_FAIL} == "report" ]] ; then
      curl_fail="--fail"
      fail_mode="report"
    else
      echo "${p_e}Unknown POPULATE_RELEASE_CURL_FAIL value: ${POPULATE_RELEASE_CURL_FAIL} ."

      let result=1

      return
    fi
  fi

  if [[ ${POPULATE_RELEASE_DESTINATION} != "" ]] ; then
    destination=$(echo ${POPULATE_RELEASE_DESTINATION} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ $(echo ${POPULATE_RELEASE_FILES} | sed -e 's|\s||g') != "" ]] ; then
    files=

    for i in ${POPULATE_RELEASE_FILES} ; do
      file=$(echo ${POPULATE_RELEASE_FILES} | sed -e 's|//*|/|g' -e 's|/*$||')

      pop_rel_print_debug "Using File: ${file}"

      files="${files}${file} "
    done
  fi

  if [[ ${POPULATE_RELEASE_REGISTRY} != "" ]] ; then
    registry=$(echo ${POPULATE_RELEASE_REGISTRY} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ ${POPULATE_RELEASE_TAG} != "" ]] ; then
    tag=$(echo ${POPULATE_RELEASE_TAG} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_FLOWER} != "" ]] ; then
    flower=$(echo ${POPULATE_RELEASE_FLOWER} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_REPOSITORY} != "" ]] ; then
    repository=$(echo ${POPULATE_RELEASE_REPOSITORY} | sed -e -e 's|/*$|/|g')
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v POPULATE_RELEASE_REPOSITORY_PART ]] ; then
    part=${POPULATE_RELEASE_REPOSITORY_PART}
  fi

  if [[ ${part} != "" ]] ; then
    part="refs/$(echo ${part} | sed -e 's|//*|/|g' -e 's|/*$|/|g')"
  fi
}

pop_rel_load_source() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  source="$(echo ${repository} | sed -e 's|/*$|/|')${part}${tag}/${file}"
}

pop_rel_print_curl_debug() {

  if [[ ${debug_curl} == "" ]] ; then return ; fi

  echo "${p_d}${1} Curl: ${2} ."
  echo
}

pop_rel_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

pop_rel_process_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=
  local i=
  local source=

  for i in ${files} ; do
    file=${i}

    echo
    echo "Operating on ${file}."

    pop_rel_load_source

    pop_rel_process_files_releases_prepare

    pop_rel_process_files_releases_curl

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done

  if [[ ${result} -ne 0 ]] ; then return ; fi

  echo
  echo "Done: Release is populated."
}

pop_rel_process_files_releases_curl() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local release=

  if [[ ${releases} == "" ]] ; then
    echo "Done: No releases to fetch from."

    return
  fi

  source="$(echo ${repository} | sed -e 's|/*$|/|')${part}${tag}/${file}"

  for release in ${releases} ; do

    # Skip any files without the dash in the name used to provide a version.
    if [[ $(echo ${release} | grep -sho '-') == "" ]] ; then
      continue
    fi

    if [[ -f ${destination}${flower}/${release} ]] ; then
      if [[ ${debug} != "" ]] ; then
        echo "${p_d}Skipping existing Module Descriptor: ${destination}${flower}/${release} ."
        echo
      fi

      continue
    fi

    if [[ ${debug} != "" ]] ; then
      echo "${p_d}Curl requesting Module Descriptor ${release} from: ${registry}${release} ."
      echo
    else
      echo "Curl requesting Module Descriptor: ${release}."
    fi

    pop_rel_print_curl_debug "Executing Descriptor" "curl -w '\n' ${curl_fail} ${debug_curl_silent} ${debug_curl} ${registry}${release} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${flower}/${release}"

    curl -w '\n' ${curl_fail} ${debug_curl_silent} ${debug_curl} ${registry}${release} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${flower}/${release}

    pop_rel_handle_result "Curl request failed for: ${registry}${release} to ${destination}${flower}/${release}"

    if [[ ${result} -ne 0 && ${fail_mode} == "report" ]] ; then
      # A 404 results in a 22 status code returned.
      if [[ ${result} -eq 22 ]] ; then
        let result=0
      fi
    fi

    if [[ ${result} -ne 0 ]] ; then return ; fi
  done

  echo "Done: Module descriptors fetched as needed."
}

pop_rel_process_files_releases_prepare() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ -f ${file} ]] ; then
    # Prevent jq from printing JSON if ${null} exists when not debugging.
    if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
      releases=$(jq -r -M '.[].id' ${file})
    else
      releases=$(jq -r -M '.[].id' ${file} 2> ${null})
    fi

    pop_rel_handle_result "Failed to load release IDs from JSON: ${file}"
  fi

  if [[ ! -d ${destination}${flower}/ ]] ; then
    mkdir ${debug} -p ${destination}${flower}/

    pop_rel_handle_result "Create directory failed for destination: ${destination}${flower}/"
  fi
}

pop_rel_process_sources() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=
  local i=
  local source=

  for i in ${files} ; do
    file=${i}

    pop_rel_load_source

    pop_rel_process_sources_prepare

    pop_rel_process_sources_curl

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done
}

pop_rel_process_sources_prepare() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${debug} != "" ]] ; then
    echo "${p_d}Curl requesting Install JSON from: ${source} ."
    echo
  fi

  if [[ -e ${file} ]] ; then
    rm ${debug} -f ${file}

    pop_rel_handle_result "Create file failed for install file: ${file}"
  fi
}

pop_rel_process_sources_curl() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  pop_rel_print_curl_debug "Executing Package" "curl -w '\n' ${curl_fail} ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}"

  curl -w '\n' ${curl_fail} ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}

  pop_rel_handle_result "Curl request failed for: ${source}"
}

main ${*}
