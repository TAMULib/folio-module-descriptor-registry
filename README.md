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
    - [Build Deployments](#build-deployments)
    - [Build Latest](#build-latest)
    - [Build Launches](#build-launches)
    - [Build Location](#build-location)
    - [Build Module Discovery](#build-module-discovery)
    - [Build Pages](#build-pages)
    - [Populate Node](#populate-node)
    - [Populate Release](#populate-release)
      - [Populate via Branches and Commit Hashes](#populate-via-branches-and-commit-hashes)
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


### Build Deployments

The **Build Deployments** script provides a way to build the YAML data for services such as **Fleet**.
This requires the **Module Discovery Descriptor** as an input source.
There are several template files used as input data that are conditionally expanded based on a configurable set of names.
These template files are intended and expected to be altered as needed.

The input path, such as `template/deploy/input/`, contains multiple sub-directories: `launches`, `main`, `specific`, and `vars`.

The `launches` sub-directory contains variable substitution JSON files generated using a script like `build_launches.sh` based on the `launchDescriptor` provided by each module descriptor.
Theese JSON files are named based on the `name` of the module, such as `mod-configuration.json`.
Each of these JSON files contains a JSON object just like the `vars.json` from the `main` sub-directory.
These `launches` JSON files are merged with the specific `vars` JSON files and the loaded `vars.json` file.

The `main` sub-directory contains `base.json`, `deployment.json`, `maps.json`, `names.json`, `vars.json`, and others defined via `maps.json`.
The `base.json` file is a JSON object containing the base image used to initialize the final manifest.
The `deployment.json` file is a JSON object used for all deployments being built.
The `maps.json` file is a JSON file mapping specific modules to custom alternatives to `deployment.json` for cases where the differences between `deployment.json` would require too many variables or otherwise be too extreme.
There are two options in `maps.json`, `exact` and `pcre`.
The `exact` matches the by exact name match and overrides any `pcre` matches.
The `pcre` matches based on Perl Compatible Regular Expressions (PCRE).
The `names.json` file is a JSON array of names to expand of the form `[SOME_NAME]`.
Any name defined in `names.json` but not in `vars.json` will have the key and value pair entirely removed when found in the `deployment.json` or similar JSON files.
The `vars.json` file is a JSON object map containing the names and the values that they each map to.
The values in `vars.json` may themselves be complex structures such as arrays or objects.

The `specific` sub-directory contains an optional set of variable substitution JSON files that are named based on the `name` of the module, such as `mod-configuration.json`.
Each of these specific JSON files contain a JSON object just like the `deployment.json` from the `main` sub-directory.
The specific JSON file is merged with the loaded `deployment.json` file for each deployment described in the **Module Discovery Descriptor**.

The `vars` sub-directory contains an optional set of variable substitution JSON files that are named based on the `name` of the module, such as `mod-configuration.json`.
Each of these specific JSON files contains a JSON object just like the `vars.json` from the `main` sub-directory.
The specific `vars` JSON file is merged with the `vars.json` file for each deployment described in the **Module Discovery Descriptor**.

The output path, such as `template/deploy/output/`, contains two main sub-directories: `json` and `yaml`.

The `json` sub-directory contains the built JSON files for each individual deployment.
The `yaml` sub-directory contains the built YAML file and is constructed from the individual deployment files found within the `json` sub-directory.

The variable substitution and module processing order are as follows:
  1. `deployment.json`, or other file such as `stateful_set.json` as defined by `maps.json`.
  2. `vars.json`.
  3. `launches` JSON file for each module.
  4. `vars` JSON file for each module.
  5. `specific` JSON file for each module.

The script does not operate recursively.
Instead, it makes multiple passes up to a limit specified by `BUILD_DEPLOY_PASSES`.

There are two types of variable substitution being used in this script.

The first type utilizes substitution files like `vars.json` (and therefore also `names.json`).
This type is directly passed to `jq` and `yq` as needed for doing a JSON compatible replacement of entire values.
This type does not replace individual parts of a value.
These are of the form `[NAME]` and must be part of a JSON string.
The substituted value does not have to be a string and can be any valid JSON type.
The JSON files in the `launches` sub-directory, JSON files in the `vars` sub-directory, and the `vars.json` JSON file are associated with this substitution type.

The second type utilizes the **Module Discovery Descriptor** keys and values as well as some other special keys and values.
This **Module Discovery Descriptor** type is key on a combination of special reserved words and module names.
This operates only on a string matching level using `sed` and cannot safely handle JSON data.
This type allows for partial replacements, such as `"{repository:}/{name:}:{version:}"`.
This type is of the form `{key:module}` where `key` is one of `id`, `location`, `name`, `repository`, and `version`.
The special key types are `{global:app}` and `{global:namespace}`.
The `{global:app}` represents the application name specified by the `BUILD_DEPLOY_SELECTOR` environment variable.
The `{global:namespace}` represents the namespace specified by the `BUILD_DEPLOY_NAMESPACE` environment variable.
The `{repository:}` is module specific, but is not part of the **Module Discovery Descriptor** and is instead part of the Repository Location JSON files for each module (if they exist).
The default repository is used for `{repository:}` when there is no Repository Location JSON file for a particular module.
The `module` is either not specified (like `{id:}`) to designate using information from the currently processed module.
This is useful for situations such as where the module named `mod-consortia-keycloak` needs to define `MOD_USERS_URL` with a value of `http://mod-users-19.6.0-SNAPSHOT.350.folio-modules.svc`.
This can be done using `http://mod-users-{version:mod-users}.{global:namespace}.svc`, such as in the following:
```json
"[ENVIRONMENT]": [
  {
    "name": "MOD_USERS_URL",
    "value": "http://mod-users-{version:mod-users}.{global:namespace}.svc"
  }
]
```

| Environment Variable              | Description (see script for further details)
| --------------------------------- | --------------------------------
| `BUILD_DEPLOY_ACTIONS`            | Allow limiting the actions to either `expand`, `combine`, or `both` (default is `both` when this is an empty string).
| `BUILD_DEPLOY_APP`                | The name of the application bundle, also use for the name of file without the file extension (not the full path), such as `fleet`.
| `BUILD_DEPLOY_DEBUG`              | Enable debug verbosity, any non-empty string enables this.
| `BUILD_DEPLOY_DEFAULT_REPOSITORY` | Designate the default repository to use when none is specified via a Repository Location JSON file (defaults to `folioci`).
| `BUILD_DEPLOY_DISCOVERY`          | The path to the **Module Discovery Descriptor** JSON file.
| `BUILD_DEPLOY_FLOWER`             | The Flower release name, such as `quesnelia` or `snapshot` (defaults to `snapshot`).
| `BUILD_DEPLOY_INPUT_PATH`         | The path to the input template directory.
| `BUILD_DEPLOY_LOCATION_PATH`      | The directory containing generated Repository Location JSON files (defaults to `location/`).
| `BUILD_DEPLOY_NAMES`              | If non-empty, then this is a list of names from the **Module Discovery Descriptor** that the build process should be limited to. This does support names not defined in the **Module Discovery Descriptor** file.
| `BUILD_DEPLOY_NAMESPACE`          | The Kubernetes namespace to use when building (defaults to `folio-modules`).
| `BUILD_DEPLOY_OUTPUT_FORCE`       | If non-empty, then allow writing over existing output files without failing on error.
| `BUILD_DEPLOY_OUTPUT_PATH`        | The path to the output directory.
| `BUILD_DEPLOY_PASSES`             | The number of passes to make when expanding variables.

View the documentation within the `build_deployments.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_DEPLOY_DISCOVERY="module_discovery-1.0.0-SNAPSHOT.2188.json" BUILD_DEPLOY_FLOWER="quesnelia" bash script/build_deployments.sh
```


### Build Latest

The **Build Latest** script provides a simple but automated way to create module descriptor symbolic links referencing the latest version.
This script takes a simple approach of creating a symbolic link to the version specified by the given `install.json` files in the order in which they appear.

The order in which the files are passed determines the order (left to right) in which overwrites of existing symbolic links are performed.
The default behavior is to use the `-latest` in place of the version suffix.

| Environment Variable          | Description (see script for further details)
| ----------------------------- | --------------------------------
| `BUILD_LATEST_DEBUG`          | Enable debug verbosity, any non-empty string enables this.
| `BUILD_LATEST_FILES`          | A list of files to build.
| `BUILD_LATEST_PATH`           | The destination path to write to.
| `BUILD_LATEST_SKIP_NOT_FOUND` | Skip version files that are not found, any non-empty string enables this.

View the documentation within the `build_latest.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_LATEST_PATH="release/snapshot" bash script/build_latest.sh
```


### Build Launches

The **Build Launches** script utilizes the _Launch Descriptor_ from a given set of module descriptors.
This script is intended to be used to generate the _Launch Descriptor_ variable substitution for the `launches` directory used by the **Build Deployments** script.
This is expected to be called after the **Build Latest** script is executed.

This does support using suffixed other than the `-latest`.

An input JSON file at `template/launch/input/instructions.json` is used to provide the properties to be extracted from the _Launch Descriptor_ of the module.
This file is a JSON array of mapping objects with three named keys: `map`, `type`, and `value`.
The `map` is the mapping name used by variable substitution, such as `[ENVIRONMENT]`.
The `type` is one of the following supported types:
  1. `field`: This type designates that the field from the _Launch Descriptor_ is to be directly used.
  2. `container_port`: This type designates that a container port structure from the _Launch Descriptor_ needs to be interpeted and re-mapped as a container port type for the deployment manifest (multiple ports are supported).
The `value` is different depending on the type but in general directly represents a `jq` query designating which field to select from the _Launch Descriptor_ of the module.
The `value` for the `field` type is a direct mapping.
The `value` for the `container_port` expects the structure of the form `{ "123/tcp": [ { "HostPort" : "%p" } ] }`.
The `"123/tcp"` is extracted and split into a port number and protocol name.
For each named object in the `container_port` structure, a name is generated from the index and protocol, such as `123_TCP_0`.

| Environment Variable          | Description (see script for further details)
| ----------------------------- | --------------------------------
| `BUILD_LAUNCHES_DEBUG`        | Enable debug verbosity, any non-empty string enables this.
| `BUILD_LAUNCHES_INPUT_PATH`   | The path containing the input files, such as the `instructions.json` file.
| `BUILD_LAUNCHES_OUTPUT_PATH`  | The path to write the generated `launch` files in, such as `template/deploy/input/` (this has `input/` because these files are used as input for the **Build Deployments** script).
| `BUILD_LAUNCHES_RELEASE_PATH` | The path containing the release files, such as the `release/snapshot/`.
| `BUILD_LAUNCHES_VERSION`      | The version to use as the suffix to match when selecting the releases files, such as `latest` or `5.1.0-SNAPSHOT.272`.

View the documentation within the `build_launches.sh` script for further details on how to operate this script.

Example usage:
```shell
bash script/build_launches.sh
```


### Build Location

The **Build Location** script utilizes repository templates to generate location templates.
This script is intended to be used to help automatically detect and assign which repository location to use for each release and respective tag.
This script expects the `install.json` and similar files, such as `eureka-platform.json`, to be available and ready for use.

The **Build Location** script operates by parsing the input JSON files, such as `install.json`, and extracting the releases and their respective version tags.
Only releases that begin with `mod-` and `edge-` are processed.
The Repositories JSON file, such as `repositories.json`, contains a list of all repositories to search in for each release.
The extracted list of releases is then looped through, making requests to each repository in order to determine which one contains both the release and the tag.
If the repository is confirmed to contain the release and tag, then a location file is created based on that location.

The process of making a request conditionally requires the following operations:
  1. If authentication is enabled, perform a `GET` request to anonymously fetch an Authentication Token to use performing the request.
  2. Perform a `HEAD` request (with Authentication Token if requested) to check the existence of a module.
  3. If the HTTP `HEAD` request response contains an HTTP response with `200 OK`, then the repository is considered usable.
  4. If the HTTP `HEAD` request response contains something other than `200 OK`, then the repository is consider not unsable.

The **Build Location** script attempts to reduce abuse to external servers by operating in the following way:
  1. Use HTTP `HEAD` requests for existence checks.
  2. Add a small delay between each release being looped over.
  3. Checking if the location file for a given release and tag already exists and not making another request if it does.

The Repositories JSON file is an array of objects where each object represents a single named repository.
The following is an example format, showing only a single repository:
```json
[
  {
    "id": "folioci",
    "name": "folioci",
    "auth": {
      "url": "https://auth.docker.io/",
      "registry": "registry.docker.io"
    },
    "request": {
      "url": "https://registry-1.docker.io/"
    }
  }
]
```
  - The `id` is an identifier for this specific repository.
  - The `name` is the name used in the location file to represent this repository (such as `folioci` in `https://hub.docker.com/r/folioci/mod-circulation`).
  - The `auth` is broken up into two parts, a `url` and a `registry`.
  - The `auth.url` is optional; This is used to perform `GET` requests to obtain an authentication token as an anonymous user.
  - The `auth.registry` is optional and is only used if `auth.url` is used; provides information needed for requesting the authentication token.
  - The `request` is broken up into one part, a `url`.
  - The `request.url` is the URL used to perform the `HEAD` request used to identify the presence of a package and version at the named repository.

The general format structure for a Location JSON file is `{release}-${tag}.json`, where relase might be a module such as `mod-circulation` and the tag might be `24.5.0-SNAPSHOT.1311`.
The following is an example format for the `mod-circulation-24.5.0-SNAPSHOT.1311.json` Location JSON file:
```json
{
  "id": "mod-circulation-24.5.0-SNAPSHOT.1311",
  "repository": "folioci"
}
```
  - The `id` is the release and the tag in this format: `{release}-${tag}`.
  - The `id` is provided for informational purposes and is otherwise not used.
  - The `repository` contains the named repository, based on the `name` field from the Repositories JSON file.

| Environment Variable               | Description (see script for further details)
| ---------------------------------- | --------------------------------
| `BUILD_LOCATION_DEBUG`             | Enable debug verbosity, any non-empty string enables this.
| `BUILD_LOCATION_DESTINATION`       | The directory to save the generated location JSON files in (defaults to `location/`).
| `BUILD_LOCATION_DELAY`             | The amount of time in seconds (`1s` = 1 second), minutes (`1m` = 1 minute), hours (`1h` = 1 hour), or days (`1d` = 1 day) (set to `0` to disable sleep, defaults to `0.3s`).
| `BUILD_LOCATION_FILES`             | The name of space separated JSON files, such as `install.json` and `eureka-platform.json` to GET fetch and store locally for processing.
| `BUILD_LOCATION_FLOWER`            | The Flower release name, such as `quesnelia` or `snapshot` (defaults to `snapshot`).
| `BUILD_LOCATION_LIMIT`             | Limit the number of requests made per request URI (Set to `0` to disable, defaults to `100`).
| `BUILD_LOCATION_REPOSITORIES_NAME` | The name of the repositories JSON file (defaults to `repositories.json`).
| `BUILD_LOCATION_REPOSITORIES_PATH` | The directory containing the repositories configuration JSON file (defaults to `template/location/`).

View the documentation within the `build_location.sh` script for further details on how to operate this script.

Example usage:
```shell
bash BUILD_LOCATION_LIMIT=100 BUILD_LOCATION_DELAY="0.3s" script/build_location.sh
```


### Build Module Discovery

The **Build Module Discovery** script provides a way to build a **Module Discovery** JSON file.
This JSON file can then be used to register the **Module Discovery** as well as to be used for building the **Fleet** YAML data.

| Environment Variable             | Description (see script for further details)
| -------------------------------- | --------------------------------
| `BUILD_MOD_DISCOVERY_DEBUG`      | Enable debug verbosity, any non-empty string enables this.
| `BUILD_MOD_DISCOVERY_FIELD`      | The field to use when building the discovery. One of `id`, `name`, and `version`.
| `BUILD_MOD_DISCOVERY_FORCE`      | If non-empty, then allow writing over existing output **Module Discovery Descriptor** JSON file without failing on error.
| `BUILD_MOD_DISCOVERY_INPUT`      | The input **Application Descriptor** JSON file. (May be passed as the first argument to the script.)
| `BUILD_MOD_DISCOVERY_OUTPUT`     | The output **Module Discovery Descriptor** JSON file. (May be passed as the second argument to the script.)
| `BUILD_MOD_DISCOVERY_URL_PREFIX` | The left hand side of the built URL, such as `http://`.
| `BUILD_MOD_DISCOVERY_URL_SUFFIX` | The right hand side of the built URL, such as `.folio-modules.svc`.

The URL is built as follows `${BUILD_MOD_DISCOVERY_URL_PREFIX}${BUILD_MOD_DISCOVERY_FIELD}${BUILD_MOD_DISCOVERY_URL_SUFFIX}`, which by default will build something like this `http://my_module-1.0.folio-modules.svc`.

View the documentation within the `build_module_discovery.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_MOD_DISCOVERY_INPUT="app-platform-minimal-1.0.0-SNAPSHOT.2188.json" BUILD_MOD_DISCOVERY_OUTPUT="module_discovery-1.0.0-SNAPSHOT.2188.json" bash script/build_module_discovery.sh
```
Example alternate usage:
```shell
bash script/build_module_discovery.sh app-platform-minimal-1.0.0-SNAPSHOT.2188.json module_discovery-1.0.0-SNAPSHOT.2188.json
```


### Build Pages

The **Build Pages** script provides a way to generate **GitHub Pages** using a set of very simple templates.
The templates are provided by default, but custom templates are supported.

The template functionality is not intended to handle complex cases and only utilizes simple logic.
The basic structure allows for this process to be extensible but such logic is not implemented.
The `sed` statements in the script will need to be edited to enhance the template options available.

| Template Variable           | Description
| --------------------------- | --------------------------------
| `_REPLACE_LINK_`            | A URI (not intended to have HTML).
| `_REPLACE_LINK_DOWNLOAD_`   | For adding `download` `<a>` tag attribute, such as `download="my_file.json"`.
| `_REPLACE_LINK_NAME_`       | A name used for representing a link.
| `_REPLACE_LINK_TYPE_`       | For adding `type` `<a>` tag attribute, such as `type="application/json"`.
| `_REPLACE_PAGE_BACK_`       | Used by the script to apply the `back.html` template (explicitly intended to have HTML).
| `_REPLACE_PAGE_TITLE_`      | A page title, added to the HTML `<HEAD>` (not intended to have HTML).
| `_REPLACE_SECTION_DATE_`    | A date time stamp to display to users (defaults to a UTC date time).
| `_REPLACE_SECTION_TITLE_`   | A title to be displayed in HTML.
| `_REPLACE_SECTION_SNIPPET_` | Used by the script to apply the `item.html` template (explicitly intended to have HTML).

| Environment Variable         | Description (see script for further details)
| ---------------------------- | --------------------------------
| `BUILD_PAGES_BASE`           | The base URL where the generated pages are stored.
| `BUILD_PAGES_DEBUG`          | Enable debug verbosity, any non-empty string enables this.
| `BUILD_PAGES_IGNORE_INVALID` | Ignore non-JSON files rather than fail, any non-empty string enables this.
| `BUILD_PAGES_TEMPLATE_BACK`  | The name of the back HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| `BUILD_PAGES_TEMPLATE_BASE`  | The name of the base HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| `BUILD_PAGES_TEMPLATE_ITEM`  | The name of the item HTML template within the `BUILD_PAGES_TEMPLATE_PATH` directory.
| `BUILD_PAGES_TEMPLATE_PATH`  | The path to the template directory containing the HTML template files.
| `BUILD_PAGES_WORK`           | A working directory used to create the GitHub Pages structure (all templates and files are added here).

View the documentation within the `build_pages.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_PAGES_WORK="../work" bash script/build_pages.sh
```


### Populate Node

The **Populate Node** is a supplementary script to the **Populate Release**.

The **Populate Release** script operates based on existing pre-generated install JSON files.
The **Populate Node** script operates based on generating the install JSON files using the **FOLIO NPM Registry** (or whichever registry is configured via the `~/.yarnrc` file).

The install JSON file by default is named `npm.json` by default to prevent confusing it with the other install JSON files, such as `install.json` and `eureka-platform.json`.
This `npm.json` file is re-created on every run of this script.

The current implementation of this script limits the packages being operated on to those prefixed with `@folio/` in their package name.

This is intended to handle the small number of packages that are known to not be available directly in the **FOLIO Registry**, namely `@folio/authorization-policies` and `@folio/authorization-roles`.

| Environment Variable        | Description (see script for further details)
| --------------------------- | --------------------------------
| `POPULATE_NODE_DEBUG`       | Enable debug verbosity, any non-empty string enables this.
| `POPULATE_NODE_DESTINATION` | Destination directory the release files are stored in (this defaults to `${PWD}/release/snapshot`).
| `POPULATE_NODE_NPM_DIR`     | Designate a directory where the NPM JSON file is located (this defaults to `${PWD}`).
| `POPULATE_NODE_NPM_FILE`    | The name of the NPM JSON file used to hold the generated projects and versions.
| `POPULATE_NODE_PROJECTS`    | Designate the (space-separated) projects to operate on (specifying this overrides the default).
| `POPULATE_NODE_SKIP_BAD`    | Skip projects that fail to fetch and build instead of aborting the script, any non-empty string enables this.
| `POPULATE_NODE_WORKSPACE`   | Designate a workspace directory to use (This directory must already have a `package.json` workspace file).

View the documentation within the `populate_node.sh` script for further details on how to operate this script.

Example usage:
```shell
POPULATE_NODE_WORKSPACE="/path/to/workspace" bash script/populate_node.sh
```


### Populate Release

The **Populate Release** script helps automate building a list of module versions based on a specific flower release.
This release is then used to fetch all of the available module descriptors from an upstream source (an `install.json` file), such as those found on the **FOLIO Registry**.

The flower release name in relation to its release date designation (which maps to the tag name) can be found on the **FOLIO Project** wiki in the [Flower Release Names](https://folio-org.atlassian.net/wiki/spaces/REL/pages/5210505/Flower+Release+Names) page.

| Environment Variable               | Description (see script for further details)
| ---------------------------------- | --------------------------------
| `POPULATE_RELEASE_CURL_FAIL`       | Designate how to handle curl failures. This can be one of `fail`, `none`, and `report` (default).
| `POPULATE_RELEASE_DEBUG`           | Enable debug verbosity, any non-empty string enables this.
| `POPULATE_RELEASE_DESTINATION`     | Destination parent directory.
| `POPULATE_RELEASE_FILE_REUSE`      | Enable re-using existing JSON files without GET fetching, any non-empty string enables this.
| `POPULATE_RELEASE_FILES`           | The name of space separated JSON files, such as `install.json` and `eureka-platform.json` to GET fetch and store locally for processing.
| `POPULATE_RELEASE_FLOWER`          | The Flower release name, such as `quesnelia` or `snapshot`.
| `POPULATE_RELEASE_REGISTRY`        | The URL to GET the module descriptor from for some specific module version.
| `POPULATE_RELEASE_REPOSITORY`      | The raw GitHub repository URL to fetch from (but without the URL parts after the repository name).
| `POPULATE_RELEASE_REPOSITORY_PART` | The part of the GitHub repository URL specifying the tag, branch, or hash (but without either the specific tag/branch name or the file path).
| `POPULATE_RELEASE_TAG`             | The GitHub release tag, such as `R1-2024-csp-9`.

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


### Synchronize Snapshot

The **Synchronize Snapshot** script identifies whether or no changes are detected and preforms the necessary `git` operations to push those changes to an upstream repository.

| Environment Variable    | Description (see script for further details)
| ----------------------- | --------------------------------
| `SYNC_SNAPSHOT_DEBUG`   | Enable debug verbosity, any non-empty string enables this.
| `SYNC_SNAPSHOT_MESSAGE` | Specify a custom message to use for the commit.
| `SYNC_SNAPSHOT_PATH`    | Designate a path in which to analyze (default is an empty string, which means current directory).
| `SYNC_SNAPSHOT_RESULT`  | The file name to write the results of this script to.
| `SYNC_SNAPSHOT_SIGN`    | Set to "yes" to explicitly sign, set to "no" to explicitly not sign, and do not set (or set to empty string) to use user-space default.

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

| Input Variable    | Type      | Description
| ----------------- | --------- | -----------
| `debug_mode`      | string    | Enables debugging when non-empty. Special options (space separated): `curl`, `git`, `json`, `verify`, `yarn`, `curl_only`, `git_only`, `json_only`, `verify_only`, and `yarn_only`.
| `registry_branch` | string    | The name of the branch containing the registry descriptor files, such as `snapshot`.
| `script_branch`   | string    | The name of the branch containing the scripts, such as `master`.


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

There are three primary types of branches in use, called trunks.
These three trunks, `master`, `snapshot`, and `fleet`, operate from different fundamental concepts.

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

The third trunk, `fleet`, is designed to provide the YAML file needed for **Fleet** operations.
This houses the `fleet.yaml` and other related **Fleet** files.
These files can be accessed by **Fleet** using either the GitHub Webhooks or the **Fleet** polling.


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
