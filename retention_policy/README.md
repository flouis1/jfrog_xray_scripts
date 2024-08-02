# Update Retention Script

This bash script is designed to update the retention policy for repositories in JFrog Artifactory. It checks and modifies the repository configurations to ensure the retention policy is set to xx days, and provides options to filter, run in dry run mode, and retry failed updates.

## Prerequisites

Make sure the following environment variables are set before running the script:
- `TOKEN_ACCESS`: The access token for the JFrog API.
- `JFROG_PLATFORM_URL`: The base URL for the JFrog platform.

## Usage

```sh
./update_retention.sh [-r regex] [-l repo_list] [-retry] [-dryrun] [-f file]
```

### Options

- `-r regex`: Filter repositories by regex.
- `-l repo_list`: Filter repositories by a list of repo keys (comma-separated).
- `-retry`: Retry updating repositories from the `repos_to_update.json` file.
- `-dryrun`: Generate the `repos_to_update.json` file without updating repositories.
- `-f file`: Specify a file to update configurations from.

## Functions

### fetch_repositories

Fetches the list of repositories from Artifactory and saves it to `repositories.json`.

### filter_repo_keys

Filters repository keys based on regex or a list of repository keys provided.

### fetch_indexing_config

Fetches the indexing configuration for a specified repository.

### prepare_updates

Checks the retention policy for repositories and prepares the list for updates.

### update_repo

Updates the retention policy for a specified repository and removes it from the `repos_to_update.json` file if the update is successful.

### process_updates_from_file

Processes updates from a specified file.

## Logs and Output Files

- `repositories.json`: Contains the fetched repository information.
- `error.log`: Logs errors encountered during the script execution.
- `repos_to_update.json`: Contains the list of repositories to be updated.
- `remaining_repos.json`: Contains the list of repositories that failed to update.

## Example

To filter repositories by a regex and update their retention policy, run:

```sh
export TOKEN_ACCESS="your_access_token"
export JFROG_PLATFORM_URL="https://your.jfrog.instance"
./update_retention.sh -r '.*-local'
```

To run in dry run mode:

```sh
./update_retention.sh -r '.*-local' -dryrun
```

To retry updating repositories from the `repos_to_update.json` file:

```sh
./update_retention.sh -retry
```

To specify a file for updating configurations:

```sh
./update_retention.sh -f custom_repos.json
```
