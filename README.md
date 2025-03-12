# FOLIO Module Descriptor Registry (MDR)

Copyright © 2025 Texas A&M University Libraries under the [MIT license](LICENSE).

The [FOLIO](https://folio.org/) module **Module Descriptor Registry** (**MDR**) provides a listing of generated module descriptors.

The **MDR** is intended to be accessed directly by [FOLIO](https://folio.org/) instances for determining what module is available to enable.

**MDR** is a simple, static, implementation of the [OKAPI](https://github.com/folio-org/okapi/) module that is hosted on **GitHub Pages**.
Only static Module Descriptor JSON files are served.

The **MDR** **GitHub Pages** may be found at [https://tamulib.github.io/folio-module-descriptor-registry](https://tamulib.github.io/folio-module-descriptor-registry).

The Module Descriptors for each release are found within the `release/` sub-directory on a separate branch from the scripts (such as `snapshot`).

The [FOLIO Application Generator](folio-org/folio-application-generator) should be able to utilize this repository if and when it supports the `Simple` mode.


## Scripts

This repository provides additional scripts that may help facilitate the generation of the Module Descriptors.


### Build Latest

The **Build Latest** script provides a simple but automated way to create module descriptor symbolic links referencing the latest version.
This script takes a simple approach of creating a symbolic link to the version specified by the given `install.json` files in the order in which they appear.

The order in which the files are passed determines the order (left to right) in which overwrites of existing symbolic links are performed.
The default behavior is to use the `-latest` in place of the version suffix.

View the documentation within the `build_latest.sh` script for further details on how to operate this script.

Example usage:
```shell
bash script/build_path.sh release/
```


### Build Pages

The **Build Pages** script provides a to generate **GitHub Pages** using a set of very simple templates.
The templates are provided by default, but custom templates are supported.

The template functionality is not intended to handle complex cases and only utilizes simple logic.
The basic structure allows for this process to be extensible but such logic is not implemented.
The `sed` statements in the script will need to be edited to enhance the template options available.

|      Template Variable      | Description
| --------------------------- | -----------
| `_REPLACE_LINK_`            | A URI (not intended to have HTML).
| `_REPLACE_LINK_NAME_`       | A name used for representing a link.
| `_REPLACE_PAGE_BACK_`       | Used by the script to apply the `back.html` template (explicitly intended to have HTML).
| `_REPLACE_PAGE_TITLE_`      | A page title, added to the HTML `<HEAD>` (not intended to have HTML).
| `_REPLACE_SECTION_DATE_`    | A date time stamp to display to users (defaults to a UTC date time).
| `_REPLACE_SECTION_TITLE_`   | A title to be displayed in HTML.
| `_REPLACE_SECTION_SNIPPET_` | Used by the script to apply the `item.html` template (explicitly intended to have HTML).

View the documentation within the `build_pages.sh` script for further details on how to operate this script.

Example usage:
```shell
BUILD_LATEST_PATH="release/snapshot" bash script/build_latest.sh install.json additional.json
```


### Populate Release

The **Populate Release** script helps automate building a list of module versions based on a specific flower release.
This release is then used to fetch all of the available module descriptors from an upstream source (an `install.json` file), such as those found on the **FOLIO Registry**.

This script is designed to accept environment variables, thereby allowing for easier integration with automation tools such as Docker.

Direct command line use is also supported to allow for individuals to manually execute.
Most settings, however, are either done via environment variables or by manually toggling the variables within the script.

The flower release name in relation to its release date designation (which maps to the tag name) can be found on the **FOLIO Project** wiki in the [Flower Release Names](https://folio-org.atlassian.net/wiki/spaces/REL/pages/5210505/Flower+Release+Names) page.

View the documentation within the `populate_release.sh` script for further details on how to operate this script.

Example usage:
```shell
bash script/populate_release.sh R1-2024-csp-9 quesnelia
```

_Make sure to manually delete any already downloaded JSON files to avoid accidentally including the wrong dependencies for some flower release when executing this script for multiple flower releases._


#### Populate via Branches and Commit Hashes

The population can be done via a branch name or a commit hash rather than only a tag name.

The `POPULATE_RELEASE_REPOSITORY_PART` environment variable should be used to specify this.
The value must be set to `heads` to use a branch name.
The value must be set to an empty string to use a specific commit hash instead of either a tag name or a branch name.

Example branch name usage:
```shell
POPULATE_RELEASE_REPOSITORY_PART="heads" bash script/populate_release.sh snapshot snapshot
```

Example commit hash usage:
```shell
POPULATE_RELEASE_REPOSITORY_PART="" bash script/populate_release.sh fe7223e040d5d024f3f4961a3bc324d99a6fe7f5 aggies
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
| `debug_mode`            | string    | Enables debugging when non-empty. Special options (space separated): `curl`, `git`, `json`, `verify`, `curl_only`, `git_only`, `json_only`, and `verify_only`.
| `registry_branch`       | string    | The name of the branch containing the registry descriptor files, such as `snapshot`.
| `script_branch`         | string    | The name of the branch containing the scripts, such as `master`.


### Build GitHub Pages

This GitHub Workflow loads existing, pre-generated, FOLIO module descriptors and deploys the files on the **GitHub Pages** for this repository.

The deployment process utilizes GitHub Artifacts.
These artifacts may be temporarily downloaded via the GitHub Workflow Action view and are available as per GitHub's retention policies.


### Synchronize Snapshot

This GitHub Workflow loads the latest releases from some pre-configured `install.json` file, commits the changes, and pushes the changes to the GitHub repository registry branch.
Commits made by this Workflow utilize the default GitHub Actions Bot (`41898282+github-actions[bot]@users.noreply.github.com`).

The **Build GitHub Pages Workflow** is automatically called by this GitHub Workflow.
This only happens if changes are detected.
Should something go wrong while calling the **Build GitHub Pages Workflow**, then the v must be manually called.
This is because the changes during the synchronization are committed before the **Build GitHub Pages Workflow** is called.

The **Synchronize Snapshot Workflow** is run using a cron-job like timer every day at 00:00:00 UTC.
