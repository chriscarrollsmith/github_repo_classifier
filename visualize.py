# /// script
# dependencies = [
#   "pandas",
#   "numpy",
# ]
# ///

# Enhanced Python script for repository analysis and HTML report generation
import json
import pandas as pd
import numpy as np
from urllib.parse import urlparse

# Load data
print("Loading repository data...")
with open('classified_repos.json', 'r') as f:
    data = json.load(f)

df = pd.DataFrame(data)
print(f"Loaded {len(df)} repositories")

# Extract repository names for better labeling
def extract_repo_name(url):
    """Extract owner/repo from GitHub URL"""
    try:
        path = urlparse(url).path
        return path.strip('/').replace('github.com/', '')
    except:
        return url

df['repo_name'] = df['github_url'].apply(extract_repo_name)

# Create composite scores for better analysis
df['overall_quality'] = (df['code_quality'] + df['innovativeness'] + 
                        df['usefulness'] + df['user_friendliness']) / 4

df['value_score'] = df['overall_quality'] / np.log10(df['star_count'] + 10)  # Higher is more undervalued
df['overrated_score'] = np.log10(df['star_count'] + 10) / df['overall_quality']  # Higher is more overrated

# Create color mapping
def get_color_category(row):
    if row['underrated'] == 1:
        return 'Underrated'
    elif row['overrated'] == 1:
        return 'Overrated'
    else:
        return 'Normal'

df['category'] = df.apply(get_color_category, axis=1)

# Generate summary reports
print("\nGenerating summary reports...")

# Top undervalued repositories
print("\n=== TOP 10 UNDERVALUED REPOSITORIES ===")
top_undervalued = df.nlargest(10, 'value_score')[['repo_name', 'star_count', 'overall_quality', 'value_score', 'project_domain']]
print(top_undervalued.to_string(index=False))

# Best overall repositories
print("\n=== TOP 10 BEST OVERALL REPOSITORIES ===")
best_overall = df.nlargest(10, 'overall_quality')[['repo_name', 'star_count', 'overall_quality', 'code_quality', 'innovativeness', 'usefulness', 'user_friendliness', 'project_domain']]
print(best_overall.to_string(index=False))

# Flagged underrated repositories
print(f"\n=== LLM-FLAGGED UNDERRATED REPOSITORIES ({df['underrated'].sum()} total) ===")
underrated_repos = df[df['underrated'] == 1][['repo_name', 'star_count', 'code_quality', 'motivation']].head(10)
print(underrated_repos.to_string(index=False))

# Create enhanced HTML report with both undervalued and best overall repositories
print("\nCreating enhanced HTML repository report...")
with open('repository_report.html', 'w', encoding='utf-8') as f:
    f.write('''<html>
<head>
    <title>GitHub Repository Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; border-bottom: 2px solid #333; }
        h2 { color: #666; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .undervalued { background-color: #fff3cd; }
        .high-quality { background-color: #d4edda; }
        .overrated { background-color: #f8d7da; }
        .llm-flagged { background-color: #ffeaa7 !important; border-left: 4px solid #fdcb6e; }
        .llm-flagged-overrated { background-color: #f5c6cb !important; border-left: 4px solid #dc3545; }
        .repo-link { text-decoration: none; color: #0366d6; }
        .repo-link:hover { text-decoration: underline; }
        .score { font-weight: bold; }
        .summary { background-color: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .flag-indicator { font-weight: bold; color: #e17055; }
        .legend { background-color: #f8f9fa; padding: 10px; border-radius: 5px; margin: 10px 0; font-size: 0.9em; }
    </style>
</head>
<body>''')
    
    f.write(f'<h1>GitHub Repository Analysis Report</h1>')
    f.write(f'<div class="summary">')
    f.write(f'<p><strong>Analysis Summary:</strong></p>')
    f.write(f'<ul>')
    f.write(f'<li>Total repositories analyzed: {len(df)}</li>')
    f.write(f'<li>Unique project domains: {df["project_domain"].nunique()}</li>')
    f.write(f'<li>LLM-flagged underrated repositories: {df["underrated"].sum()}</li>')
    f.write(f'<li>LLM-flagged overrated repositories: {df["overrated"].sum()}</li>')
    f.write(f'<li>Average overall quality score: {df["overall_quality"].mean():.2f}/10</li>')
    f.write(f'</ul>')
    f.write(f'</div>')
    
    # Top Undervalued Repositories Table
    f.write('<h2>🔍 Top 20 Most Undervalued Repositories</h2>')
    f.write('<p>These repositories have high quality scores relative to their star count, suggesting they may be hidden gems.</p>')
    f.write('<div class="legend">')
    f.write('<strong>Legend:</strong> Repositories with highlighted background and orange left border are specifically flagged by the LLM as underrated.')
    f.write('</div>')
    f.write('<table class="undervalued">')
    f.write('<tr><th>Rank</th><th>Repository</th><th>Stars</th><th>Overall Quality</th><th>Innovation</th><th>Value Score</th><th>Domain</th><th>Motivation</th></tr>')
    
    for idx, (_, row) in enumerate(df.nlargest(20, 'value_score').iterrows(), 1):
        row_class = 'llm-flagged' if row['underrated'] == 1 else ''
        f.write(f'<tr class="{row_class}">')
        f.write(f'<td>{idx}</td>')
        f.write(f'<td><a href="{row["github_url"]}" target="_blank" class="repo-link">{row["repo_name"]}</a></td>')
        f.write(f'<td>{row["star_count"]}</td>')
        f.write(f'<td class="score">{row["overall_quality"]:.2f}</td>')
        f.write(f'<td class="score">{row["innovativeness"]}</td>')
        f.write(f'<td class="score">{row["value_score"]:.3f}</td>')
        f.write(f'<td>{row["project_domain"]}</td>')
        f.write(f'<td>{row["motivation"][:100]}{"..." if len(row["motivation"]) > 100 else ""}</td>')
        f.write(f'</tr>')
    
    f.write('</table>')
    
    # Best Overall Repositories Table
    f.write('<h2>⭐ Top 20 Best Overall Repositories</h2>')
    f.write('<p>These repositories have the highest overall quality scores across all evaluation criteria.</p>')
    f.write('<table class="high-quality">')
    f.write('<tr><th>Rank</th><th>Repository</th><th>Stars</th><th>Overall Quality</th><th>Code Quality</th><th>Innovation</th><th>Usefulness</th><th>User Friendly</th><th>Domain</th></tr>')
    
    for idx, (_, row) in enumerate(df.nlargest(20, 'overall_quality').iterrows(), 1):
        f.write(f'<tr>')
        f.write(f'<td>{idx}</td>')
        f.write(f'<td><a href="{row["github_url"]}" target="_blank" class="repo-link">{row["repo_name"]}</a></td>')
        f.write(f'<td>{row["star_count"]}</td>')
        f.write(f'<td class="score">{row["overall_quality"]:.2f}</td>')
        f.write(f'<td class="score">{row["code_quality"]}</td>')
        f.write(f'<td class="score">{row["innovativeness"]}</td>')
        f.write(f'<td class="score">{row["usefulness"]}</td>')
        f.write(f'<td class="score">{row["user_friendliness"]}</td>')
        f.write(f'<td>{row["project_domain"]}</td>')
        f.write(f'</tr>')
    
    f.write('</table>')
    
    # Overrated Repositories Table
    f.write('<h2>📉 Top 20 Most Overrated Repositories</h2>')
    f.write('<p>These repositories have high star counts relative to their quality scores, suggesting they may be receiving more attention than they merit.</p>')
    f.write('<div class="legend">')
    f.write('<strong>Legend:</strong> Repositories with highlighted background and red left border are specifically flagged by the LLM as overrated.')
    f.write('</div>')
    f.write('<table class="overrated">')
    f.write('<tr><th>Rank</th><th>Repository</th><th>Stars</th><th>Overall Quality</th><th>Innovation</th><th>Overrated Score</th><th>Domain</th><th>Motivation</th></tr>')
    
    for idx, (_, row) in enumerate(df.nlargest(20, 'overrated_score').iterrows(), 1):
        row_class = 'llm-flagged-overrated' if row['overrated'] == 1 else ''
        f.write(f'<tr class="{row_class}">')
        f.write(f'<td>{idx}</td>')
        f.write(f'<td><a href="{row["github_url"]}" target="_blank" class="repo-link">{row["repo_name"]}</a></td>')
        f.write(f'<td>{row["star_count"]}</td>')
        f.write(f'<td class="score">{row["overall_quality"]:.2f}</td>')
        f.write(f'<td class="score">{row["innovativeness"]}</td>')
        f.write(f'<td class="score">{row["overrated_score"]:.3f}</td>')
        f.write(f'<td>{row["project_domain"]}</td>')
        f.write(f'<td>{row["motivation"][:100]}{"..." if len(row["motivation"]) > 100 else ""}</td>')
        f.write(f'</tr>')
    
    f.write('</table>')
    
    f.write('</body></html>')

print("Enhanced HTML report saved as 'repository_report.html'")

print(f"\n🎉 Analysis complete! Generated files:")
print("  📋 repository_report.html - Enhanced HTML report with undervalued, best overall, and overrated repositories")
print(f"\nAnalyzed {len(df)} repositories across {df['project_domain'].nunique()} domains")