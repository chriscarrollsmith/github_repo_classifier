#!/bin/bash

# Script to analyze a GitHub repository and classify it using repomix and llm

DEFAULT_LLM_MODEL="gemini-2.5-flash-preview-05-20"
LLM_FALLBACK_MODEL="gpt-4.1-mini"

TEMPLATE_NAME="github_repo_classify"
OUTPUT_JSON_FILE="classified_repos.json"
REPOMIX_OUTPUT_FILE_PREFIX="repomix_out_" # Will append repo name
TEMP_REPO_DIR_PREFIX="temp_repo_clone_"   # Will append repo name

# --- Helper Functions ---
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo >&2 "Error: $1 is not installed or not in PATH. Please install it. Aborting."
    exit 1
  fi
}

# --- Sanity Checks ---
check_command gh
check_command llm
check_command repomix
check_command jq


# --- Argument Parsing ---
if [ -z "$1" ]; then
  echo "Usage: bash $0 <GITHUB_REPO_URL>"
  echo "Example: bash $0 https://github.com/owner/repo"
  exit 1
fi
REPO_URL=$1

# Extract owner/repo from URL (handles optional .git suffix and trailing slashes)
REPO_OWNER_NAME=$(echo "$REPO_URL" | sed 's|https://github.com/||' | sed 's|\.git$||' | sed 's|/$||')
if [ -z "$REPO_OWNER_NAME" ]; then
  echo "Invalid GitHub URL format. Expected https://github.com/owner/repo"
  exit 1
fi
SAFE_REPO_NAME=$(echo "$REPO_OWNER_NAME" | tr '/' '_')
REPOMIX_OUTPUT_FILE="${REPOMIX_OUTPUT_FILE_PREFIX}${SAFE_REPO_NAME}.txt"
TEMP_REPO_DIR="${TEMP_REPO_DIR_PREFIX}${SAFE_REPO_NAME}"

echo "Analyzing repository: $REPO_URL ($REPO_OWNER_NAME)"

# --- Schema Definition ---
if ! llm templates | grep -qw "$TEMPLATE_NAME :"; then
    SCHEMA_FIELDS=(
        "project_domain string" # "Primary area (e.g., web framework, data analysis tool)"
        "motivation string" # "The core problem the project aims to solve or its main purpose"
        "tech_stack string" # "Main programming languages, frameworks, and key libraries"
        "code_quality int" # "Scale 1-10 (1=poor, 10=excellent) for clarity, structure, maintainability, tests"
        "innovativeness int" # "Scale 1-10 (1=copycat, 10=groundbreaking) for novelty of idea or approach"
        "usefulness int" # "Scale 1-10 (1=not useful, 10=highly useful) for its intended audience/purpose"
        "user_friendliness int" # "Scale 1-10 (1=very hard, 10=very easy) for setup, usage, and documentation quality"
        "underrated int" # "0 (false) or 1 (true): Deserves significantly more attention/stars given its quality and usefulness vs. current star_count"
        "overrated int" # "0 (false) or 1 (true): Receives more attention/stars than its quality or usefulness warrants vs. current star_count"
    )

    # 1. Construct the schema definition string for 'llm --schema'
    #    Example: "'project_domain string,motivation string,...'"
    SCHEMA_DEFINITION_FOR_LLM_COMMAND="'$(IFS=,; echo "${SCHEMA_FIELDS[*]}")'"
    echo "Schema definition string for llm: $SCHEMA_DEFINITION_FOR_LLM_COMMAND"

# --- Template Definition ---

    echo "Defining LLM template: $TEMPLATE_NAME with embedded schema using model $DEFAULT_LLM_MODEL"
    # Note: $variable syntax is used by llm for template variables.
    SYSTEM_PROMPT_TEMPLATE="You are an expert software engineering analyst.
The user will provide a codebase summary (packed by repomix).
Your task is to evaluate this codebase and respond ONLY with a valid JSON object adhering to the defined structure.
Do NOT include any other text, explanation, or markdown formatting around the JSON.

Schema fields to populate:
- project_domain (string): Main domain or purpose (e.g., 'web development framework', 'data science library', 'CLI tool for X').
- motivation (string): The primary problem this project tries to solve or its key goals. Quote or paraphrase from the README if possible.
- tech_stack (string): List the primary programming languages, frameworks, and significant technologies observed.
- code_quality (int, 1-10): Assess clarity, maintainability, structure, tests, and use of best practices. (1=poor, 10=excellent).
- innovativeness (int, 1-10): How novel or unique are the ideas or implementation? (1=not innovative, 10=highly innovative).
- usefulness (int, 1-10): How useful or impactful is this project for its target audience or problem domain? (1=not useful, 10=very useful).
- user_friendliness (int, 1-10): How easy is it for a new user to understand, set up, and use the project? Consider documentation, examples, and overall design. (1=very difficult, 10=very easy).
- underrated (bool): Set to true if you believe the project deserves significantly more attention/stars than it has, considering its quality, innovativeness, and usefulness relative to its current star count of \$star_count. Otherwise, set to false.
- overrated (bool): Set to true if you believe the project receives more attention/stars than its quality, innovativeness, or usefulness warrants, relative to its current star count of \$star_count. Otherwise, set to false.

The repository has received \$star_count stars.
Ensure all fields in the JSON response are populated.
"
    # Save the template, associating it with the schema and default model
    if llm --schema "$SCHEMA_DEFINITION_FOR_LLM_COMMAND" --system "$SYSTEM_PROMPT_TEMPLATE" --save "$TEMPLATE_NAME" -m "$DEFAULT_LLM_MODEL"; then
      echo "Template $TEMPLATE_NAME saved with embedded schema."
    else
      echo "Failed to save template $TEMPLATE_NAME. Aborting."
      exit 1
    fi
else
    echo "Template $TEMPLATE_NAME already exists."
fi

# --- Fetch GitHub Repo Data ---
echo "Fetching GitHub data for $REPO_OWNER_NAME..."
GH_REPO_DATA=$(gh repo view "$REPO_OWNER_NAME" --json stargazerCount,pushedAt,licenseInfo,url 2>/dev/null)

STAR_COUNT=$(echo "$GH_REPO_DATA" | jq -r '.stargazerCount // 0')
LAST_COMMIT_DATE=$(echo "$GH_REPO_DATA" | jq -r '.pushedAt // "N/A"')
LICENSE=$(echo "$GH_REPO_DATA" | jq -r '.licenseInfo.spdxId // .licenseInfo.name // "N/A"')
# openIssuesCount from gh repo view is for *all* issues, not just open. Let's use API for open_issues_count
FETCHED_GITHUB_URL=$(echo "$GH_REPO_DATA" | jq -r '.url // "'"$REPO_URL"'"')

# --- Duplicate Check ---
if [ -f "$OUTPUT_JSON_FILE" ]; then
    echo "Checking for duplicates in $OUTPUT_JSON_FILE..."
    EXISTING_URL=$(jq -r --arg url "$FETCHED_GITHUB_URL" '.[] | select(.github_url == $url) | .github_url' "$OUTPUT_JSON_FILE" 2>/dev/null | head -1)
    if [ -n "$EXISTING_URL" ]; then
        echo "Repository $FETCHED_GITHUB_URL already exists in $OUTPUT_JSON_FILE. Skipping."
        exit 0
    fi
    echo "Repository not found in existing data. Proceeding with classification."
else
    echo "$OUTPUT_JSON_FILE does not exist yet. Proceeding with classification."
fi

# Get total commit count by summing across all paginated results
COMMIT_COUNT=$(gh api "repos/$REPO_OWNER_NAME/commits" --paginate -q '.[] | 1' 2>/dev/null | wc -l || echo 0)
if [ "$COMMIT_COUNT" == "null" ] || [ -z "$COMMIT_COUNT" ]; then COMMIT_COUNT=0; fi

# Fetch open issues count
OPEN_ISSUES_COUNT=$(gh api "repos/$REPO_OWNER_NAME" --jq '.open_issues_count // 0' 2>/dev/null || echo 0)

# Sanitize numeric variables for jq --argjson
if [ -z "$STAR_COUNT" ] || [ "$STAR_COUNT" = "null" ]; then STAR_COUNT=0; fi
if [ -z "$COMMIT_COUNT" ] || [ "$COMMIT_COUNT" = "null" ]; then COMMIT_COUNT=0; fi
if [ -z "$OPEN_ISSUES_COUNT" ] || [ "$OPEN_ISSUES_COUNT" = "null" ]; then OPEN_ISSUES_COUNT=0; fi

echo "--- Fetched Data ---"
echo "URL: $FETCHED_GITHUB_URL"
echo "Stars: $STAR_COUNT"
echo "Commits: $COMMIT_COUNT"
echo "Last Commit: $LAST_COMMIT_DATE"
echo "Open Issues: $OPEN_ISSUES_COUNT"
echo "License: $LICENSE"
echo "--------------------"

# --- Repomix ---
echo "Running repomix for $FETCHED_GITHUB_URL..."
if ! repomix --remote "$FETCHED_GITHUB_URL" --output "$REPOMIX_OUTPUT_FILE"; then
  echo "Repomix failed for $FETCHED_GITHUB_URL. Aborting."
  rm -f "$REPOMIX_OUTPUT_FILE" # Clean up partial file
  exit 1
fi
echo "Repomix output saved to $REPOMIX_OUTPUT_FILE"

# --- LLM Classification with Retry Logic ---
echo "Running LLM classification using template $TEMPLATE_NAME..."
CURRENT_MODEL_FOR_ATTEMPT=$DEFAULT_LLM_MODEL
CLASSIFICATION_JSON=""
SUCCESS=false

# Attempt 1: Default Model
echo "Attempting with $CURRENT_MODEL_FOR_ATTEMPT..."
RAW_OUTPUT=$(cat "$REPOMIX_OUTPUT_FILE" | llm -t "$TEMPLATE_NAME" -m "$CURRENT_MODEL_FOR_ATTEMPT" \
    -p star_count "$STAR_COUNT" 2>&1) # Capture stderr for error checking

IS_RATE_LIMIT=$(echo "$RAW_OUTPUT" | grep -q -i -E "rate limit|limit exceeded|quota|Too Many Requests"; echo $?)
IS_ERROR=$(echo "$RAW_OUTPUT" | grep -q -i -E "error|failed|Traceback"; echo $?) # General error check

if [ "$IS_RATE_LIMIT" -eq 0 ]; then # Rate limit error
    echo "Rate limit error with $CURRENT_MODEL_FOR_ATTEMPT. Trying fallback $LLM_FALLBACK_MODEL."
    CURRENT_MODEL_FOR_ATTEMPT=$LLM_FALLBACK_MODEL
    
    # Attempt 2: Fallback Model
    RAW_OUTPUT=$(cat "$REPOMIX_OUTPUT_FILE" | llm -t "$TEMPLATE_NAME" -m "$CURRENT_MODEL_FOR_ATTEMPT" \
        -p star_count "$STAR_COUNT" 2>&1)
    
    IS_RATE_LIMIT=$(echo "$RAW_OUTPUT" | grep -q -i -E "rate limit|limit exceeded|quota|Too Many Requests"; echo $?)
    IS_ERROR=$(echo "$RAW_OUTPUT" | grep -q -i -E "error|failed|Traceback"; echo $?)

    if [ "$IS_RATE_LIMIT" -eq 0 ]; then # Still rate limit with fallback
        echo "Rate limit error with fallback $CURRENT_MODEL_FOR_ATTEMPT. Waiting 60 seconds and retrying fallback."
        sleep 60
        
        # Attempt 3: Fallback Model after wait
        RAW_OUTPUT=$(cat "$REPOMIX_OUTPUT_FILE" | llm -t "$TEMPLATE_NAME" -m "$CURRENT_MODEL_FOR_ATTEMPT" \
            -p star_count "$STAR_COUNT" 2>&1)
        IS_ERROR=$(echo "$RAW_OUTPUT" | grep -q -i -E "error|failed|Traceback"; echo $?) # Update error status
    fi
fi

# Final check of RAW_OUTPUT from last attempt
if [ "$IS_ERROR" -eq 0 ] && ! (echo "$RAW_OUTPUT" | jq -e . >/dev/null 2>&1); then # If general error flag was set OR output is not JSON
    echo "LLM classification failed or produced invalid JSON for $FETCHED_GITHUB_URL. Error/Output:"
    echo "$RAW_OUTPUT"
elif [ "$IS_ERROR" -ne 0 ] && (echo "$RAW_OUTPUT" | jq -e . >/dev/null 2>&1); then # No error keywords but IS valid JSON
    echo "LLM classification successful for $FETCHED_GITHUB_URL."
    CLASSIFICATION_JSON="$RAW_OUTPUT"
    SUCCESS=true
elif [ "$IS_ERROR" -eq 0 ]; then # Error keywords present and it's likely not JSON either
    echo "LLM classification failed for $FETCHED_GITHUB_URL. Error:"
    echo "$RAW_OUTPUT"
else # No error keywords, and it IS valid JSON
    echo "LLM classification successful for $FETCHED_GITHUB_URL."
    CLASSIFICATION_JSON="$RAW_OUTPUT"
    SUCCESS=true
fi


# --- Process Result ---
if [ "$SUCCESS" = true ] && [ -n "$CLASSIFICATION_JSON" ]; then
    echo "Classification result for $FETCHED_GITHUB_URL:"
    echo "$CLASSIFICATION_JSON" | jq .

    # --- Enrichment Step: Add metadata fields ---
    echo "Enriching classification with metadata..."
    
    # Debug: Print all variables before enrichment
    echo "DEBUG: Variables for enrichment:"
    echo "  FETCHED_GITHUB_URL: '$FETCHED_GITHUB_URL'"
    echo "  STAR_COUNT: '$STAR_COUNT'"
    echo "  COMMIT_COUNT: '$COMMIT_COUNT'"
    echo "  LAST_COMMIT_DATE: '$LAST_COMMIT_DATE'"
    echo "  OPEN_ISSUES_COUNT: '$OPEN_ISSUES_COUNT'"
    echo "  LICENSE: '$LICENSE'"
    
    # Validate that numeric variables are actually numeric
    if ! [[ "$STAR_COUNT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: STAR_COUNT is not a valid number: '$STAR_COUNT'"
        STAR_COUNT=0
    fi
    if ! [[ "$COMMIT_COUNT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: COMMIT_COUNT is not a valid number: '$COMMIT_COUNT'"
        COMMIT_COUNT=0
    fi
    if ! [[ "$OPEN_ISSUES_COUNT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: OPEN_ISSUES_COUNT is not a valid number: '$OPEN_ISSUES_COUNT'"
        OPEN_ISSUES_COUNT=0
    fi
    
    # Test each --argjson parameter individually
    echo "DEBUG: Testing individual jq --argjson parameters..."
    
    # Test star_count
    if ! echo '{}' | jq --argjson star_count "$STAR_COUNT" '. + {star_count: $star_count}' >/dev/null 2>&1; then
        echo "ERROR: star_count parameter failed: '$STAR_COUNT'"
    else
        echo "DEBUG: star_count parameter OK"
    fi
    
    # Test commit_count
    if ! echo '{}' | jq --argjson commit_count "$COMMIT_COUNT" '. + {commit_count: $commit_count}' >/dev/null 2>&1; then
        echo "ERROR: commit_count parameter failed: '$COMMIT_COUNT'"
    else
        echo "DEBUG: commit_count parameter OK"
    fi
    
    # Test open_issues_count
    if ! echo '{}' | jq --argjson open_issues_count "$OPEN_ISSUES_COUNT" '. + {open_issues_count: $open_issues_count}' >/dev/null 2>&1; then
        echo "ERROR: open_issues_count parameter failed: '$OPEN_ISSUES_COUNT'"
    else
        echo "DEBUG: open_issues_count parameter OK"
    fi
    
    # Now attempt the full enrichment with error capture
    ENRICHMENT_ERROR=""
    ENRICHED_JSON=$(echo "$CLASSIFICATION_JSON" | jq --arg github_url "$FETCHED_GITHUB_URL" \
        --argjson star_count "$STAR_COUNT" \
        --argjson commit_count "$COMMIT_COUNT" \
        --arg last_commit_date "$LAST_COMMIT_DATE" \
        --argjson open_issues_count "$OPEN_ISSUES_COUNT" \
        --arg license "$LICENSE" \
        '. + {
            github_url: $github_url,
            star_count: $star_count,
            commit_count: $commit_count,
            last_commit_date: $last_commit_date,
            open_issues_count: $open_issues_count,
            license: $license
        }' 2>&1)
    
    ENRICHMENT_EXIT_CODE=$?
    
    if [ $ENRICHMENT_EXIT_CODE -ne 0 ]; then
        echo "ERROR: Enrichment failed with exit code $ENRICHMENT_EXIT_CODE"
        echo "ERROR: jq error output: $ENRICHED_JSON"
        ENRICHED_JSON=""
    fi

    if [ -n "$ENRICHED_JSON" ]; then
        echo "Enriched result:"
        echo "$ENRICHED_JSON" | jq .
        
        # Append to JSON array file
        if [ ! -f "$OUTPUT_JSON_FILE" ]; then
            echo "Creating $OUTPUT_JSON_FILE..."
            echo "[]" > "$OUTPUT_JSON_FILE"
        fi
        # Create a temporary file for the new content
        TEMP_JQ_OUTPUT_FILE=$(mktemp)
        if jq --argjson new_obj "$ENRICHED_JSON" '. += [$new_obj]' "$OUTPUT_JSON_FILE" > "$TEMP_JQ_OUTPUT_FILE"; then
            mv "$TEMP_JQ_OUTPUT_FILE" "$OUTPUT_JSON_FILE"
            echo "Enriched result appended to $OUTPUT_JSON_FILE"
        else
            echo "Error: Failed to update $OUTPUT_JSON_FILE with jq."
            rm -f "$TEMP_JQ_OUTPUT_FILE" # Clean up temp file on error
        fi
    else
        echo "Error: Failed to enrich classification JSON. Using original classification."
        echo "DEBUG: Enrichment failed, attempting to save original classification..."
        
        # Validate that the original classification is valid JSON
        if ! echo "$CLASSIFICATION_JSON" | jq -e . >/dev/null 2>&1; then
            echo "ERROR: Original classification JSON is also invalid!"
            echo "Original JSON content: $CLASSIFICATION_JSON"
        else
            echo "DEBUG: Original classification JSON is valid"
        fi
        
        # Fallback to original classification
        if [ ! -f "$OUTPUT_JSON_FILE" ]; then
            echo "Creating $OUTPUT_JSON_FILE..."
            echo "[]" > "$OUTPUT_JSON_FILE"
        fi
        TEMP_JQ_OUTPUT_FILE=$(mktemp)
        if jq --argjson new_obj "$CLASSIFICATION_JSON" '. += [$new_obj]' "$OUTPUT_JSON_FILE" > "$TEMP_JQ_OUTPUT_FILE" 2>&1; then
            mv "$TEMP_JQ_OUTPUT_FILE" "$OUTPUT_JSON_FILE"
            echo "Original result appended to $OUTPUT_JSON_FILE"
        else
            echo "Error: Failed to update $OUTPUT_JSON_FILE with jq."
            echo "jq error output: $(cat "$TEMP_JQ_OUTPUT_FILE")"
            rm -f "$TEMP_JQ_OUTPUT_FILE" # Clean up temp file on error
        fi
    fi
else
    echo "Failed to get valid classification for $FETCHED_GITHUB_URL after all attempts."
fi

# --- Cleanup ---
rm -f "$REPOMIX_OUTPUT_FILE"
echo "Done with $FETCHED_GITHUB_URL."
