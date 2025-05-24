#!/bin/bash

# Script to search for GitHub repositories using custom search terms
# Searches with different criteria to get both popular and obscure repos
# Outputs URLs in the format expected by workflow_batch.sh

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS] \"search_term1,search_term2,search_term3,...\""
    echo ""
    echo "Options:"
    echo "  -l, --limit NUM     Number of repos per search term (default: 15)"
    echo "  -o, --output FILE   Output file name (default: inputs.json)"
    echo "  -t, --total NUM     Total number of repos to select (default: 50)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 \"PDF parsing,RAG PDF,document extraction\""
    echo "  $0 -l 20 -t 60 \"machine learning,deep learning,neural networks\""
    echo "  $0 --limit 10 --output ml_repos.json \"tensorflow,pytorch,scikit-learn\""
    echo ""
    echo "Search terms will be used to find repositories with various filters:"
    echo "  - Created since 2020"
    echo "  - Mix of popular and low-star repositories"
    echo "  - Recent activity prioritized"
    exit 1
}

# Default values
LIMIT_PER_SEARCH=15
OUTPUT_FILE="inputs.json"
TOTAL_REPOS=50
SEARCH_TERMS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--limit)
            LIMIT_PER_SEARCH="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -t|--total)
            TOTAL_REPOS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option $1"
            usage
            ;;
        *)
            if [ -z "$SEARCH_TERMS" ]; then
                SEARCH_TERMS="$1"
            else
                echo "Error: Multiple search term arguments provided. Please provide a single comma-separated string."
                usage
            fi
            shift
            ;;
    esac
done

# Check if search terms were provided
if [ -z "$SEARCH_TERMS" ]; then
    echo "Error: No search terms provided."
    echo ""
    usage
fi

# Validate numeric arguments
if ! [[ "$LIMIT_PER_SEARCH" =~ ^[0-9]+$ ]] || [ "$LIMIT_PER_SEARCH" -lt 1 ]; then
    echo "Error: Limit per search must be a positive integer"
    exit 1
fi

if ! [[ "$TOTAL_REPOS" =~ ^[0-9]+$ ]] || [ "$TOTAL_REPOS" -lt 1 ]; then
    echo "Error: Total repos must be a positive integer"
    exit 1
fi

echo "Searching for repositories with terms: $SEARCH_TERMS"
echo "Limit per search: $LIMIT_PER_SEARCH"
echo "Total repos to select: $TOTAL_REPOS"
echo "Output file: $OUTPUT_FILE"
echo ""

# Create output file for search results
SEARCH_RESULTS_FILE="repo_search_results.json"
echo "[]" > $SEARCH_RESULTS_FILE

# Function to merge JSON arrays
merge_json() {
    local file1=$1
    local file2=$2
    jq -s '.[0] + .[1]' "$file1" "$file2" > temp.json && mv temp.json "$file1"
}

# Convert comma-separated search terms to array
IFS=',' read -ra SEARCH_ARRAY <<< "$SEARCH_TERMS"

# Counter for search operations
search_count=0

# Perform searches with different strategies for each term
for search_term in "${SEARCH_ARRAY[@]}"; do
    # Trim whitespace
    search_term=$(echo "$search_term" | xargs)
    
    if [ -z "$search_term" ]; then
        continue
    fi
    
    search_count=$((search_count + 1))
    
    echo "Search $search_count: General search for '$search_term'..."
    gh search repos "$search_term" --created=">=2020-01-01" --limit="$LIMIT_PER_SEARCH" \
        --json="fullName,description,stargazersCount,forksCount,pushedAt,url" > temp_search.json 2>/dev/null
    if [ $? -eq 0 ]; then
        merge_json $SEARCH_RESULTS_FILE temp_search.json
    else
        echo "  Warning: Search failed for '$search_term'"
    fi
    
    search_count=$((search_count + 1))
    echo "Search $search_count: Python-focused search for '$search_term'..."
    gh search repos "$search_term" --language=python --created=">=2020-01-01" --limit="$((LIMIT_PER_SEARCH / 2))" \
        --json="fullName,description,stargazersCount,forksCount,pushedAt,url" > temp_search.json 2>/dev/null
    if [ $? -eq 0 ]; then
        merge_json $SEARCH_RESULTS_FILE temp_search.json
    else
        echo "  Warning: Python search failed for '$search_term'"
    fi
    
    search_count=$((search_count + 1))
    echo "Search $search_count: Low-star search for '$search_term' (hidden gems)..."
    gh search repos "$search_term" --stars="1..20" --created=">=2021-01-01" --limit="$((LIMIT_PER_SEARCH / 3))" \
        --json="fullName,description,stargazersCount,forksCount,pushedAt,url" > temp_search.json 2>/dev/null
    if [ $? -eq 0 ]; then
        merge_json $SEARCH_RESULTS_FILE temp_search.json
    else
        echo "  Warning: Low-star search failed for '$search_term'"
    fi
    
    search_count=$((search_count + 1))
    echo "Search $search_count: Recently active search for '$search_term'..."
    gh search repos "$search_term" --updated=">=2024-01-01" --limit="$((LIMIT_PER_SEARCH / 3))" \
        --json="fullName,description,stargazersCount,forksCount,pushedAt,url" > temp_search.json 2>/dev/null
    if [ $? -eq 0 ]; then
        merge_json $SEARCH_RESULTS_FILE temp_search.json
    else
        echo "  Warning: Recent activity search failed for '$search_term'"
    fi
done

# Clean up
rm -f temp_search.json

# Remove duplicates and sort by stars
echo "Removing duplicates and processing results..."
jq 'unique_by(.fullName) | sort_by(.stargazersCount)' $SEARCH_RESULTS_FILE > temp.json && mv temp.json $SEARCH_RESULTS_FILE

echo "Search complete! Results saved to $SEARCH_RESULTS_FILE"
echo "Total repositories found: $(jq length $SEARCH_RESULTS_FILE)"

# Create output file with selected repositories
echo "Creating $OUTPUT_FILE with diverse repository selection..."

# Simple selection: take first N repositories (already sorted by stars, so we get a mix)
jq -r "map(.url) | .[0:$TOTAL_REPOS]" $SEARCH_RESULTS_FILE > $OUTPUT_FILE

echo "Created $OUTPUT_FILE with $(jq length $OUTPUT_FILE) repository URLs"

# Show some stats
echo ""
echo "Repository selection summary:"
echo "Total unique repositories found: $(jq length $SEARCH_RESULTS_FILE)"
echo "Selected for $OUTPUT_FILE: $(jq length $OUTPUT_FILE)"

echo ""
echo "Sample of selected repositories:"
jq -r '.[0:5][]' $OUTPUT_FILE

echo ""
echo "$OUTPUT_FILE is ready for use with workflow_batch.sh!" 