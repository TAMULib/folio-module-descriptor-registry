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
#  Parameters:
#    1) (optional) The GitHub release tag (target), such as "R1-2024-csp-9" (If not needed but (2) is, then set this to an empty string).
#    2) (optional) The Flower release name, such as "quesnelia" or "snapshot", used to create the destination directory.
#
#  Environment Variables:
#    POPULATE_RELEASE_CURL_FAIL:       Designate how to handle curl failures. This can be one of: "fail", "none", and "report" (default).
#    POPULATE_RELEASE_DEBUG:           Enable debug verbosity, any non-empty string enables this.
#    POPULATE_RELEASE_DESTINATION:     Destination parent directory.
#    POPULATE_RELEASE_FILE_REUSE:      Enable re-using existing JSON files without GET fetching, any non-empty string enables this.
#    POPULATE_RELEASE_FILES:           The name of space separated JSON files, such as "install.json" and "eureka-platform.json" to GET fetch and store locally for processing.
#    POPULATE_RELEASE_FLOWER:          The Flower release name; If specified, then the associated parameter is ignored.
#    POPULATE_RELEASE_REGISTRY:        The URL to GET the module descriptor from for some specific module version.
#    POPULATE_RELEASE_REPOSITORY:      The raw GitHub repository URL to fetch from (but without the URL parts after the repository name).
#    POPULATE_RELEASE_REPOSITORY_PART: The part of the GitHub repository URL specifying the tag, branch, or hash (but without either the specific tag/branch name or the file path).
#    POPULATE_RELEASE_TARGET:          The GitHub release tag; If specified, then the associated parameter is ignored.
#
# The following POPULATE_RELEASE_REPOSITORY_PART are known to work in GitHub:
#   - 'tags':  Designate that this uses a tag name that is specified via the POPULATE_RELEASE_TARGET.
#   - 'heads': Designate that this uses a branch name that is specified via the POPULATE_RELEASE_TARGET (the default).
#   - '':      Set to an empty string for when using a commit hash, in which case the POPULATE_RELEASE_TARGET must be a valid hash.
#
# The POPULATE_RELEASE_DEBUG may be specifically set to "curl" to include printing the curl commands.
# The POPULATE_RELEASE_DEBUG may be specifically set to "curl_only" to only print the curl commands, disabling all other debugging (does not pass -v to curl).
# Otherwise, any non-empty value will result in debug printing without the curl command.
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
  local debug=
  local debug_curl=
  local destination="release/"
  local curl_fail="--fail"
  local fail_mode="report"
  local files="install.json eureka-platform.json"
  local flower="snapshot"
  local part="heads"
  local registry="https://folio-registry.dev.folio.org/_/proxy/modules/"
  local releases=
  local repository="https://raw.githubusercontent.com/folio-org/platform-complete/"
  local target="snapshot"

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

pop_rel_load_environment() {
  local i=
  local file=

  if [[ ${1} != "" ]] ; then
    target=$(echo ${1} | sed -e 's|/||g')
  fi

  if [[ ${2} != "" ]] ; then
    flower=$(echo ${2} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_DEBUG} != "" ]] ; then
    debug="-v"
    debug_curl=

    if [[ ${POPULATE_RELEASE_DEBUG} == "curl" ]] ; then
      debug_curl="y"
    elif [[ ${POPULATE_RELEASE_DEBUG} == "curl_only" ]] ; then
      debug=
      debug_curl="y"
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "\<curl\>") != "" ]] ; then
      debug_curl="y"
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

  if [[ ${POPULATE_RELEASE_TARGET} != "" ]] ; then
    target=$(echo ${POPULATE_RELEASE_TARGET} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_FLOWER} != "" ]] ; then
    flower=$(echo ${POPULATE_RELEASE_FLOWER} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_REPOSITORY} != "" ]] ; then
    repository=$(echo ${POPULATE_RELEASE_REPOSITORY} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
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

  source="$(echo ${repository} | sed -e 's|//*|/|g' -e 's|/*$|/|')${part}${target}/${file}"
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
  local file=
  local i=
  local source=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  for i in ${files} ; do
    file=${i}

    echo
    echo "Operating on ${file}."

    pop_rel_load_source

    pop_rel_process_files_releases_prepare

    pop_rel_process_files_releases_curl

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done
}

pop_rel_process_files_releases_curl() {
  local i=
  local release=
  local version=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ ${releases} == "" ]] ; then
    echo "Done: No releases to fetch from."

    return
  fi

  source="$(echo ${repository} | sed -e 's|//*|/|g' -e 's|/*$|/|')${part}${target}/${file}"

  for i in ${releases} ; do

    # Skip any files without the dash in the name used to provide a version.
    if [[ $(echo ${i} | grep -sho '-') == "" ]] ; then
      continue
    fi

    if [[ -f ${destination}${flower}/${i} ]] ; then
      if [[ ${debug} != "" ]] ; then
        echo "${p_d}Skipping existing Module Descriptor: ${destination}${flower}/${i} ."
        echo
      fi

      continue
    fi

    if [[ ${debug} != "" ]] ; then
      echo "${p_d}Curl requesting Module Descriptor ${i} from: ${registry}${i} ."
      echo
    else
      echo "Curl requesting Module Descriptor: ${i}."
    fi

    pop_rel_print_curl_debug "Executing Descriptor" "curl -w '\n' ${curl_fail} ${debug} ${registry}${i} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${flower}/${i}"

    curl -w '\n' ${curl_fail} ${debug} ${registry}${i} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${flower}/${i}

    pop_rel_handle_result "${p_e}Curl request failed (with system code ${?}) for: ${registry}${i} to ${destination}${flower}/${i}."

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
    releases=$(jq -M '.[].id' ${file} | sed -e 's|"||g')
  fi

  if [[ ! -d ${destination}${flower}/ ]] ; then
    mkdir ${debug} -p ${destination}${flower}/

    pop_rel_handle_result "${p_e}Create directory failed (with system code ${?}) for destination: ${destination}${flower}/ ."
  fi
}

pop_rel_process_sources() {
  local file=
  local i=
  local source=

  if [[ ${result} -ne 0 ]] ; then return ; fi

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

    pop_rel_handle_result "${p_e}Create file failed (with system code ${?}) for install file: ${file} ."
  fi
}

pop_rel_process_sources_curl() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  pop_rel_print_curl_debug "Executing Package" "curl -w '\n' ${curl_fail} ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}"

  curl -w '\n' ${curl_fail} ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}

  pop_rel_handle_result "${p_e}Curl request failed (with system code ${?}) for: ${source} ."
}

pop_rel_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${1}"
    echo
  fi
}

main $*
