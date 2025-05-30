#!/bin/bash
#
# Populate a location JSON file to help provide which repository to use for which backend or edge module.
#
# This requires the following user-space programs:
#   - bash
#   - curl
#   - grep
#   - jq
#   - sed
#   - sleep (This is not required if BUILD_LOCATION_DELAY is set to "0".)
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The BUILD_LOCATION_DEBUG may be specifically set to "json" to include printing the JSON files.
# The BUILD_LOCATION_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
#
# The BUILD_LOCATION_DEBUG may be specifically set to "curl" to include printing the curl commands.
# The BUILD_LOCATION_DEBUG may be specifically set to "curl_only" to only print the curl commands, disabling all other debugging (does not pass -v to curl).
#
# Important information regarding services such as dockerhub:
#   There are rate limits being applied, such as 100 requests allowed every 6 hours for GET requests.
#   However, there are no such limits for HEAD requests (which are therefore).
#   Using GitHub Actions still requires logging in and having credentials, even if using HEAD requests.
#   These credentials are operated using GET requests.
#
#   To be on the safe side, the default requests is still set to 100.
#   This can be changed using the BUILD_LOCATION_LIMIT.
#
#   see: https://docs.docker.com/docker-hub/usage/
#   see: https://docs.docker.com/docker-hub/usage/pulls/
#   see: https://docs.docker.com/docker-hub/usage/pulls/#github-actions
#   see: https://docs.docker.com/docker-hub/usage/pulls/#kubernetes
#   see: https://docs.docker.com/docker-hub/usage/manage/
#

main() {
  local debug=
  local debug_curl=
  local debug_json=
  local delay="0.3s"
  local destination="location/"
  local destination_flower=
  local files="install.json eureka-platform.json"
  local flower="snapshot"
  local null="/dev/null"
  local releases=
  local repositories=
  local repositories_file="repositories.json"
  local repositories_path="template/location/"
  local repositories_json=

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -A tags=
  local -A repositories_auth_url=
  local -A repositories_auth_registry=
  local -A repositories_name=
  local -A repositories_request_url=

  local -i limit=100
  local -i result=0

  build_location_load_environment

  build_location_verify_json "repositories file" ${repositories_json}
  build_location_verify_files

  build_location_load_repositories
  build_location_load_releases

  build_location_operate

  return ${result}
}

build_location_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

build_location_load_environment() {
  local file=
  local repository=
  local i=

  if [[ ${BUILD_LOCATION_DEBUG} != "" ]] ; then
    debug="-v"
    debug_curl=
    debug_json=

    if [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "^\s*curl\s*$") != "" ]] ; then
      debug_curl="-v"
    elif [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "^\s*curl_only\s*$") != "" ]] ; then
      debug=
      debug_curl="-v"
    elif [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "^\s*json\s*$") != "" ]] ; then
      debug_json="y"
    elif [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "^\s*json_only\s*$") != "" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "\<curl\>") != "" ]] ; then
        debug_curl="-v"
      fi

      if [[ $(echo ${BUILD_LOCATION_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi
    fi
  fi

  if [[ ${BUILD_LOCATION_DELAY} != "" ]] ; then
    let delay=${BUILD_LOCATION_DELAY}
  fi

  if [[ ${delay} == "" ]] ; then
    echo "${p_e}The delay must not be an empty string (a value of '0' can be used to disable delay)."

    let result=1

    return
  fi

  if [[ $(echo ${BUILD_LOCATION_FILES} | sed -e 's|\s||g') != "" ]] ; then
    files=

    for i in ${BUILD_LOCATION_FILES} ; do
      file=$(echo ${i} | sed -e 's|//*|/|g' -e 's|/*$||')

      if [[ -f ${file} ]] ; then
        build_location_print_debug "Using File: ${file}"

        files="${files}${file} "
      else
        echo "${p_e}The following path is not a valid file: ${file} ."

        let result=1

        return
      fi
    done

    file=
  fi

  if [[ ${BUILD_LOCATION_REPOSITORIES_NAME} != "" ]] ; then
    repositories_file=${BUILD_LOCATION_REPOSITORIES_NAME}

    if [[ $(echo ${repositories_file} | grep -sho "[/\]") != "" ]] ; then
      echo "${p_e}The repositories name must not have slashes: ${repositories_file} ."

      let result=1

      return
    fi
  fi

  if [[ ${BUILD_LOCATION_REPOSITORIES_PATH} != "" ]] ; then
    repositories_path=$(echo ${BUILD_LOCATION_REPOSITORIES_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|')
  fi

  repositories_json=${repositories_path}${repositories_file}

  if [[ ${BUILD_LOCATION_LIMIT} != "" ]] ; then
    let limit=${BUILD_LOCATION_LIMIT}
  fi

  if [[ ${limit} -lt 0 ]] ; then
    echo "${p_e}The limit must be 0 or greater, but is instead '${limit}' ."

    let result=1

    return
  fi

  if [[ ${BUILD_LOCATION_DESTINATION} != "" ]] ; then
    destination=$(echo ${BUILD_LOCATION_DESTINATION} | sed -e 's|//*|/|g' -e 's|/*$|/|')
  fi

  if [[ ${destination} != "" ]] ; then
    destination=$(echo ${destination} | sed -e 's|/*$|/|')
  fi

  if [[ ${BUILD_LOCATION_FLOWER} != "" ]] ; then
    flower=$(echo ${BUILD_LOCATION_FLOWER} | sed -e 's|/||g')
  fi

  destination_flower="${destination}${flower}/"

  if [[ -e ${destination_flower} ]] ; then
    if [[ ! -d ${destination_flower} ]] ; then
      echo "${p_e}The destination directory is not and must be a directory: ${destination_flower} ."

      let result=1

      return
    fi
  else
    mkdir ${debug} -p ${destination_flower}

    build_location_handle_result "Failed to create destination directory path: ${destination_flower}"
  fi
}

build_location_load_releases() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=
  local i=
  local manifest=
  local release=

  for file in ${files} ; do

    build_location_load_releases_prepare

    if [[ ${result} -ne 0 ]] ; then return ; fi

    for i in ${manifest} ; do

      # Skip any files without the dash in the name used to provide a version.
      if [[ $(echo ${i} | grep -sho '-') == "" ]] ; then continue ; fi

      build_location_parse_release ${i} ${file}

      build_location_load_releases_parse_tag

      if [[ ${result} -ne 0 ]] ; then return ; fi
    done
  done
}

build_location_load_releases_parse_tag() {

  if [[ ${result} -ne 0 || ${release} == "" || ${i} == "" ]] ; then return ; fi

  local message=

  if [[ ${file} != "" ]] ; then
    message=" from JSON: ${file}"
  fi

  tags["${release}"]=$(echo -n "${i}" | sed -e "s|^${release}-||")

  build_location_handle_result "Failed to parse release tag from '${i}'${message}"
}

build_location_load_releases_prepare() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_sorted_match_specific=".[] | sort_by(.id) | .[].id | select(. | test(\"mod-|edge-\"))"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    manifest=$(jq -s -r -M "${jq_sorted_match_specific}" ${file})
  else
    manifest=$(jq -s -r -M "${jq_sorted_match_specific}" ${file} 2> ${null})
  fi

  build_location_handle_result "Failed to load release IDs from JSON: ${file}"

  releases="${releases}${manifest} "
}

build_location_load_repositories() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local repo=
  local repositories_manifest=
  local value=

  local -i i=0
  local -i repo_length=0

  build_location_load_repositories_load_manifest
  build_location_load_repositories_load_names
  build_location_load_repositories_load_length

  while [[ ${i} -lt ${repo_length} ]] ; do
    build_location_load_repositories_extract_literal id
    repo="${value}"

    build_location_load_repositories_extract_literal name
    repositories_name["${repo}"]="${value}"

    build_location_load_repositories_extract_url "auth.url"
    repositories_auth_url["${repo}"]="${value}"

    build_location_load_repositories_extract_url "request.url"
    repositories_request_url["${repo}"]="${value}"

    build_location_load_repositories_extract_domain "auth.registry"
    repositories_auth_registry["${repo}"]="${value}"

    build_location_load_repositories_verify_url "auth.url" ${repositories_auth_url["${repo}"]}
    build_location_load_repositories_verify_url "request.url" ${repositories_request_url["${repo}"]}
    build_location_load_repositories_verify_domain "auth.domain" ${repositories_auth_registry["${repo}"]}

    if [[ ${result} -ne 0 ]] ; then return ; fi

    let i++
  done
}

build_location_load_repositories_extract_domain() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}
  local jq_registry=".[${i}].${key}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_registry}")
  else
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_registry}" 2> ${null})
  fi

  build_location_handle_result "Failed to extract domain from '${key}' for the ${repo} repositories manifest (at index ${i}) from: ${repositories_json}"

  if [[ ${result} -eq 0 ]] ; then
    if [[ ${value} == "" || ${value} == "null" ]] ; then
      build_location_print_debug "Disabling domain from '${key}' because the ${repo} repositories manifest (at index ${i}) is empty or null: ${value}"

      value=
    fi
  fi
}

build_location_load_repositories_extract_url() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}
  local jq_registry=".[${i}].${key}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_registry}" | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  else
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_registry}" | sed -e 's|//*|/|g' -e 's|/*$|/|g' 2> ${null})
  fi

  build_location_handle_result "Failed to extract URL from '${key}' for the ${repo} repositories manifest (at index ${i}) from: ${repositories_json}"

  if [[ ${result} -eq 0 ]] ; then
    if [[ ${value} == "" || ${value} == "null" ]] ; then
      build_location_print_debug "Disabling URL from '${key}' because the ${repo} repositories manifest (at index ${i}) is empty or null: ${value}"

      value=
    fi
  fi
}

build_location_load_repositories_extract_literal() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local literal=${1}
  local jq_name=".[${i}].${1}"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_name}")
  else
    value=$(echo "${repositories_manifest}" | jq -r -M "${jq_name}" 2> ${null})
  fi

  build_location_handle_result "Failed to extract repositories manifest '${literal}' at index ${i} from: ${repositories_json}"

  if [[ ${result} -eq 0 && ( ${value} == "" || ${value} == "null" ) ]] ; then
    echo "${p_e}The extracted repositories manifest '${literal}' at index ${i} is an empty string from: ${repositories_json} ."

    let result=1
  fi
}

build_location_load_repositories_extract_request_url() {

  if [[ ${result} -ne 0 ]] ; then return ; fi
}

build_location_load_repositories_load_manifest() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    repositories_manifest=$(jq -M . ${repositories_json})
  else
    repositories_manifest=$(jq -M . ${repositories_json} 2> ${null})
  fi

  build_location_handle_result "Failed to load repositories manifest from: ${repositories_json}"
}

build_location_load_repositories_load_length() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_length="length"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    let repo_length=$(echo "${repositories_manifest}" | jq -r -M "${jq_length}")
  else
    let repo_length=$(echo "${repositories_manifest}" | jq -r -M "${jq_length}" 2> ${null})
  fi

  build_location_handle_result "Failed to load repositories manifest length from: ${repositories_json}"
}

build_location_load_repositories_load_names() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_names=".[].name"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    repositories=$(echo "${repositories_manifest}" | jq -r -M "${jq_names}")
  else
    repositories=$(echo "${repositories_manifest}" | jq -r -M "${jq_names}" 2> ${null})
  fi

  build_location_handle_result "Failed to load repositories manifest names from: ${repositories_json}"
}

build_location_load_repositories_verify_domain() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}
  local value=${2}

  if [[ $(echo ${value} | grep -sho '[/\:&?]') != "" ]] ; then
    echo "${p_e}The ${repo} ${key} domain value has unsupported characters ('/', '\', ':', '&', and '?'): ${value} ."

    let result=1
  fi
}

build_location_load_repositories_verify_url() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local key=${1}
  local value=${2}

  if [[ ${value} == "" ]] ; then
    echo "${p_e}The ${repo} ${key} URL value must not be empty for: ${value} ."

    let result=1
  fi
}

build_location_operate() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local destination_json=
  local i=
  local location_manifest=
  local name=
  local release=
  local repo=
  local repositories_active=${repositories}
  local request_manifest=
  local request_url=
  local requests_distinct=
  local tag=
  local token=

  local -A counts=

  local -i count=0
  local -i found=0

  # Initialize the counts.
  for repo in ${repositories} ; do
    request_url=${repositories_request_url["${repo}"]}

    if [[ ${counts["${request_url}"]} == "" ]] ; then
      requests_distinct="${requests_distinct}${repo} "
    fi

    let counts["${request_url}"]=0
  done

  for i in ${releases} ; do
    let found=0

    build_location_parse_release ${i}

    tag=${tags["${release}"]}
    destination_json="${destination_flower}${release}-${tag}.json"

    # Avoid rate limit problems by not pulling when a location file already exists.
    if [[ -f ${destination_json} ]] ; then
      build_location_print_debug "Skipping already existing location manifest for release '${release}' and tag '${tag}'"

      continue
    fi

    build_location_print_debug "Operating '${i}' with name '${release}' and tag '${tag}'"

    for repo in ${repositories_active} ; do
      name=${repositories_name["${repo}"]}
      request_manifest=
      request_url=${repositories_request_url["${repo}"]}
      token=

      if [[ ${limit} -gt 0 && ${counts["${request_url}"]} -ge ${limit} ]] ; then
        build_location_print_debug "Skipping all future '${repo}' repository requests due to reaching request rate limit of ${limit} for the request URL: ${request_url}"

        # Remove the repo from the active repositories list.
        repositories_active=$(echo "${repositories_active}" | sed -e "s|\<${repo}\>||g")

        continue
      fi

      if [[ ${repositories_auth_url["${repo}"]} != "" ]] ; then
        build_location_operate_login
      fi

      build_location_operate_request
      build_location_operate_write

      if [[ ${result} -ne 0 ]] ; then return ; fi

      let counts["${request_url}"]++

      # The process can be very fast, so add a delay to reduce abusing remote servers and to help avoid possibly getting blocked.
      if [[ ${delay} != "0" ]] ; then
        sleep "${delay}"
      fi

      if [[ ${found} -eq 1 ]] ; then break ; fi
    done

    # Terminate loop if there are no active repositories left.
    if [[ $(echo "${repositories_active}" | sed -e 's|\s||g') == "" ]] ; then break ; fi
  done

  for repo in ${requests_distinct} ; do
    request_url=${repositories_request_url["${repo}"]}
    let count=${counts["${request_url}"]}

    build_location_print_debug "A total of ${count} requests have been made to the request URL: ${request_url}"
  done
}

build_location_operate_login() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local auth_url=${repositories_auth_url["${repo}"]}
  local auth_registry=${repositories_auth_registry["${repo}"]}
  local login_url=
  local response=

  if [[ ${auth_registry} != "" ]] ; then
    auth_registry="&service=${auth_registry}"
  fi

  login_url="${auth_url}token?scope=repository:${repo}/${release}:pull${auth_registry}"

  build_location_print_debug "Executing Login: curl ${debug_curl} '${login_url}'"

  response=$(curl ${debug_curl} "${login_url}")

  build_location_handle_result "Curl request failed for repository '${repo}' and release '${release}' for: ${login_url}"

  build_location_operate_login_token
}

build_location_operate_login_token() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local jq_select_token=".token"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    token=$(echo ${response} | jq -r -M "${jq_select_token}")
  else
    token=$(echo ${response} | jq -r -M "${jq_select_token}" 2> ${null})
  fi

  build_location_handle_result "Failed to load token from response by ${login_url}"

  if [[ ${result} -eq 0 && ${token} == "" ]] ; then
    echo "${p_e}The token returned by the successful login is empty for: ${login_url} ."

    let result=1
  fi
}

build_location_operate_request() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local auth_header_value=
  local auth_header_redact=
  local full_url="${request_url}v2/${repo}/${release}/manifests/${tag}"
  local http_status=

  if [[ ${repositories_auth_url["${repo}"]} != "" ]] ; then
    auth_header_value="Authorization: Bearer ${token}"
    auth_header_redact="Authorization: Bearer (REDACTED)"
  fi

  build_location_print_debug "Executing Load Manifest: curl ${debug_curl} -I -H '${auth_header_redact}' '${full_url}'"

  request_manifest=$(curl ${debug_curl} -I -H "${auth_header_value}" ${full_url})

  build_location_handle_result "Curl request failed for repository '${repo}', release '${release}', and tag '${tag}' for: ${full_url}"

  if [[ ${result} -eq 0 ]] ; then
    http_status=$(echo ${request_manifest} | grep -shoi "^http/.*" | grep -shoi "200 ok")

    if [[ ${http_status} != "" ]] ; then
      let found=1
    fi
  fi
}

build_location_operate_write() {

  if [[ ${result} -ne 0 || ${found} -eq 0 ]] ; then return ; fi

  local release_manifest="{ \"id\": \"${release}-${tag}\", \"repository\": \"${name}\" }"

  # Prevent jq from printing JSON if ${null} exists when not debugging.
  if [[ ${debug_json} != "" || ! -e ${null} ]] ; then
    echo "${release_manifest}" | jq -M . 1> ${destination_json}
  else
    echo "${release_manifest}" | jq -M . 1> ${destination_json} 2> ${null}
  fi

  build_location_handle_result "Failed to write Location Manifest to: ${destination_json}"
}

build_location_parse_release() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local file=${2}
  local message=
  local release_with_version=${1}

  if [[ ${file} != "" ]] ; then
    message=" from JSON: ${file}"
  fi

  release=$(echo -n ${release_with_version} | sed -e "s|-SNAPSHOT*||" -e "s|-[^-]*$||" -e 's|"||g')

  build_location_handle_result "Failed to parse release name from '${release_with_version}'${message}"
}

build_location_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_location_verify_files() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  local i=
  local problems=

  if [[ ${files} != "" ]] ; then
    for i in ${files} ; do
      build_location_print_debug "Verifying File: ${i}"

      build_location_verify_json "input file" ${i} yes

      if [[ ${result} -ne 0 ]] ; then
        problems="${problems}${i} "
      fi
    done
  fi

  if [[ ${problems} != "" ]] ; then
    echo "${p_e}Build Location failed, the following are either missing or invalid files: ${problems}."

    if [[ ${result} -eq 0 ]] ; then
      let result=1
    fi
  fi
}

build_location_verify_json() {
  local name=${1}
  local file=${2}
  local special=${3} # When non-empty, designate that this function should ignore any pre-existing error state of ${result} and not print any errors.

  if [[ ${result} -ne 0 && ${special} == "" ]] ; then return ; fi

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

  if [[ ${result} -ne 0 && ${special} == "" ]] ; then
    echo "${p_e}The ${name} '${file}' does not exist or is not a valid JSON file."
    echo
  fi
}

main ${*}
