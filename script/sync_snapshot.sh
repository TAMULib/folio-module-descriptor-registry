#!/bin/bash
#
# Identify whether or not changes are detected and perform git push using the given key.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - git
#
# See the repository `README.md` for the listing of the environment variables and parameters.
#
# The SYNC_SNAPSHOT_DEBUG may be specifically set to "git" to include printing the git commands.
# The SYNC_SNAPSHOT_DEBUG may be specifically set to "git_only" to only print the git commands, disabling all other debugging (does not pass -v to git).
#
# If SYNC_SNAPSHOT_RESULT is a non-empty string, then on handled exit the contents of the specified file name will be "none" for no updates, "updated" for updates", and "failure" on error.
#

main() {
  local debug=
  local debug_git=
  local path=
  local signoff=
  local changes=
  local message="Synchronize Snapshot Update."
  local updated="none"

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  sync_snap_load_environment

  sync_snap_determine

  if [[ ${changes} != "" ]] ; then
    sync_snap_commit

    sync_snap_push
  fi

  if [[ ${result} -ne 0 ]] ; then
    updated="failure"
  elif [[ ${updated} == "none" ]] ; then
    echo
    echo "Done: No changes to commit detected."
  else
    echo
    echo "Done: Pushed detected changes."
  fi

  if [[ ${SYNC_SNAPSHOT_RESULT} != "" ]] ; then
    echo -n ${updated} > ${SYNC_SNAPSHOT_RESULT}
  fi

  return ${result}
}

sync_snap_commit() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  sync_snap_print_git_debug "Committing" "git commit -m \"${message}\" ${signoff} ${debug}"

  git commit -m "${message}" ${signoff} ${debug}

  sync_snap_handle_result_git "committing"
}

sync_snap_determine() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  sync_snap_print_git_debug "Determining" "git status --porcelain --untracked-files"

  changes=$(git status --porcelain --untracked-files)

  if [[ ${changes} != "" ]] ; then
    updated="updates"

    sync_snap_print_git_debug "Adding" "git add -A ${debug}"

    git add -A ${debug}

    sync_snap_handle_result_git "adding"
  fi
}

sync_snap_handle_result() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}${1} (system code ${result})."
    echo
  fi
}

sync_snap_handle_result_git() {
  let result=${?}

  if [[ ${result} -ne 0 ]] ; then
    echo "${p_e}Git failed when ${1} changes (system code ${result})."
  fi
}

sync_snap_load_environment() {

  if [[ ${SYNC_SNAPSHOT_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ $(echo ${SYNC_SNAPSHOT_DEBUG} | grep -sho "^\s*git\s*$") != "" ]] ; then
      debug_git="y"
    elif [[ $(echo ${SYNC_SNAPSHOT_DEBUG} | grep -sho "^\s*git_only\s*$") != "" ]] ; then
      debug=
      debug_git="y"
    elif [[ $(echo ${SYNC_SNAPSHOT_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=
    elif [[ $(echo ${SYNC_SNAPSHOT_DEBUG} | grep -sho "\<git\>") != "" ]] ; then
      debug_git="y"
    fi
  fi

  if [[ ${SYNC_SNAPSHOT_MESSAGE} != "" ]] ; then
    message="${SYNC_SNAPSHOT_MESSAGE}"
  fi

  if [[ ${SYNC_SNAPSHOT_PATH} != "" ]] ; then
    path="${SYNC_SNAPSHOT_PATH}"
  fi

  if [[ ${SYNC_SNAPSHOT_SIGN} == "yes" ]] ; then
    signoff="--no-signoff"
  elif [[ ${SYNC_SNAPSHOT_SIGN} == "no" ]] ; then
    signoff="--signoff"
  fi

  if [[ ${path} != "" ]] ; then
    cd ${path}

    sync_snap_handle_result "Failed to change to path: ${path}"
  fi
}

sync_snap_print_git_debug() {

  if [[ ${debug_git} == "" ]] ; then return ; fi

  echo "${p_d}${1} Git Changes: ${2} ."
  echo
}

sync_snap_push() {

  if [[ ${result} -ne 0 ]] ; then return ; fi

  sync_snap_print_git_debug "Pushing" "git push ${debug}"

  git push ${debug}

  sync_snap_handle_result_git "pushing"
}

main ${*}
