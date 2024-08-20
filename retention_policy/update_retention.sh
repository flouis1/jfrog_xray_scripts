#!/bin/bash

# Check if TOKEN_ACCESS and JFROG_PLATFORM_URL variables are set
if [ -z "$TOKEN_ACCESS" ] || [ -z "$JFROG_PLATFORM_URL" ]; then
  echo "Error: TOKEN_ACCESS and JFROG_PLATFORM_URL environment variables must be set."
  exit 1
fi

# Define the Artifactory and Xray API URLs
ARTIFACTORY_API_URL="$JFROG_PLATFORM_URL/artifactory/api/repositories"
XRAY_API_URL="$JFROG_PLATFORM_URL/xray/api/v1/repos_config"

# Output file names
OUTPUT_FILE="repositories.json"
ERROR_LOG="error.log"
REPOS_TO_UPDATE="repos_to_update.json"
REMAINING_REPOS="remaining_repos.json"

# Function to display the helper
function show_help {
  echo "Usage: $0 [-r regex] [-l repo_list] [-retry] [-dryrun] [-f file]"
  echo "  -r regex        Filter repositories by regex."
  echo "  -l repo_list    Filter repositories by a list of repo keys."
  echo "  -retry          Retry updating repositories from the repos_to_update.json file."
  echo "  -dryrun         Generate the repos_to_update.json file without updating repositories."
  echo "  -f file         Specify a file to update configurations from."
  exit 1
}

# Function to fetch repositories from Artifactory
function fetch_repositories {
  echo $ARTIFACTORY_API_URL
  local response=$(curl -s -H "Authorization: Bearer $TOKEN_ACCESS" $ARTIFACTORY_API_URL)
  
  
  if [ $? -eq 0 ]; then
    echo "Request was successful. Saving data to $OUTPUT_FILE"
    echo $response | jq '[.[] | select(.type != "VIRTUAL")]' > $OUTPUT_FILE
  else
    echo "Request failed."
    exit 1
  fi
}

# Function to filter repository keys
function filter_repo_keys {
  local repo_keys=$(cat $OUTPUT_FILE | jq -r '.[].key')
  
  if [ -n "$filter_regex" ]; then
    repo_keys=$(echo "$repo_keys" | grep -E "$filter_regex")
  elif [ ${#repo_list[@]} -ne 0 ]; then
    repo_keys=$(echo "$repo_keys" | grep -E "$(IFS=\|; echo "${repo_list[*]}")")
  fi
  
  echo "$repo_keys"
}

# Function to fetch indexing config for a repository
function fetch_indexing_config {
  local repo_key=$1
  local indexing_config_response=$(curl -s -H "Authorization: Bearer $TOKEN_ACCESS" "$XRAY_API_URL/$repo_key" | jq 'select(.error == null)')
  echo "$indexing_config_response"
}

# Function to check retention policy and prepare update list
function prepare_updates {
  local repo_keys=$1

  for repo_key in $repo_keys; do
    if [ -z "$config_file" ]; then
      echo "----------------------------------------"
      echo "Fetching indexing config for repository: $repo_key"
      echo "----------------------------------------"
    fi
    
    # Fetch the indexing config for the repository
    local indexing_config_response=$(fetch_indexing_config $repo_key)
    
    if [ -n "$indexing_config_response" ]; then
      local retention_in_days=$(echo "$indexing_config_response" | jq -r '.repo_config.retention_in_days')
      
      # Check if retention_in_days is set and if it is less than or equal to 180
      if [ -n "$retention_in_days" ] && [ "$retention_in_days" -le 180 ]; then
        repos_to_update+=("$repo_key")
        
        # Update retention_in_days to 180
        local new_json=$(echo "$indexing_config_response" | jq '.repo_config.retention_in_days = 180')
        
        # Write the updated JSON to the repos_to_update file
        echo "$new_json" | grep -v '^\s*$' >> "$REPOS_TO_UPDATE"
        
        echo "Updated JSON for repository $repo_key:"
        echo "$new_json"
      fi
    else
      echo "Repository $repo_key is either not indexed or does not exist."
      echo "$repo_key" >> "$ERROR_LOG"
    fi
  done
}

# Function to update repository retention policy
function update_repo {
  local repo_key=$1
  local new_json=$2
  update_response=$(curl -s -X PUT -H "Authorization: Bearer $TOKEN_ACCESS" -H "Content-Type: application/json" -d "$new_json" "$XRAY_API_URL")

  if [ $? -eq 0 ]; then
    echo "Successfully updated retention policy for repository $repo_key."
    # Remove the successfully processed repository from repos_to_update.json
    jq -c "select(.repo_name != \"$repo_key\")" $REPOS_TO_UPDATE > temp.json && mv temp.json $REPOS_TO_UPDATE
  else
    echo "Failed to update retention policy for repository $repo_key."
    echo $repo_key >> $REMAINING_REPOS
  fi
}

# Function to process updates from a file
function process_updates_from_file {
  local config_file=$1
  local repos_to_update=$(jq -r '.repo_name' $config_file)
  
  for repo_key in $repos_to_update; do
    local new_json=$(jq -r --arg key "$repo_key" 'select(.repo_name == $key)' $config_file)
    update_repo $repo_key "$new_json"
  done
}

# Parse command-line arguments
while getopts ":r:l:retry:dryrun:f:" opt; do
  case $opt in
    r)
      filter_regex=$OPTARG
      ;;
    l)
      IFS=',' read -ra repo_list <<< "$OPTARG"
      ;;
    retry)
      retry=true
      ;;
    dryrun)
      dryrun=true
      ;;
    f)
      config_file=$OPTARG
      ;;
    *)
      show_help
      ;;
  esac
done

# Clear previous logs and output files
> $ERROR_LOG
> $REPOS_TO_UPDATE
> $REMAINING_REPOS

if [ "$retry" = true ]; then
  if [ -f $REPOS_TO_UPDATE ]; then
    process_updates_from_file $REPOS_TO_UPDATE
  else
    echo "Retry mode enabled but repos_to_update.json file not found."
    exit 1
  fi
elif [ -n "$config_file" ]; then
  process_updates_from_file $config_file
else
  fetch_repositories
  repo_keys=$(filter_repo_keys)
  prepare_updates "$repo_keys"
fi

if [ "$dryrun" = true ]; then
  echo "Dry run mode enabled. The repos_to_update.json file has been generated."
  exit 0
fi

if [ -z "$config_file" ]; then
  for repo_key in "${repos_to_update[@]}"; do
    new_json=$(jq -r --arg key "$repo_key" 'select(.repo_name == $key)' $REPOS_TO_UPDATE)
    update_repo $repo_key "$new_json"
  done
fi

# Echo a message with the list of repositories to be updated
if [ ${#repos_to_update[@]} -ne 0 ]; then
  echo "Retention policy for the following repos has been updated:"
  for repo in "${repos_to_update[@]}"; do
    echo "- $repo"
  done
else
  echo "No repositories needed updating."
fi
