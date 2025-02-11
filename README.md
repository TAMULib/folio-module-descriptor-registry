# FOLIO Module Descriptor Registry (MDR)

The [FOLIO](https://folio.org/) module **Module Descriptor Registry** (**MDR**) provides a listing of generated module descriptors.

The **MDR** is intended to be accessed directly by [FOLIO](https://folio.org/) instances for determining what module is available to enable.

**MDR** is a simple, static, implementation of the [OKAPI](https://github.com/folio-org/okapi/) module that is hosted on _GitHub Pages_.
Only static Module Descriptor JSON files are served.

The **MDR** _GitHub Pages_ may be found at [https://tamulib.github.io/folio-module-descriptor-registry](https://tamulib.github.io/folio-module-descriptor-registry).

The Module Descriptors for each release are found within the `release/` subdirectory.


## Scripts

This repository provides additional scripts that may help facilitate the generation of the Module Descriptors.


### Populate Release

The **Populate Release** script helps automate building a list of module versions based on a specific flower release.
This release is then used to fetch all of the available module descriptors from an upstream source, such as those found on the **FOLIO Registry**.

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


### Populate via Branches and Commit Hashes

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
POPULATE_RELEASE_REPOSITORY_PART="heads" bash script/populate_release.sh fe7223e040d5d024f3f4961a3bc324d99a6fe7f5 aggies
```
