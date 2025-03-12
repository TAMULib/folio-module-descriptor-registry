#!/bin/bash
#
# Build a simple index listing of the descriptors using minimal HTML and script-based templating.
#
# This requires the following user-space programs:
#   - bash
#   - basename
#   - cat
#   - cp
#   - date
#   - grep
#   - jq
#   - ls
#   - mkdir
#   - sed
#
#  Parameters:
#    *) All descriptor source directories to process. This script uses simple logic, be careful about sub-directory naming conflicts.
#
#  Environment Variables:
#    BUILD_PAGES_BASE:           The base URL where the generated pages are stored.
#    BUILD_PAGES_DEBUG:          Enable debug verbosity, any non-empty string enables this.
#    BUILD_PAGES_IGNORE_INVALID: Ignore non-JSON files rather than fail, any non-empty string enables this.
#    BUILD_PAGES_TEMPLATE_BACK:  The name of the back HTML template within the BUILD_PAGES_TEMPLATE_PATH directory.
#    BUILD_PAGES_TEMPLATE_BASE:  The name of the base HTML template within the BUILD_PAGES_TEMPLATE_PATH directory.
#    BUILD_PAGES_TEMPLATE_ITEM:  The name of the item HTML template within the BUILD_PAGES_TEMPLATE_PATH directory.
#    BUILD_PAGES_TEMPLATE_PATH:  The path to the template directory containing the HTML template files.
#    BUILD_PAGES_WORK:           A working directory used to create the gh-pages structure (all templates and files are added here).
#
# The BUILD_PAGES_DEBUG may be specifically set to "json" to include printing the JSON files.
# The BUILD_PAGES_DEBUG may be specifically set to "json_only" to only print the JSON files, disabling all other debugging (does not pass -v).
# Otherwise, any non-empty value will result in debug printing without the git command.
# The BUILD_PAGES_DEBUG may be specifically set to "verify" to include printing the individual verify/process file messages.
# The BUILD_PAGES_DEBUG may be specifically set to "verify_only" to only print the the individual verify/process file messages, disabling all other debugging (does not pass -v).
# Otherwise, any non-empty value will result in debug printing without the git command.
#
# If any of BUILD_PAGES_TEMPLATE_BASE, BUILD_PAGES_TEMPLATE_ITEM, or BUILD_PAGES_TEMPLATE_PATH are not specified, then the default is loaded for each unspecified variable.
#

main() {
  local base="/folio-module-descriptor-registry/"
  local debug=
  local debug_json=
  local debug_verify=
  local i=
  local ignore_invalid=
  local now=$(date -u)
  local sources=
  local title_main="Listing of FOLIO Releases"
  local template_back="back.html"
  local template_back_data=
  local template_base="base.html"
  local template_item="item.html"
  local template_item_data=
  local template_path="template/"
  local work="work/"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  build_page_load_environment ${*}

  build_page_operate

  return ${result}
}

build_page_load_environment() {
  local file=
  local parameter=
  local total=

  if [[ ${BUILD_PAGES_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ ${BUILD_PAGES_DEBUG} == "json" ]] ; then
      debug_json="y"
    elif [[ ${BUILD_PAGES_DEBUG} == "verify" ]] ; then
      debug_verify="y"
    elif [[ ${BUILD_PAGES_DEBUG} == "json_only" ]] ; then
      debug=
      debug_json="y"
    elif [[ $(echo ${BUILD_PAGES_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    else
      if [[ $(echo ${BUILD_PAGES_DEBUG} | grep -sho "\<json\>") != "" ]] ; then
        debug_json="y"
      fi

      if [[ $(echo ${BUILD_PAGES_DEBUG} | grep -sho "\<verify\>") != "" ]] ; then
        debug_verify="y"
      fi
    fi
  fi

  # May be empty, so use "-v" test rather than != "".
  if [[ -v BUILD_PAGES_BASE ]] ; then
    if [[ $(echo ${BUILD_PAGES_BASE} | sed -e "s|\s||g") == "" ]] ; then
      base=
    else
      base=$(echo ${BUILD_PAGES_BASE} | sed -e 's|/*$|/|g')
    fi
  fi

  if [[ ${BUILD_PAGES_IGNORE_INVALID} != "" ]] ; then
    ignore_invalid="y"
  fi

  if [[ ${BUILD_PAGES_TEMPLATE_BACK} != "" ]] ; then
    template_back=$(echo ${BUILD_PAGES_TEMPLATE_BACK} | sed -e 's|//*|/|g' -e 's|/*$||g')
  fi

  if [[ ${BUILD_PAGES_TEMPLATE_BASE} != "" ]] ; then
    template_base=$(echo ${BUILD_PAGES_TEMPLATE_BASE} | sed -e 's|//*|/|g' -e 's|/*$||g')
  fi

  if [[ ${BUILD_PAGES_TEMPLATE_ITEM} != "" ]] ; then
    template_item=$(echo ${BUILD_PAGES_TEMPLATE_ITEM} | sed -e 's|//*|/|g' -e 's|/*$||g')
  fi

  if [[ ${BUILD_PAGES_TEMPLATE_PATH} != "" ]] ; then
    template_path=$(echo ${BUILD_PAGES_TEMPLATE_PATH} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ ! -d ${template_path} ]] ; then
    echo "${p_e}The following path is not a valid template directory: ${template_path} ."

    let result=1
  else
    if [[ ! -f ${template_path}${template_back} ]] ; then
      echo "${p_e}The following path is not a valid back template file: ${template_path}${template_back} ."

      let result=1
    fi

    if [[ ! -f ${template_path}${template_base} ]] ; then
      echo "${p_e}The following path is not a valid base template file: ${template_path}${template_base} ."

      let result=1
    fi

    if [[ ! -f ${template_path}${template_item} ]] ; then
      echo "${p_e}The following path is not a valid item template file: ${template_path}${template_item} ."

      let result=1
    fi
  fi

  if [[ ${BUILD_PAGES_WORK} != "" ]] ; then
    work=$(echo ${BUILD_PAGES_WORK} | sed -e 's|//*|/|g' -e 's|/*$|/|g')
  fi

  if [[ -e ${work} && ! -d ${work} ]] ; then
    echo "${p_e}The following path is not a valid work directory: ${work} ."

    let result=1
  fi

  if [[ ${result} -ne 0 ]] ; then return ; fi

  template_back_data=$(cat ${template_path}${template_back})
  template_item_data=$(cat ${template_path}${template_item})

  if [[ ! -d ${work} ]] ; then
    mkdir ${debug} -p ${work}

    build_page_handle_result "Failed to create work directory: ${work}"
  fi

  if [[ ${result} -eq 0 && ${#} -gt 0 ]] ; then
    total=${#}

    while [[ ${i} -lt ${total} ]] ; do
      let i=${i}+1
      parameter=${!i}

      file=$(echo ${parameter} | sed -e 's|//*|/|' -e 's|/*$|/|')

      if [[ ! -d ${file} ]] ; then
        echo "${p_e}The following path is not a valid descriptor source directory: ${file} ."

        let result=1

        return
      fi

      sources="${sources}${file} "
    done
  fi
}

build_page_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${1}"
  fi
}

build_page_operate() {
  local indexes=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  build_page_operate_sources

  build_page_operate_sources_process_index "${work}/index.html" "${title_main}" "${indexes}"

  if [[ ${result} -ne 0 ]] ; then return ; fi

  echo
  echo "Done: Pages are built."
}

build_page_operate_sources() {
  local source=
  local j=
  local k=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  for i in ${sources} ; do

    echo
    echo "Operating on source: ${i} ."

    if [[ $(ls ${i}) != "" ]] ; then
      for j in ${i}* ; do
        source=$(basename ${j})

        build_page_operate_sources_process_index_template_item

        echo
        echo "Operating on source ${i} work source sub-directory: ${source} ."

        mkdir ${debug} -p ${work}${source}

        build_page_handle_result "Failed to create work source sub-directory: ${work}${source}"

        if [[ ${result} -ne 0 ]] ; then break ; fi
        if [[ $(ls ${j}/) == "" ]] ; then continue ; fi

        build_page_operate_sources_process_files

        if [[ ${result} -ne 0 ]] ; then break ; fi
      done
    fi

    if [[ ${result} -ne 0 ]] ; then break ; fi
  done
}

build_page_operate_sources_process_files() {
  local file=
  local files=
  local items=
  local k=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  for k in ${j}/* ; do
    file=$(basename ${k})

    if [[ $(echo -n ${file} | grep -sho "^\.") != "" ]] ; then
      build_page_print_debug_verify "Skipping work source sub-directory ${source} hidden file: ${file}"

      continue
    fi

    if [[ -d ${k} ]] ; then
      build_page_print_debug_verify "Skipping work source sub-directory ${source} directory file: ${file}"

      continue
    fi

    build_page_print_debug_verify "Verifying work source sub-directory ${source} file: ${file}"

    if [[ ! -f ${k} ]] ; then
      let result=1
    fi

    build_page_operate_sources_process_files_verify_file

    build_page_operate_sources_process_files_copy_file

    build_page_operate_sources_process_files_template_item "${source}/${file}" "${file}"

    # Reset error for each loop pass, the problems represents the final error state.
    if [[ ${result} -ne 0 ]] ; then
      problems="${problems}${k} "

      let result=0
    fi
  done

  if [[ ${problems} != "" ]] ; then
    echo "${p_e}Build Path failed, the following files are missing, invalid, or failed to be processed: ${problems}."

    let result=1
  fi

  build_page_operate_sources_process_index "${work}${source}/index.html" "Listing of ${source} Release" "${items}" yes
}

build_page_operate_sources_process_files_copy_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  cp ${debug} ${k} ${work}${source}/${file}

  build_page_handle_result "Failed to copy ${k} to ${work}${source}/${file}"
}

build_page_operate_sources_process_files_template_item() {
  local item=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  item=$(echo ${template_item_data} | sed -e "s|\<_REPLACE_LINK_\>|${source}/${file}|g" -e "s|\<_REPLACE_LINK_NAME_\>|${file}|g")
  items="${items}${item}_REPLACE_EOL_ "
}

build_page_operate_sources_process_files_verify_file() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  # Prevent jq from printing JSON if /dev/null exists when not debugging.
  if [[ ${debug_json} != "" || ! -e /dev/null ]] ; then
    cat ${k} | jq
  else
    cat ${k} | jq >> /dev/null
  fi

  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    if [[ ${ignore_invalid} != "" ]] ; then
      build_page_print_debug "Ignoring work source sub-directory ${source} invalid JSON file: ${file}"

      let result=0
    fi
  fi
}

build_page_operate_sources_process_index() {
  local index=${1}
  local title=${2}
  local snippet=${3}
  local back=${4}

  if [[ ${result} -ne 0 ]] ; then return ; fi

  if [[ $(echo ${snippet} | sed -e "s|\s||g") == "" ]] ; then
    snippet="There are no items available."
  fi

  if [[ ${back} != "" ]] ; then
    if [[ $(echo ${template_back_data} | sed -e "s|\s||g") == "" ]] ; then
      back=
    else
      back=$(echo ${template_back_data} | sed -e "s|\<_REPLACE_LINK_\>||g" -e "s|\<_REPLACE_SECTION_TITLE_\>|${title_main}|g")
    fi
  fi

  cp ${debug} ${template_path}${template_base} ${index}

  build_page_handle_result "Failed to copy ${template_path}${template_item} to ${index}"

  if [[ ${result} -ne 0 ]] ; then return ; fi

  sed -i \
    -e "s|\<_REPLACE_BASE_PATH_\>|${base}|g" \
    -e "s|\<_REPLACE_PAGE_BACK_\>|${back}|g" \
    -e "s|\<_REPLACE_PAGE_TITLE_\>|${title}|g" \
    -e "s|\<_REPLACE_SECTION_TITLE_\>|${title}|g" \
    -e "s|\<_REPLACE_SECTION_DATE_\>|${now}|g" \
    -e "s|\<_REPLACE_SECTION_SNIPPET_\>|${snippet}|g" \
    -e "s|\s*\<_REPLACE_EOL_\>\s*|\n|g" \
    ${index}

  build_page_handle_result "Failed to expand template variables in ${index}"
}

build_page_operate_sources_process_index_template_item() {
  local item=

  if [[ ${result} -ne 0 ]] ; then return ; fi

  item=$(echo ${template_item_data} | sed -e "s|\<_REPLACE_LINK_\>|${source}/|g" -e "s|\<_REPLACE_LINK_NAME_\>|${source}|g")
  indexes="${indexes}${item}_REPLACE_EOL_ "
}

build_page_print_debug() {

  if [[ ${debug} == "" ]] ; then return ; fi

  echo "${p_d}${1} ."
  echo
}

build_page_print_debug_verify() {

  if [[ ${debug_verify} == "" ]] ; then return ; fi

  echo
  echo "${p_d}${1} ."
}

main ${*}
