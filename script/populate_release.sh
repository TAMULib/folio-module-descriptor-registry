#!/bin/bash
#
# Populate a release directory based on a platform-complete release tag.
#
# This requires the following user-space programs:
#   - bash
#   - curl
#   - grep
#   - sed
#
#  Parameters:
#    1) (optional) The GitHub release tag (target), such as "R1-2024-csp-9" (If not needed but (2) is, then set this to an empty string).
#    2) (optional) The Flower release name, such as "quesnelia" or "snapshot", used to create the destination directory.
#
#  Environment Variables:
#    POPULATE_RELEASE_DEBUG:           Enable debug verbosity, any non-empty string is enables this.
#    POPULATE_RELEASE_DESTINATION:     Destination parent directory.
#    POPULATE_RELEASE_FILE:            The name of the install.json file as it is stored locally after GET fetching.
#    POPULATE_RELEASE_FILE_REUSE:      Enable re-using existing install.json file without GET fetching, any non-empty string is enables this.
#    POPULATE_RELEASE_FLOWER:          The Flower release name; If specified, then the associated parameter is ignored.
#    POPULATE_RELEASE_REGISTRY:        The URL to GET the module descriptor from for some specific module version.
#    POPULATE_RELEASE_REPOSITORY:      The raw GitHub repository URL to fetch from (but without the URL parts after the repository name).
#    POPULATE_RELEASE_REPOSITORY_PART: The part of the Github repository URL specifying the tag, branch, or hash (but without either the specific tag/branch name or the file path).
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

main() {
  local debug=
  local debug_curl=
  local registry="https://folio-registry.dev.folio.org/_/proxy/modules/"
  local destination="release/"
  local file="install.json"
  local i=
  local part="heads"
  local target="snapshot"
  local flower="snapshot"
  local repository="https://raw.githubusercontent.com/folio-org/platform-complete/"
  local releases=
  local source=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  if [[ ${1} != "" ]] ; then
    target=$(echo ${1} | sed -e 's|/||g')
  fi

  if [[ ${2} != "" ]] ; then
    flower=$(echo ${2} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_DEBUG} != "" ]] ; then
    debug="-v"
    debug_curl=""

    if [[ ${POPULATE_RELEASE_DEBUG} == "curl" ]] ; then
      debug_curl="y"
    elif [[ ${POPULATE_RELEASE_DEBUG} == "curl_only" ]] ; then
      debug=""
      debug_curl="y"
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=""
    elif [[ $(echo ${POPULATE_RELEASE_DEBUG} | grep -sho "\<curl\>") != "" ]] ; then
      debug_curl="y"
    fi
  fi

  if [[ ${POPULATE_RELEASE_DESTINATION} != "" ]] ; then
    destination=$(echo ${POPULATE_RELEASE_DESTINATION} | sed -e 's|/*$|/|g')
  fi

  if [[ ${POPULATE_RELEASE_FILE} != "" ]] ; then
    file=$(echo ${POPULATE_RELEASE_FILE} | sed -e 's|/*$||')
  fi

  if [[ ${POPULATE_RELEASE_REGISTRY} != "" ]] ; then
    registry=$(echo ${POPULATE_RELEASE_REGISTRY} | sed -e 's|/*$|/|g')
  fi

  if [[ ${POPULATE_RELEASE_TARGET} != "" ]] ; then
    target=$(echo ${POPULATE_RELEASE_TARGET} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_FLOWER} != "" ]] ; then
    flower=$(echo ${POPULATE_RELEASE_FLOWER} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_REPOSITORY} != "" ]] ; then
    repository=$(echo ${POPULATE_RELEASE_REPOSITORY} | sed -e 's|/*$|/|g')
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v POPULATE_RELEASE_REPOSITORY_PART ]] ; then
    part=${POPULATE_RELEASE_REPOSITORY_PART}
  fi

  if [[ ${part} != "" ]] ; then
    part="refs/$(echo ${part} | sed -e 's|/*$|/|g')"
  fi

  source="$(echo ${repository} | sed -e 's|/*$|/|')${part}${target}/${file}"

  if [[ ${POPULATE_RELEASE_FILE_REUSE} != "" ]] ; then
    if [[ ! -f ${file} ]] ; then
      echo "${p_e}The install JSON file is either missing or is not a regular file: ${file} ."

      return 1
    fi
  else
    if [[ ${debug} != "" ]] ; then
      echo "${p_d}Curl requesting Install JSON from: ${source} ."
      echo
    fi

    if [[ -e ${file} ]] ; then
      rm ${debug} -f ${file}

      let result=$?
      if [[ ${result} -ne 0 ]] ; then
        echo "${p_e}Create file failed (with system code ${result}) for install file: ${file} ."

        return ${result}
      fi
    fi

    if [[ ${debug_curl} != "" ]] ; then
      echo "${p_d}Executing Package Curl: curl -w '\n' ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file} ."
      echo
    fi

    curl -w '\n' ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      echo "${p_e}Curl request failed (with system code ${result}) for: ${source} ."

      return ${result}
    fi
  fi

  if [[ -f ${file} ]] ; then
    releases=$(grep -shr '"id" : "' ${file} | sed -e 's|^.*"id" : "||g' -e 's|",$||g')
  fi

  if [[ ! -d ${destination}${flower}/ ]] ; then
    mkdir ${debug} -p ${destination}${flower}/

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      echo "${p_e}Create directory failed (with system code ${result}) for destination: ${destination}${flower}/ ."

      return ${result}
    fi
  fi

  if [[ ${releases} == "" ]] ; then
    echo "Done: No releases to fetch from."
  else
    for i in ${releases} ; do

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

      if [[ ${debug_curl} != "" ]] ; then
        echo "${p_d}Executing Descriptor Curl: curl -w '\n' ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file} ."
        echo
      fi

      curl -w '\n' ${debug} ${registry}${i} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${flower}/${i}

      let result=$?
      if [[ ${result} -ne 0 ]] ; then
        echo "${p_e}Curl request failed (with system code ${result}) for: ${registry}${i} to ${destination}${flower}/${i}."

        return ${result}
      fi
    done

    echo "Done: Module descriptors fetched as needed."
  fi

  return 0
}

main $*
