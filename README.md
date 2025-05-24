# Automated GitHub Repository Classifier & Discovery

This project provides a powerful set of Bash scripts to automate the analysis and classification of GitHub repositories using AI. It leverages open-source command-line tools like `repomix`, `llm`, and `gh` to extract repository information, summarize codebases, and apply an LLM-based classification schema.

## Purpose & Motivation

My thesis for this project is that there's a wealth of incredible, undiscovered technology available for free on GitHub. The primary bottleneck is discovery and distribution: good coders often aren't good distributors, and effective distributors aren't always proficient coders. By intelligently discovering such repositories, significant opportunities for innovation, impact, and even monetization can be unlocked through simple acts of distribution. This project demonstrates how an AI agent, powered by relatively simple bash scripts and CLI tools, can achieve such discovery.

## How It Works

The core of the analysis is handled by the `workflow.sh` script:

1.  **Input:** It takes a GitHub repository URL as an argument.
2.  **GitHub Data Fetching:** Uses the `gh` CLI to retrieve essential repository metadata (stars, commits, license, etc.).
3.  **Codebase Packing:** `repomix` creates a concise, LLM-friendly text representation of the repository's source code, excluding binary files and ignored patterns.
4.  **Schema & Template Management:** On its first run, `workflow.sh` automatically defines and saves a specialized `llm` schema and template, ensuring the LLM understands the desired output format and evaluation criteria.
5.  **LLM Classification:** The packed codebase summary and fetched GitHub metadata are fed to the configured LLM (e.g., Google Gemini Flash), which generates a JSON object based on the predefined classification schema.
6.  **Data Enrichment:** The script then enriches this LLM-generated JSON with all the initially fetched GitHub metadata.
7.  **Output Persistence:** The complete, enriched JSON object is appended to `classified_repos.json` (or a configured output file).

The `workflow_batch.sh` script automates this process for a list of repository URLs provided in a JSON file, making it easy to classify many projects sequentially.

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

### 1. LLM Classification Schema

The `workflow.sh` script automatically sets up the necessary `llm` schema and template. The classification criteria the LLM will evaluate and output are:

*   **`project_domain`** (string): The primary area or purpose of the project (e.g., 'web development framework', 'data science library', 'CLI tool for X').
*   **`motivation`** (string): The core problem the project aims to solve or its main purpose. The LLM will attempt to quote or paraphrase from the README if possible.
*   **`tech_stack`** (string): A list of primary programming languages, frameworks, and significant technologies observed.
*   **`code_quality`** (int, 1-10): An assessment of clarity, maintainability, structure, presence of tests, and adherence to best practices (1=poor, 10=excellent).
*   **`innovativeness`** (int, 1-10): How novel or unique are the ideas or implementation? (1=not innovative, 10=groundbreaking).
*   **`usefulness`** (int, 1-10): How useful or impactful is this project for its target audience or problem domain? (1=not useful, 10=very useful).
*   **`user_friendliness`** (int, 1-10): How easy is it for a new user to understand, set up, and use the project? Considers documentation, examples, and overall design (1=very difficult, 10=very easy).
*   **`underrated`** (bool, 0 or 1): Set to `1` (true) if the project deserves significantly more attention/stars given its quality, innovativeness, and usefulness relative to its current `star_count`. Otherwise, set to `0` (false).
*   **`overrated`** (bool, 0 or 1): Set to `1` (true) if the project receives more attention/stars than its quality, innovativeness, or usefulness warrants, relative to its current `star_count`. Otherwise, set to `0` (false).

### 2. Analyze a Single Repository

To analyze a single GitHub repository, run `workflow.sh` with its URL:

```bash
bash workflow.sh https://github.com/simonw/datasette
```

The output will be appended to `classified_repos.json`.

### 3. Analyze Multiple Repositories (Batch Processing)

For batch processing, create a JSON file (e.g., `repos_to_analyze.json`) containing an array of GitHub repository URLs:

```json
[
  "https://github.com/simonw/datasette",
  "https://github.com/Textualize/textual",
  "https://github.com/another-owner/another-project"
]
```

Then, execute `workflow_batch.sh` with the path to your JSON file:

```bash
bash workflow_batch.sh repos_to_analyze.json
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
  },
  // ... more classified repository entries
]
```

## Configuration

You can customize the behavior of the scripts by modifying the variables at the beginning of `workflow.sh`:

*   `DEFAULT_LLM_MODEL`: The primary LLM model alias to use (e.g., `"gemini-2.5-flash-preview-04-17"`).
*   `LLM_FALLBACK_MODEL`: An alternative model to use if the default model encounters rate limits or errors (e.g., `"gpt-4.1-mini"`).
*   `TEMPLATE_NAME`: The name used for the `llm` template (default: `"github_repo_classify"`).
*   `OUTPUT_JSON_FILE`: The name of the file where all classified results will be aggregated (default: `"classified_repos.json"`).
*   `REPOMIX_OUTPUT_FILE_PREFIX`: Prefix for temporary `repomix` output files.

## Contributing

Feel free to open issues or submit pull requests! All contributions, suggestions, and improvements are welcome.

## License

This project is open-sourced under the [MIT License](LICENSE.md).

---
