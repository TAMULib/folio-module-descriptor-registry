# FOLIO Module Descriptor Registry (MDR)

Copyright © 2025 Texas A&M University Libraries under the [MIT license](LICENSE).

The [FOLIO](https://folio.org/) module **Module Descriptor Registry** (**MDR**) provides a listing of generated module descriptors.

The **MDR** is intended to be accessed directly by [FOLIO](https://folio.org/) instances for determining what module is available to enable.

**MDR** is a simple, static, implementation of the [OKAPI](https://github.com/folio-org/okapi/) module that is hosted on **GitHub Pages**.
Only static Module Descriptor JSON files are served.

The **MDR** **GitHub Pages** may be found at [https://tamulib.github.io/folio-module-descriptor-registry](https://tamulib.github.io/folio-module-descriptor-registry).

The Module Descriptors for each release are found within the `release/` sub-directory on a separate branch from the scripts (such as `snapshot`).

The [https://repository.folio.org/repository/npm-folioci/](https://repository.folio.org/repository/npm-folioci/) repository is utilized to fetch any `@folio/` UI modules that require manual module descriptor building.

The [FOLIO Application Generator](folio-org/folio-application-generator) should be able to utilize this repository if and when it supports the `Simple` mode.


## Navigation
  - [Scripts](#scripts)
    - [Build Latest](#build-latest)
    - [Build Pages](#build-pages)
    - [Populate Release](#populate-release)
      - [Populate via Branches and Commit Hashes](#populate-via-branches-and-commit-hashes)
    - [Populate Node](#populate-node)
    - [Synchronize Snapshot](#synchronize-snapshot)
  - [GitHub Workflows](#github-workflows)
    - [Build GitHub Pages Workflow](#build-github-pages-workflow)
    - [Synchronize Snapshot Workflow](#synchronize-snapshot-workflow)
  - [Design and Methodology](#design-and-methodology)
    - [Repository Branch Design](#repository-branch-design)
    - [GitHub Workflows Design](#github-workflows-design)
    - [Self-Hosted Design](#self-hosted-design)
    - [Separation of Concern Design](#separation-of-concern-design)
    - [Fail Forward Design](#fail-forward-design)
    - [Scripting Design](#scripting-design)


## Scripts

This repository provides additional scripts that may help facilitate the generation of the Module Descriptors and related Continuous Integration and Continuous Delivery (CI/CD) operations.


### Build Latest

The **Build Latest** script provides a simple but automated way to create module descriptor symbolic links referencing the latest version.
This script takes a simple approach of creating a symbolic link to the version specified by the given `install.json` files in the order in which they appear.

The order in which the files are passed determines the order (left to right) in which overwrites of existing symbolic links are performed.
The default behavior is to use the `-latest` in place of the version suffix.

| Environment Variable Name        | Description (see script for further details)
| -------------------------------- | --------------------------------
| BUILD_LATEST_DEBUG               | Enable debug verbosity, any non-empty string enables this.
| BUILD_LATEST_FILES               | A list of files to build.
| BUILD_LATEST_PATH                | The destination path to write to.
| BUILD_LATEST_SKIP_NOT_FOUND      | Skip version files that are not found, any non-empty string enables this.

View the documentation within the `build_latest.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_LATEST_PATH="release/snapshot" bash script/build_latest.sh
```


### Build Pages

The **Build Pages** script provides a to generate **GitHub Pages** using a set of very simple templates.
The templates are provided by default, but custom templates are supported.

The template functionality is not intended to handle complex cases and only utilizes simple logic.
The basic structure allows for this process to be extensible but such logic is not implemented.
The `sed` statements in the script will need to be edited to enhance the template options available.

| Template Variable           | Description
| --------------------------- | --------------------------------
| `_REPLACE_LINK_`            | A URI (not intended to have HTML).
| `_REPLACE_LINK_NAME_`       | A name used for representing a link.
| `_REPLACE_PAGE_BACK_`       | Used by the script to apply the `back.html` template (explicitly intended to have HTML).
| `_REPLACE_PAGE_TITLE_`      | A page title, added to the HTML `<HEAD>` (not intended to have HTML).
| `_REPLACE_SECTION_DATE_`    | A date time stamp to display to users (defaults to a UTC date time).
| `_REPLACE_SECTION_TITLE_`   | A title to be displayed in HTML.
| `_REPLACE_SECTION_SNIPPET_` | Used by the script to apply the `item.html` template (explicitly intended to have HTML).

| Environment Variable Name        | Description (see script for further details)
| -------------------------------- | --------------------------------
| BUILD_PAGES_BASE                 | The base URL where the generated pages are stored.
| BUILD_PAGES_DEBUG                | Enable debug verbosity, any non-empty string enables this.
| BUILD_PAGES_IGNORE_INVALID       | Ignore non-JSON files rather than fail, any non-empty string enables this.
| BUILD_PAGES_TEMPLATE_BACK        | The name of the back HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| BUILD_PAGES_TEMPLATE_BASE        | The name of the base HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| BUILD_PAGES_TEMPLATE_ITEM        | The name of the item HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| BUILD_PAGES_TEMPLATE_PATH        | The path to the template directory containing the HTML template files.
| BUILD_PAGES_WORK                 | A working directory used to create the GitHub Pages structure (all templates and files are added here).

View the documentation within the `build_pages.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_PAGES_WORK="../work" bash script/build_pages.sh
```


### Populate Release

The **Populate Release** script helps automate building a list of module versions based on a specific flower release.
This release is then used to fetch all of the available module descriptors from an upstream source (an `install.json` file), such as those found on the **FOLIO Registry**.

The flower release name in relation to its release date designation (which maps to the tag name) can be found on the **FOLIO Project** wiki in the [Flower Release Names](https://folio-org.atlassian.net/wiki/spaces/REL/pages/5210505/Flower+Release+Names) page.

| Environment Variable Name        | Description (see script for further details)
| -------------------------------- | --------------------------------
| POPULATE_RELEASE_CURL_FAIL       | Designate how to handle curl failures. This can be one of `fail`, `none`, and `report` (default).
| POPULATE_RELEASE_DEBUG           | Enable debug verbosity, any non-empty string enables this.
| POPULATE_RELEASE_DESTINATION     | Destination parent directory.
| POPULATE_RELEASE_FILE_REUSE      | Enable re-using existing JSON files without GET fetching, any non-empty string enables this.
| POPULATE_RELEASE_FILES           | The name of space separated JSON files, such as `install.json` and `eureka-platform.json` to GET fetch and store locally for processing.
| POPULATE_RELEASE_FLOWER          | The Flower release name, such as `quesnelia` or `snapshot`.
| POPULATE_RELEASE_REGISTRY        | The URL to GET the module descriptor from for some specific module version.
| POPULATE_RELEASE_REPOSITORY      | The raw GitHub repository URL to fetch from (but without the URL parts after the repository name).
| POPULATE_RELEASE_REPOSITORY_PART | The part of the GitHub repository URL specifying the tag, branch, or hash (but without either the specific tag/branch name or the file path).
| POPULATE_RELEASE_TAG             | The GitHub release tag, such as `R1-2024-csp-9`.

View the documentation within the `populate_release.sh` script for further details on how to operate this script.

Example usage:
```shell
POPULATE_RELEASE_FLOWER="quesnelia" POPULATE_RELEASE_TAG="R1-2024-csp-9" bash script/populate_release.sh
```

_Make sure to manually delete any already downloaded JSON files to avoid accidentally including the wrong dependencies for some flower release when executing this script for multiple flower releases._


#### Populate via Branches and Commit Hashes

The population can be done via a branch name or a commit hash rather than only a tag name.

The `POPULATE_RELEASE_REPOSITORY_PART` environment variable should be used to specify this.
The value must be set to `heads` to use a branch name.
The value must be set to an empty string to use a specific commit hash instead of either a tag name or a branch name.

Example branch name usage:
```shell
POPULATE_RELEASE_REPOSITORY_PART="heads" POPULATE_RELEASE_FLOWER="snapshot" POPULATE_RELEASE_TAG="snapshot" bash script/populate_release.sh
```

Example commit hash usage:
```shell
POPULATE_RELEASE_REPOSITORY_PART="" POPULATE_RELEASE_FLOWER="aggies" POPULATE_RELEASE_TAG="fe7223e040d5d024f3f4961a3bc324d99a6fe7f5" bash script/populate_release.sh
```


### Populate Node

The **Populate Node** is a supplementary script to the **Populate Release**.

The **Populate Release** script operates based on existing pre-generated install JSON files.
The **Populate Node** script operates based on generating the install JSON files using the **FOLIO NPM Registry** (or whichever registry is configured via the `~/.yarnrc` file).

The install JSON file by default is named `npm.json` by default to prevent confusing it with the other install JSON files, such as `install.json` and `eureka-platform.json`.
This `npm.json` file is re-created on every run of this script.

The current implementation of this script limits the packages being operated on to those prefixed with `@folio/` in their package name.

This is intended to handle the small number of packages that are known to not be available directly in the **FOLIO Registry**, namely `@folio/authorization-policies` and `@folio/authorization-roles`.

| Environment Variable Name        | Description (see script for further details)
| -------------------------------- | --------------------------------
| POPULATE_NODE_DEBUG              | Enable debug verbosity, any non-empty string enables this.
| POPULATE_NODE_DESTINATION        | Destination directory the release files are stored in (this defaults to `${PWD}/release/snapshot`).
| POPULATE_NODE_NPM_DIR            | Designate a directory where the NPM JSON file is located (this defaults to `${PWD}`).
| POPULATE_NODE_NPM_FILE           | The name of the NPM JSON file used to hold the generated projects and versions.
| POPULATE_NODE_PROJECTS           | Designate the (space-separated) projects to operate on (specifying this overrides the default).
| POPULATE_NODE_SKIP_BAD           | Skip projects that fail to fetch and build instead of aborting the script, any non-empty string enables this.
| POPULATE_NODE_WORKSPACE          | Designate a workspace directory to use (This directory must already have a `package.json` workspace file).

View the documentation within the `populate_node.sh` script for further details on how to operate this script.

Example usage:
```shell
POPULATE_NODE_WORKSPACE="/path/to/workspace" bash script/populate_node.sh
```


### Synchronize Snapshot

The **Synchronize Snapshot** script identifies whether or no changes are detected and preforms the necessary `git` operations to push those changes to an upstream repository.

| Environment Variable Name        | Description (see script for further details)
| -------------------------------- | --------------------------------
| SYNC_SNAPSHOT_DEBUG              | Enable debug verbosity, any non-empty string enables this.
| SYNC_SNAPSHOT_MESSAGE            | Specify a custom message to use for the commit.
| SYNC_SNAPSHOT_PATH               | Designate a path in which to analyze (default is an empty string, which means current directory).
| SYNC_SNAPSHOT_RESULT             | The file name to write the results of this script to.
| SYNC_SNAPSHOT_SIGN               | Set to "yes" to explicitly sign, set to "no" to explicitly not sign, and do not set (or set to empty string) to use user-space default.

View the documentation within the `synchronize_snapshot.sh` script for further details on how to operate this script.

Example usage:
```shell
SYNC_SNAPSHOT_MESSAGE="Completed the snapshot synchronization." bash script/synchronize_snapshot.sh
```


## GitHub Workflows

This repository utilizes GitHub Workflows to perform Continuous Integration and Continuous Delivery (CI/CD).
The default configuration relies on `self-hosted` runners.

_The `self-hosted` runners may easily be changed to something like `ubuntu-latest` and should work, in general._

The GitHub Workflows are expected to clean up their working directory due to the nature of `self-hosted` runners.
These GitHub Workflows utilize run directories to help reduce potential problems for when running on `self-hosted` runners.
This does not guarantee parallel safety, but should help make problems significantly less likely.
The Workflows also attempt to perform clean up on success.

_The `self-hosted` runner is expected to perform its own maintenance to ensure that there are no disk space or other such problems._

These GitHub Workflows support some common input variables.
These input variables are available both as input variables for event triggers and as input variables if called by other GitHub Workflows.

|      Input Variable     |   Type    | Description
| ----------------------- | --------- | -----------
| `debug_mode`            | string    | Enables debugging when non-empty. Special options (space separated): `curl`, `git`, `json`, `verify`, `yarn`, `curl_only`, `git_only`, `json_only`, `verify_only`, and `yarn_only`.
| `registry_branch`       | string    | The name of the branch containing the registry descriptor files, such as `snapshot`.
| `script_branch`         | string    | The name of the branch containing the scripts, such as `master`.


### Build GitHub Pages Workflow

This GitHub Workflow loads existing, pre-generated, FOLIO module descriptors and deploys the files on the **GitHub Pages** for this repository.

The deployment process utilizes GitHub Artifacts.
These artifacts may be temporarily downloaded via the GitHub Workflow Action view and are available as per GitHub's retention policies.


### Synchronize Snapshot Workflow

This GitHub Workflow loads the latest releases from some pre-configured `install.json` file, commits the changes, and pushes the changes to the GitHub repository registry branch.
Commits made by this Workflow utilize the default GitHub Actions Bot (`41898282+github-actions[bot]@users.noreply.github.com`).

The **Build GitHub Pages Workflow** is automatically called by this GitHub Workflow.
This only happens if changes are detected.
Should something go wrong while calling the **Build GitHub Pages Workflow**, then the v must be manually called.
This is because the changes during the synchronization are committed before the **Build GitHub Pages Workflow** is called.

The **Synchronize Snapshot Workflow** is run using a cron job like timer every day at `00:00:00 UTC`.


## Design and Methodology

This repository is designed around the idea of avoiding re-creating existing CI/CD to a certain extent.
The use of Bash scripting language over programming languages is done to keep the design simple and to focus on using existing tools.
This repository is intended to automate part of the manual processes a user might have to perform when building and maintaining a FOLIO registry.
The primary focus is on provide module descriptors, but there may be some cross-over functionality regarding application descriptors and other related CI/CD tasks.


### Repository Branch Design

There are two primary types of branches in use, called trunks.
These two trunks, `master` and `snapshot`, operate from different fundamental concepts.

The first trunk, `master`, is the most common trunk design.
This houses scripts, workflows, documentation, and any other programmatic tool.
Branches based on the `master` trunk are the traditional coding branches and is expected to be the primary fork and merge branch.
There will be no release related content within this trunk beyond the scripts and tools used to operate on a release.
Note that this "release" is not a release of the repository but instead is referring to FOLIO module, applications, or flower releases.

The second trunk, `snapshot`, is a package release trunk design.
This houses only descriptor files and other release related content.
There are no scripts, documentation, or other non-release related content.
This is maintained as a separate trunk to help maintain a clean repository structure.
There will be a lot of automated commits entirely unrelated to the code itself.


### GitHub Workflows Design

The GitHub Workflows are designed to be dynamically toggled using a small number input variables.
These Workflows provide input variables for selecting the individual branches to be selected.


### Self-Hosted Design

The GitHub Workflows are design to be operated within a self-hosted environment.
This potentially gives the Workflow access to systems inside the self-hosted environment, such as Rancher and Kubernetes.

A self-hosted system within Rancher might maintain state because a clean system might not be spun up and down for every single Workflow execution.
This necessitates that the Workflows must manage potentially parallel state, such as creating distinct running instance sub-directories and the deletion of those directories on success.
The standard behavior on failure is to not perform the directory clean up to help facilitate investigation of any problems.
Should there be a lot of problems, the self-hosted runner may need either manual intervention or a custom process to clean up stale instance directories.


### Separation of Concern Design

A certain level of separation of concerns is used to structure the numerous scripts in this process.
There may be some overlap or double duty in some scripts, but for the most part each script handles its process in isolation of other scripts.
Many of the scripts will require the existence of files that are created by other scripts, but those files can be created through any means beyond just running other scripts.


### Fail Forward Design

A certain level of fail-forward behavior is supported by several scripts in order to ensure that problems with a single project or descriptor will not block or prevent the publishing of the entire set.
This functionality is configurable via environment variables, but the Workflows enable this fail-forward behavior by default.


### Scripting Design

The scripts are design using functions in Bash.

Each script is named using a few words to describe the general purpose of the script.
The functions within the script, except special functions like `main`, are prefixed with either the script name or a shortened variation of the script name.
The special case `main` function starts the program, acts as a holder of effective `global` local variables,

Environment variables are prefixed with the full script name and are in all upper case.
All environment variables are mapped to a `local` variable within the script at the `main` scope.
Some amount of validation is performed on the environment variables.
Most environment variables are treated as undefined when set to an empty string.
There are some special cases where any empty string is explicitly needed and in such cases those variables are considered defined when empty (via the `-z` condition check).

Special case `*_DEBUG*` variables are provided to help facilitate passing debug settings to the scripts.

A custom `result` variable as an integer is used to help facility failure and success states.
Most, if not all, functions pre-check this `result` variable for error state.
This helps simplify the need for lots of conditional checks after each function call.
The function calls can then be set side by side (technically above and below each other) without as many conditionals to make the script more readable.
A special exception to these `result` checks all being in the functions include loops, such as `for` or `while`, where the loop needs to either be broken out of or continued.
The `local` variables must be defined after the `result` check in functions for cases where the `result` variable is checked at the start of the function.

A `*_handle_result` function is used as a standard naming for functions that check the `result` variable and print an error message.
Errors are generally handled via the appropriate `*_handle_result` when a return code is involved.
When there is no return code, then the `result` variable must be manually set and any desired printing must be directly performed.
These functions are exception cases where the `local` variable must be defined at the start so that the `${?}` can be immediately processed before anything else could alter the value of `${?}`.

A `*_print*` function is used for various types of printing that are conditionally printed, such as when debugging is enabled.

A `*_load_environment` function is used in every script to perform processing of environment variables and command-line parameters passed to the script.
These functions are expected to not check the error state on start so that they always run.
The handling of the debug variables must be performed first to ensure error handling and debugging is enabled for the remainder of the function.

The scripts are written in Bash, but are designed to increase the possibility of supporting other advanced shell interpreters, such as ZSH.
The `${}` style is consistently used on all variables because some shell interpreters like ZSH are more fickle about such things.
This practice also helps avoid inconsistencies in the styling when variables are combined side-by-side such that the `${}` is required.
Double quotes are applied to all variables when spaces must be preserved, otherwise double quotes are avoided.
The use of single quotes are limited to when variable substitution and other such behavior must explicitly be avoided in the string.

The scripts are designed to control the verbosity using the `*_DEBUG*` environment variables.
Exceptions to this are generally problematic programs like `jq` and `yarn`.

It is encouraged to use `local` variables in a function to prevent those variables from being exposed at a higher level.
If the parent function is managing some `local` variable, then that script is expected to not define a `local` for that variable.
Many of the functions are design to expect some parent to have defined variables.
Most functions, aside from the printing, error handling functions, and the load setting functions, do not expect variables passed to the function in a command-line style.
Instead, `local` variables at a parent scope must be used.

Each script is designed such that it can be executed stand alone on a local machine independent of the CI/CD.
The Bash scripting environment and appropriately defined environment variables are still required as needed.

Except for the `main` function, all functions are alphabetically ordered by name.
