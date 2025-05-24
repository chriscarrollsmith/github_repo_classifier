#!/bin/bash

# Batch wrapper for workflow.sh
# Usage: bash workflow_batch.sh <INPUT_JSON_FILE>

if [ -z "$1" ]; then
  echo "Usage: bash $0 <JSON_FILE_WITH_ARRAY_OF_REPO_URLs>"
  exit 1
fi

INPUT_JSON="$1"

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed or not in PATH. Please install jq."
  exit 1
fi

# Ensure output file is reset
if [ -f "${OUTPUT_JSON_FILE:-classified_repos.json}" ]; then
  rm -f "${OUTPUT_JSON_FILE:-classified_repos.json}"
fi

echo "[]" > "${OUTPUT_JSON_FILE:-classified_repos.json}"

# Read URLs into array
mapfile -t REPO_URLS < <(jq -r '.[]' "$INPUT_JSON")

# Loop through each URL and invoke workflow.sh
for repo_url in "${REPO_URLS[@]}"; do
  echo "\n===== Processing $repo_url ====="
  bash workflow.sh "$repo_url"
done 