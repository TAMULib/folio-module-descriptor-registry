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
#    1) (optional) The GitHub release tag, such as "R1-2024-csp-9" (If not needed but (2) is, then set this to an empty string).
#    2) (optional) The Flower release name, such as "quesnelia".
#
#  Environment Variables:
#    POPULATE_RELEASE_DESTINATION:    Destination parent directory.
#    POPULATE_RELEASE_FILE:           The name of the install.json file as it is stored locally after GET fetching.
#    POPULATE_RELEASE_FILE_REUSE:     Enable re-using existing install.json file without GET fetching, any non-empty string is enables this.
#    POPULATE_RELEASE_REGISTRY:       The URL to GET the module descriptor from for some specific module version.
#    POPULATE_RELEASE_RELEASE:        The GitHub release tag; If specified, then the associated parameter is ignored.
#    POPULATE_RELEASE_RELEASE_DEBUG:  Enable debug verbosity, any non-empty string is enables this.
#    POPULATE_RELEASE_RELEASE_FLOWER: The Flower release name; If specified, then the associated parameter is ignored.
#    POPULATE_RELEASE_REPOSITORY:     The GitHub repository URL to fetch from, down to the tags (but without the specific tag name).
#
# Note: It might be possible to swap out POPULATE_RELEASE_REPOSITORY and POPULATE_RELEASE_RELEASE with a branch name rather than a tag name.
#

main() {
  local debug=
  local registry="https://folio-registry.dev.folio.org/_/proxy/modules/"
  local destination="release/"
  local file="install.json"
  local i=
  local release=$(echo ${1} | sed -e 's|/||g')
  local release_flower=$(echo ${2} | sed -e 's|/||g')
  local repository="https://raw.githubusercontent.com/folio-org/platform-complete/refs/tags/"
  local releases=
  local source=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  if [[ ${POPULATE_RELEASE_RELEASE_DEBUG} != "" ]] ; then
    debug="-v"
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

  if [[ ${POPULATE_RELEASE_RELEASE} != "" ]] ; then
    release=$(echo ${POPULATE_RELEASE_RELEASE} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_RELEASE_FLOWER} != "" ]] ; then
    release_flower=$(echo ${POPULATE_RELEASE_RELEASE_FLOWER} | sed -e 's|/||g')
  fi

  if [[ ${POPULATE_RELEASE_REPOSITORY} != "" ]] ; then
    repository=$(echo ${POPULATE_RELEASE_REPOSITORY} | sed -e 's|/*$|/|g')
  fi

  source="$(echo ${repository} | sed -e 's|/*$|/|')${release}/install.json"

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

    curl -w '\n' ${debug} ${source} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${file}

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      echo "${p_e}Curl request failed (with system code ${result}) for: ${source} ."

      return ${result}
    fi
  fi

  if [[ -f ${file} ]] ; then
    releases=$(grep -shnr '"id" : "' install.json | sed -e 's|^.*"id" : "||g' -e 's|",$||g')
  fi

  if [[ ! -d ${destination}${release_flower}/ ]] ; then
    mkdir ${debug} -p ${destination}${release_flower}/

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      echo "${p_e}Create directory failed (with system code ${result}) for destination: ${destination}${release_flower}/ ."

      return ${result}
    fi
  fi

  if [[ ${releases} != "" ]] ; then
    for i in ${releases} ; do

      if [[ -f ${destination}${release_flower}/${i} ]] ; then
        if [[ ${debug} != "" ]] ; then
          echo "${p_d}Skipping existing Module Descriptor: ${destination}${release_flower}/${i} ."
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

      curl -w '\n' ${debug} ${registry}${i} -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -o ${destination}${release_flower}/${i}

      let result=$?
      if [[ ${result} -ne 0 ]] ; then
        echo "${p_e}Curl request failed (with system code ${result}) for: ${registry}${i} to ${destination}${release_flower}/${i}."

        return ${result}
      fi
    done
  fi

  return 0
}

main $*
