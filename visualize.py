# /// script
# dependencies = [
#   "matplotlib",
#   "pandas",
#   "plotly",
#   "seaborn",
# ]
# ///

# Enhanced Python script for repository visualization with identifiers
import json
import matplotlib.pyplot as plt
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import seaborn as sns
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
df['short_name'] = df['repo_name'].apply(lambda x: x.split('/')[-1][:20])  # Last part, truncated

# Create composite scores for better analysis
df['overall_quality'] = (df['code_quality'] + df['innovativeness'] + 
                        df['usefulness'] + df['user_friendliness']) / 4

df['value_score'] = df['overall_quality'] / np.log10(df['star_count'] + 10)  # Higher is more undervalued
df['popularity_ratio'] = df['star_count'] / (df['overall_quality'] ** 2)

# Create color mapping
def get_color_category(row):
    if row['underrated'] == 1:
        return 'Underrated'
    elif row['overrated'] == 1:
        return 'Overrated'
    else:
        return 'Normal'

df['category'] = df.apply(get_color_category, axis=1)

# 1. INTERACTIVE PLOTLY SCATTER PLOT
print("Creating interactive scatter plot...")
fig1 = px.scatter(
    df, 
    x='star_count', 
    y='code_quality',
    color='category',
    size='overall_quality',
    hover_data={
        'repo_name': True,
        'star_count': True,
        'code_quality': True,
        'innovativeness': True,
        'usefulness': True,
        'user_friendliness': True,
        'project_domain': True,
        'github_url': True
    },
    title='Repository Quality vs Popularity (Interactive)',
    labels={
        'star_count': 'Star Count',
        'code_quality': 'Code Quality Score'
    },
    color_discrete_map={
        'Underrated': 'red',
        'Overrated': 'blue', 
        'Normal': 'gray'
    }
)

fig1.update_layout(
    xaxis_type="log",
    width=1200,
    height=800,
    title_font_size=16
)

fig1.write_html("interactive_quality_vs_popularity.html")
print("Interactive plot saved as 'interactive_quality_vs_popularity.html'")

colors = {'Underrated': 'red', 'Overrated': 'blue', 'Normal': 'lightgray'}

# 2. MULTI-DIMENSIONAL ANALYSIS DASHBOARD
print("Creating multi-dimensional dashboard...")
fig = make_subplots(
    rows=2, cols=2,
    subplot_titles=(
        'Quality vs Popularity', 
        'Innovation vs Usefulness',
        'Value Score Distribution',
        'Domain Analysis'
    ),
    specs=[[{"secondary_y": False}, {"secondary_y": False}],
           [{"secondary_y": False}, {"secondary_y": False}]]
)

# Plot 1: Quality vs Popularity
for category in df['category'].unique():
    mask = df['category'] == category
    fig.add_trace(
        go.Scatter(
            x=df[mask]['star_count'],
            y=df[mask]['code_quality'],
            mode='markers',
            name=category,
            text=df[mask]['repo_name'],
            hovertemplate='<b>%{text}</b><br>Stars: %{x}<br>Quality: %{y}<extra></extra>',
            marker=dict(
                color=colors[category],
                size=df[mask]['overall_quality'] * 3,
                opacity=0.7
            )
        ),
        row=1, col=1
    )

# Plot 2: Innovation vs Usefulness
fig.add_trace(
    go.Scatter(
        x=df['innovativeness'],
        y=df['usefulness'],
        mode='markers',
        text=df['repo_name'],
        hovertemplate='<b>%{text}</b><br>Innovation: %{x}<br>Usefulness: %{y}<extra></extra>',
        marker=dict(
            color=df['star_count'],
            colorscale='Viridis',
            size=8,
            colorbar=dict(title="Star Count")
        ),
        showlegend=False
    ),
    row=1, col=2
)

# Plot 3: Value Score Distribution
fig.add_trace(
    go.Histogram(
        x=df['value_score'],
        nbinsx=30,
        name='Value Score',
        showlegend=False
    ),
    row=2, col=1
)

# Plot 4: Domain Analysis (top domains)
domain_counts = df['project_domain'].value_counts().head(10)
fig.add_trace(
    go.Bar(
        x=domain_counts.values,
        y=domain_counts.index,
        orientation='h',
        name='Domain Count',
        showlegend=False
    ),
    row=2, col=2
)

fig.update_xaxes(type="log", row=1, col=1)
fig.update_layout(height=800, title_text="Repository Analysis Dashboard")
fig.write_html("repository_dashboard.html")
print("Dashboard saved as 'repository_dashboard.html'")

# 3. GENERATE SUMMARY REPORTS
print("\nGenerating summary reports...")

# Top undervalued repositories
print("\n=== TOP 10 UNDERVALUED REPOSITORIES ===")
top_undervalued = df.nlargest(10, 'value_score')[['repo_name', 'star_count', 'overall_quality', 'value_score', 'project_domain']]
print(top_undervalued.to_string(index=False))

# Flagged underrated repositories
print(f"\n=== LLM-FLAGGED UNDERRATED REPOSITORIES ({df['underrated'].sum()} total) ===")
underrated_repos = df[df['underrated'] == 1][['repo_name', 'star_count', 'code_quality', 'motivation']].head(10)
print(underrated_repos.to_string(index=False))

# High star, questionable quality
print(f"\n=== POTENTIALLY OVERRATED REPOSITORIES ===")
potentially_overrated = df[
    (df['star_count'] > df['star_count'].quantile(0.8)) & 
    (df['overall_quality'] < df['overall_quality'].quantile(0.4))
][['repo_name', 'star_count', 'overall_quality', 'project_domain']].head(10)
print(potentially_overrated.to_string(index=False))

# 4. EXPORT DETAILED DATA
print("\nExporting detailed analysis...")
analysis_df = df[[
    'repo_name', 'github_url', 'star_count', 'code_quality', 'innovativeness', 
    'usefulness', 'user_friendliness', 'overall_quality', 'value_score', 
    'category', 'project_domain', 'motivation'
]].copy()

analysis_df = analysis_df.sort_values('value_score', ascending=False)
analysis_df.to_csv('repository_analysis.csv', index=False)
print("Detailed analysis exported to 'repository_analysis.csv'")

# 6. CREATE CLICKABLE URL LIST FOR TOP REPOS
print("\nCreating clickable repository lists...")
with open('top_undervalued_repos.html', 'w') as f:
    f.write('<html><head><title>Top Undervalued Repositories</title></head><body>')
    f.write('<h1>Top 20 Undervalued Repositories</h1>')
    f.write('<table border="1" style="border-collapse: collapse;">')
    f.write('<tr><th>Rank</th><th>Repository</th><th>Stars</th><th>Quality Score</th><th>Value Score</th><th>Domain</th></tr>')
    
    for idx, (_, row) in enumerate(df.nlargest(20, 'value_score').iterrows(), 1):
        f.write(f'<tr>')
        f.write(f'<td>{idx}</td>')
        f.write(f'<td><a href="{row["github_url"]}" target="_blank">{row["repo_name"]}</a></td>')
        f.write(f'<td>{row["star_count"]}</td>')
        f.write(f'<td>{row["overall_quality"]:.2f}</td>')
        f.write(f'<td>{row["value_score"]:.3f}</td>')
        f.write(f'<td>{row["project_domain"]}</td>')
        f.write(f'</tr>')
    
    f.write('</table></body></html>')

print("Clickable list saved as 'top_undervalued_repos.html'")

print(f"\n🎉 Analysis complete! Generated files:")
print("  📊 interactive_quality_vs_popularity.html - Interactive scatter plot")
print("  📈 annotated_quality_vs_popularity.png - Static plot with annotations")
print("  📋 repository_dashboard.html - Multi-dimensional dashboard")
print("  📄 repository_analysis.csv - Detailed data export")
print("  🔗 top_undervalued_repos.html - Clickable repository list")
print(f"\nAnalyzed {len(df)} repositories across {df['project_domain'].nunique()} domains")