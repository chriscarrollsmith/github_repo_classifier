#!/bin/bash

# Script to list GitHub repositories for specified owners (users/organizations)
# Outputs repository URLs into a JSON file for workflow_batch.sh

# Ensure jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is not installed. Please install jq to use this script."
    echo "On macOS: brew install jq"
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    echo "On Fedora: sudo dnf install jq"
    echo "On Windows (with Chocolatey): choco install jq"
    exit 1
fi

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS] \"owner1,owner2,...\""
    echo ""
    echo "Arguments:"
    echo "  \"owner1,owner2,...\"   Required. Comma-separated list of GitHub usernames or"
    echo "                        organization names whose repositories will be fetched."
    echo ""
    echo "Options:"
    echo "  -o, --output FILE   Output file name (default: inputs.json)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 \"chriscarrollsmith,Promptly-Technologies-LLC\""
    echo "  $0 -o my_repos.json \"github,torvalds\""
    exit 1
}

# Default values
OUTPUT_FILE="inputs.json"
OWNERS_STRING=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Error: Unknown option $1"
            usage
            ;;
        *)
            if [ -n "$OWNERS_STRING" ]; then
                echo "Error: Owners string provided more than once. Please provide a single comma-separated string for owners."
                usage
            fi
            OWNERS_STRING="$1"
            shift
            ;;
    esac
done

# Check if owners string was provided
if [ -z "$OWNERS_STRING" ]; then
    echo "Error: No owners provided."
    usage
fi

# Convert comma-separated owners string to array and trim whitespace from each owner
TEMP_OWNERS_PARSED=()
IFS=',' read -ra RAW_OWNERS <<< "$OWNERS_STRING"
for owner in "${RAW_OWNERS[@]}"; do
    trimmed_owner=$(echo "$owner" | xargs) # xargs trims leading/trailing whitespace
    if [ -n "$trimmed_owner" ]; then
        TEMP_OWNERS_PARSED+=("$trimmed_owner")
    fi
done
OWNERS=("${TEMP_OWNERS_PARSED[@]}")

# Check if, after trimming and filtering, we have any owners left
if [ ${#OWNERS[@]} -eq 0 ]; then
    echo "Error: No valid owner names provided after processing the input string '$OWNERS_STRING'."
    usage
fi

echo "Fetching repositories for owners: ${OWNERS[*]}"
echo "Output file: $OUTPUT_FILE"
echo ""

# Create output file for search results
SEARCH_RESULTS_FILE="repo_search_results.json"
echo "[]" > $SEARCH_RESULTS_FILE

# Function to merge JSON arrays
merge_json() {
    local file1=$1
    local file2=$2

    # Ensure file2 (source) is not empty
    if [ ! -s "$file2" ]; then
        echo "  Warning: Temporary file $file2 is empty. Skipping merge for this source."
        return
    fi
    # Ensure file2 contains valid JSON
    if ! jq -e . "$file2" > /dev/null 2>&1; then
        echo "  Warning: Temporary file $file2 does not contain valid JSON. Content:"
        cat "$file2"
        echo "  Skipping merge for this source."
        return
    fi
    # Ensure file2's content is a JSON array
    if ! jq -e 'type == "array"' "$file2" > /dev/null 2>&1; then
        echo "  Warning: Data in $file2 is not a JSON array. Content:"
        cat "$file2"
        echo "  Skipping merge for this source."
        return
    fi
    
    # Perform the merge
    jq -s '.[0] + .[1]' "$file1" "$file2" > temp_merge.json
    if [ $? -eq 0 ]; then
        mv temp_merge.json "$file1"
    else
        echo "  Error: Failed to merge $file1 and $file2. Check temp_merge.json and the source files."
        rm -f temp_merge.json # Clean up failed merge attempt
    fi
}

# Fetch repositories for each owner
for owner in "${OWNERS[@]}"; do
    echo "Fetching repositories for $owner..."
    TEMP_OWNER_REPOS_FILE="temp_${owner}_repos.json"
    TEMP_OWNER_ERROR_LOG="temp_${owner}_error.log"
    
    # Fetch up to 500 repos per owner; gh cli handles pagination.
    gh repo list "$owner" --limit 500 --json="url" > "$TEMP_OWNER_REPOS_FILE" 2> "$TEMP_OWNER_ERROR_LOG"
    gh_exit_code=$?
    
    error_log_content=""
    if [ -s "$TEMP_OWNER_ERROR_LOG" ]; then
        error_log_content=$(cat "$TEMP_OWNER_ERROR_LOG")
    fi

    if [ $gh_exit_code -eq 0 ]; then
        if [ -s "$TEMP_OWNER_REPOS_FILE" ]; then
            # Simpler check: if gh succeeded and produced a non-empty file,
            # let merge_json handle the detailed JSON validation.
            merge_json "$SEARCH_RESULTS_FILE" "$TEMP_OWNER_REPOS_FILE"
        else
            echo "  Warning: gh command for $owner succeeded, but $TEMP_OWNER_REPOS_FILE is empty."
            if [ -n "$error_log_content" ]; then echo "  Stderr from gh: $error_log_content"; fi
        fi
    else
        echo "  Error: gh repo list command failed for $owner (exit code $gh_exit_code)."
        if [ -n "$error_log_content" ]; then
             echo "  Stderr from gh: $error_log_content"
        else
            echo "  (No specific error message from gh in $TEMP_OWNER_ERROR_LOG)"
        fi
        # If gh failed, $TEMP_OWNER_REPOS_FILE might be empty or contain partial/error JSON.
        # merge_json has its own checks for validity if the file still gets processed.
    fi
    rm -f "$TEMP_OWNER_REPOS_FILE" "$TEMP_OWNER_ERROR_LOG"
done

# Process results: get unique URLs and output as a JSON array
echo ""
echo "Processing fetched repositories..."
if [ -s "$SEARCH_RESULTS_FILE" ]; then
    jq 'unique_by(.url) | map(.url)' "$SEARCH_RESULTS_FILE" > "$OUTPUT_FILE"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to process results with jq. Check $SEARCH_RESULTS_FILE and $OUTPUT_FILE."
        # Optionally, exit 1 if jq processing fails critically
    else
        echo "Processing complete! Raw fetched data is in $SEARCH_RESULTS_FILE."
        echo "Final list of unique repository URLs saved to $OUTPUT_FILE."
    fi
else
    echo "Warning: $SEARCH_RESULTS_FILE is empty. No repositories were successfully fetched."
    echo "[]" > "$OUTPUT_FILE" # Create an empty JSON array as output
fi

echo ""
echo "Repository processing summary:"
TOTAL_FETCHED_UNIQUE_OBJECTS=$(jq 'length' "$SEARCH_RESULTS_FILE" 2>/dev/null || echo 0)
echo "Total repository objects fetched (raw data in $SEARCH_RESULTS_FILE): $TOTAL_FETCHED_UNIQUE_OBJECTS"
SELECTED_COUNT=$(jq 'length' "$OUTPUT_FILE" 2>/dev/null || echo 0)
echo "Unique repository URLs written to $OUTPUT_FILE: $SELECTED_COUNT"

echo ""
echo "Sample of selected repository URLs (up to 5 from $OUTPUT_FILE):"
if [ "$SELECTED_COUNT" -gt 0 ]; then
    jq '.[:5]' "$OUTPUT_FILE"
else
    echo "(No repositories to display)"
fi

echo ""
echo "$OUTPUT_FILE is ready for use with workflow_batch.sh!" 