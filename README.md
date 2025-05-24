# Automated GitHub Repository Classifier & Discovery

This project provides a powerful set of Bash scripts to automate the discovery, analysis, and classification of GitHub repositories using AI. It leverages open-source command-line tools like `repomix`, `llm`, and `gh` to search for repositories, extract repository information, summarize codebases, and apply an LLM-based classification schema.

## Purpose & Motivation

My thesis for this project is that there's a wealth of incredible, undiscovered technology available for free on GitHub. The primary bottleneck is discovery and distribution: good coders often aren't good distributors, and effective distributors aren't always proficient coders. By intelligently discovering such repositories, significant opportunities for innovation, impact, and even monetization can be unlocked through simple acts of distribution. This project demonstrates how an AI agent, powered by relatively simple bash scripts and CLI tools, can achieve such discovery.

## How It Works

The project consists of two main components: **repository discovery** and **repository analysis**.

### Repository Discovery

The `search_repos.sh` script (which can be used for any type of repository search, not just PDF-related) automates the discovery of relevant repositories:

1. **Flexible Search Terms:** Takes comma-separated search terms as arguments
2. **Multi-Strategy Search:** For each search term, performs multiple GitHub searches:
   - General search across all repositories
   - Python-focused search
   - Low-star "hidden gems" search (1-20 stars)
   - Recently active repositories search
3. **Intelligent Filtering:** Filters for repositories created since 2020 and applies various criteria
4. **Deduplication:** Removes duplicate repositories and provides a diverse selection
5. **Output Generation:** Creates a JSON array of repository URLs ready for batch analysis

### Repository Analysis

The core analysis is handled by the `classify_repos.sh` script:

1. **Input:** Takes a GitHub repository URL as an argument
2. **GitHub Data Fetching:** Uses the `gh` CLI to retrieve essential repository metadata (stars, commits, license, etc.)
3. **Codebase Packing:** `repomix` creates a concise, LLM-friendly text representation of the repository's source code, excluding binary files and ignored patterns
4. **Schema & Template Management:** On its first run, `classify_repos.sh` automatically defines and saves a specialized `llm` schema and template, ensuring the LLM understands the desired output format and evaluation criteria
5. **LLM Classification:** The packed codebase summary and fetched GitHub metadata are fed to the configured LLM (e.g., Google Gemini Flash), which generates a JSON object based on the predefined classification schema
6. **Data Enrichment:** The script enriches this LLM-generated JSON with all the initially fetched GitHub metadata
7. **Output Persistence:** The complete, enriched JSON object is appended to `classified_repos.json` (or a configured output file)

The `classify_batch.sh` script automates this process for a list of repository URLs provided in a JSON file, making it easy to classify many projects sequentially.

## Prerequisites

To run the scripts, you will need to be in a Bash shell. This comes pre-installed on most Linux and macOS systems. If you're on Windows, you can install [Git Bash](https://git-scm.com/downloads) or [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

Before running these scripts, you need to install the following command-line tools and ensure they are accessible in your system's `PATH`:

*   **`gh` CLI:** [GitHub CLI](https://cli.github.com/) - For interacting with GitHub APIs. You'll need to log in (`gh auth login`).
*   **`llm` CLI:** [LLM - A CLI for interacting with LLMs](https://llm.datasette.io/en/stable/) by Simon Willison.
*   **`repomix` CLI:** [Repomix](https://github.com/simonw/repomix) by Simon Willison - For packing repositories into single files.
*   **`jq`:** A lightweight and flexible command-line JSON processor.

You will also need to configure `llm` with API keys for your chosen LLM providers (e.g., Google Gemini, OpenAI GPT). Refer to the [`llm` documentation](https://llm.datasette.io/en/stable/setup.html) for detailed setup instructions. Note that using non-OpenAI models requires [installing additional plugins](https://llm.datasette.io/en/stable/plugins/installing-plugins.html).

### Installation Steps

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/chriscarrollsmith/github_repo_classifier.git
    cd github_repo_classifier
    ```

## Usage

### 1. Repository Discovery

Use the `search_repos.sh` script to discover repositories based on search terms. Despite its name, this script can search for any type of repository:

#### Basic Usage
```bash
# Search for PDF parsing repositories
./search_repos.sh "PDF parsing,RAG PDF,document extraction,PDF table extraction"

# Search for machine learning repositories
./search_repos.sh "machine learning,deep learning,neural networks,tensorflow"

# Search for web development frameworks
./search_repos.sh "react,vue,angular,svelte,web framework"
```

#### Advanced Usage with Options
```bash
# Custom limits and output file
./search_repos.sh -l 20 -t 60 -o ml_repos.json "machine learning,deep learning"

# Fewer repositories per search term, different output
./search_repos.sh --limit 10 --total 30 --output web_repos.json "react,vue,angular"
```

#### Options
- `-l, --limit NUM`: Number of repositories per search term (default: 15)
- `-o, --output FILE`: Output filename (default: inputs.json)
- `-t, --total NUM`: Total number of repositories to select (default: 50)
- `-h, --help`: Show usage information

The script will create a JSON file with an array of repository URLs ready for batch analysis.

### 2. LLM Classification Schema

The `classify_repos.sh` script automatically sets up the necessary `llm` schema and template. The classification criteria the LLM will evaluate and output are:

*   **`project_domain`** (string): The primary area or purpose of the project (e.g., 'web development framework', 'data science library', 'CLI tool for X').
*   **`motivation`** (string): The core problem the project aims to solve or its main purpose. The LLM will attempt to quote or paraphrase from the README if possible.
*   **`tech_stack`** (string): A list of primary programming languages, frameworks, and significant technologies observed.
*   **`code_quality`** (int, 1-10): An assessment of clarity, maintainability, structure, presence of tests, and adherence to best practices (1=poor, 10=excellent).
*   **`innovativeness`** (int, 1-10): How novel or unique are the ideas or implementation? (1=not innovative, 10=groundbreaking).
*   **`usefulness`** (int, 1-10): How useful or impactful is this project for its target audience or problem domain? (1=not useful, 10=very useful).
*   **`user_friendliness`** (int, 1-10): How easy is it for a new user to understand, set up, and use the project? Considers documentation, examples, and overall design (1=very difficult, 10=very easy).
*   **`underrated`** (bool, 0 or 1): Set to `1` (true) if the project deserves significantly more attention/stars given its quality, innovativeness, and usefulness relative to its current `star_count`. Otherwise, set to `0` (false).
*   **`overrated`** (bool, 0 or 1): Set to `1` (true) if the project receives more attention/stars than its quality, innovativeness, or usefulness warrants, relative to its current `star_count`. Otherwise, set to `0` (false).

### 3. Analyze a Single Repository

To analyze a single GitHub repository, run `classify_repos.sh` with its URL:

```bash
bash classify_repos.sh https://github.com/simonw/datasette
```

The output will be appended to `classified_repos.json`.

### 4. Analyze Multiple Repositories (Batch Processing)

#### Option A: Use the Discovery Script + Batch Analysis
```bash
# 1. Discover repositories
./search_repos.sh "PDF parsing,RAG PDF,document extraction" 

# 2. Analyze all discovered repositories
bash classify_batch.sh inputs.json
```

#### Option B: Manual Repository List
Create a JSON file (e.g., `repos_to_analyze.json`) containing an array of GitHub repository URLs:

```json
[
  "https://github.com/simonw/datasette",
  "https://github.com/Textualize/textual",
  "https://github.com/another-owner/another-project"
]
```

Then execute `classify_batch.sh`:

```bash
bash classify_batch.sh repos_to_analyze.json
```

### 5. Complete Workflow Example

Here's a complete example of discovering and analyzing PDF parsing repositories:

```bash
# 1. Discover PDF parsing repositories
./search_repos.sh "PDF parsing,RAG PDF,document extraction,PDF table extraction,OCR PDF,langchain PDF,unstructured PDF"

# 2. Analyze all discovered repositories
bash classify_batch.sh inputs.json

# 3. View results
jq '.[0]' classified_repos.json  # View first classified repository
```

### Output File

All classified and enriched results are appended as JSON objects to the `classified_repos.json` file by default. Each entry in this JSON array will look similar to this example:

```json
[
  {
    "project_domain": "Data analysis and publishing tool",
    "motivation": "To easily publish and explore data from CSVs, SQLite databases, and more, as interactive websites and APIs.",
    "tech_stack": "Python, SQLite, Starlette, Jinja2",
    "code_quality": 9,
    "innovativeness": 9,
    "usefulness": 10,
    "user_friendliness": 9,
    "underrated": 1,
    "overrated": 0,
    "github_url": "https://github.com/simonw/datasette",
    "star_count": 8000,
    "commit_count": 5000,
    "last_commit_date": "2023-10-27T12:34:56Z",
    "open_issues_count": 150,
    "license": "Apache-2.0"
  }
]
```

## Configuration

You can customize the behavior of the scripts by modifying the variables at the beginning of `classify_repos.sh`:

*   `DEFAULT_LLM_MODEL`: The primary LLM model alias to use (e.g., `"gemini-2.5-flash-preview-04-17"`).
*   `LLM_FALLBACK_MODEL`: An alternative model to use if the default model encounters rate limits or errors (e.g., `"gpt-4.1-mini"`).
*   `TEMPLATE_NAME`: The name used for the `llm` template (default: `"github_repo_classify"`).
*   `OUTPUT_JSON_FILE`: The name of the file where all classified results will be aggregated (default: `"classified_repos.json"`).
*   `REPOMIX_OUTPUT_FILE_PREFIX`: Prefix for temporary `repomix` output files.

## Use Cases

This project is particularly useful for:

- **Technology Scouting:** Discovering innovative but underrated repositories in specific domains
- **Competitive Analysis:** Understanding the landscape of tools and libraries in a particular field
- **Due Diligence:** Evaluating the quality and potential of open-source projects
- **Research:** Analyzing trends and patterns in software development
- **Investment Research:** Identifying promising open-source projects that might warrant commercial attention

## Contributing

Feel free to open issues or submit pull requests! All contributions, suggestions, and improvements are welcome.

## License

This project is open-sourced under the [MIT License](LICENSE.md).

---
