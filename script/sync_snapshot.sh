#!/bin/bash
#
# Identify whether or not changes are detected and perform git push using the given key.
#
# This requires the following user-space programs:
#   - bash
#   - grep
#   - git
#
#  Parameters:
#    1) (optional) A message to use for the Git commit.
#
#  Environment Variables:
#    SYNC_SNAPSHOT_DEBUG:   Enable debug verbosity, any non-empty string is enables this.
#    SYNC_SNAPSHOT_MESSAGE: Specify a custom message to use for the commit.
#    SYNC_SNAPSHOT_PATH:    Designate a path in which to analyze (default is an empty string, which means current directory).
#    SYNC_SNAPSHOT_SIGN:    Set to "yes" to explicitly sign, set to "no" to explicitly not sign, and do not set (or set to empty string) to use user-space default.
#
# The SYNC_SNAPSHOT_DEBUG may be specifically set to "git" to include printing the git commands.
# The SYNC_SNAPSHOT_DEBUG may be specifically set to "git_only" to only print the git commands, disabling all other debugging (does not pass -v to git).
# Otherwise, any non-empty value will result in debug printing without the git command.
#

main() {
  local debug=
  local debug_git=
  local path=
  local signoff=
  local changes=
  local message="Synchronize Snapshot Update."

  # Custom prefixes for debug and error.
  local p_d="DEBUG: "
  local p_e="ERROR: "

  local -i result=0

  if [[ ${1} != "" ]] ; then
    message=${1}
  fi

  if [[ ${SYNC_SNAPSHOT_DEBUG} != "" ]] ; then
    debug="-v"

    if [[ ${SYNC_SNAPSHOT_DEBUG} == "git" ]] ; then
      debug_git="y"
    elif [[ ${SYNC_SNAPSHOT_DEBUG} == "git_only" ]] ; then
      debug=""
      debug_git="y"
    elif [[ $(echo ${SYNC_SNAPSHOT_DEBUG} | grep -sho "_only") != "" ]] ; then
      debug=""
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

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      echo "${p_e}Failed (with system code ${result}) to change to path: ${path} ."

      return ${result}
    fi
  fi

  if [[ ${debug_git} != "" ]] ; then
    print_git_debug "Determining" "git status --porcelain --untracked-files=yes | grep '.*' -sho"
  fi

  changes=$(git status --porcelain --untracked-files=yes | grep '.*' -sho)

  if [[ ${changes} == "" ]] ; then
    echo "Done: No changes to commit detected."
  else
    if [[ ${debug_git} != "" ]] ; then
      print_git_debug "Adding" "git add -A ${debug}"
    fi

    git add -A ${debug}

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      print_git_error "adding"

      return ${result}
    fi

    if [[ ${debug_git} != "" ]] ; then
      print_git_debug "Committing" "git commit -m \"${message}\" ${signoff} ${debug}"
    fi

    git commit -m "${message}" ${signoff} ${debug}

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      print_git_error "committing"

      return ${result}
    fi

    if [[ ${debug_git} != "" ]] ; then
      print_git_debug "Pushing" "git push ${debug}"
    fi

    git push ${debug}

    let result=$?
    if [[ ${result} -ne 0 ]] ; then
      print_git_error "pushing"

      return ${result}
    fi

    echo "Done: Pushed detected changes."
  fi

  return 0
}

print_git_debug() {
  echo "${p_d}${1} Git Changes: ${2} ."
  echo
}

print_git_error() {
  echo "${p_e}Git failed (with system code ${result}) when ${1} changes."
}

main $*
