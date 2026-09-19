# Firecrawl LLMs.txt Generator

A Python script that generates `llms.txt` and `llms-full.txt` files for any website using the Firecrawl API. No LLM needed: titles and descriptions come from each page's metadata.

## What is llms.txt?

`llms.txt` is a standardized format for making website content more accessible to Large Language Models (LLMs). It provides:

- **llms.txt**: A concise index of all pages with titles and descriptions
- **llms-full.txt**: Complete content of all pages for comprehensive access

## Features

- 🗺️ **Website Mapping**: Automatically discovers all URLs on a website using Firecrawl's map endpoint
- 📄 **Content Scraping**: Extracts markdown content from each page
- 🏷️ **Metadata Summaries**: Titles and descriptions come from page metadata, with the first sentence of the body as fallback
- ⚡ **Parallel Processing**: Processes multiple URLs concurrently for faster generation
- 🎯 **Configurable Limits**: Set maximum number of URLs to process
- 📁 **Flexible Output**: Choose to generate both files or just llms.txt

## Prerequisites

- Python 3.7+
- Firecrawl API key ([Get one here](https://firecrawl.dev))

## Installation

```bash
./install.sh
```

The installer is idempotent and:

1. Installs [uv](https://docs.astral.sh/uv/) if missing, creates `.venv` and installs the dependencies
2. Asks for the Firecrawl API key and writes it to `.env` (skipped if a key is already there)
3. Adds `alias create-llmstxt=...` to `~/.zshrc` pointing at the `create-llmstxt` wrapper

Then `source ~/.zshrc` and `create-llmstxt` works from any directory.

Manual alternative: `uv venv .venv && uv pip install -r requirements.txt`, then `cp .env.example .env` and edit it, or export `FIRECRAWL_API_KEY`, or pass `--firecrawl-api-key`.

## Usage

### Basic Usage

Generate llms.txt and llms-full.txt for a website:

```bash
create-llmstxt https://example.com
# or, without the alias:
python generate-llmstxt.py https://example.com
```

### With Options

```bash
# Limit to 50 URLs
python generate-llmstxt.py https://example.com --max-urls 50

# Save to specific directory
python generate-llmstxt.py https://example.com --output-dir ./output

# Only generate llms.txt (skip full text)
python generate-llmstxt.py https://example.com --no-full-text

# Enable verbose logging
python generate-llmstxt.py https://example.com --verbose

# Specify API key via command line
python generate-llmstxt.py https://example.com --firecrawl-api-key "fc-..."
```

### Command Line Options

- `url` (required): The website URL to process
- `--max-urls`: Maximum number of URLs to process (default: 20)
- `--output-dir`: Directory to save output files (default: current directory)
- `--firecrawl-api-key`: Firecrawl API key (defaults to .env file or FIRECRAWL_API_KEY env var)
- `--no-full-text`: Only generate llms.txt, skip llms-full.txt
- `--verbose`: Enable verbose logging for debugging

## Output Format

### llms.txt

```
# https://example.com llms.txt

- [Page Title](https://example.com/page1): Brief description of the page content here
- [Another Page](https://example.com/page2): Another concise description of page content
```

### llms-full.txt

```
# https://example.com llms-full.txt

<|firecrawl-page-1-lllmstxt|>
## Page Title
Full markdown content of the page...

<|firecrawl-page-2-lllmstxt|>
## Another Page
Full markdown content of another page...
```

## How It Works

1. **Website Mapping**: Uses Firecrawl's `/map` endpoint to discover all URLs on the website
2. **Batch Processing**: Processes URLs in batches of 10 for efficiency
3. **Content Extraction**: Scrapes each URL to extract markdown content
4. **Summaries**: For each page, the title comes from the `<title>` tag (site-name suffix stripped) and the description from the meta description, falling back to the first sentence of the content
5. **File Generation**: Creates formatted llms.txt and llms-full.txt files

## Error Handling

- Failed URL scrapes are logged and skipped
- If no URLs are found, the script exits with an error
- API errors are logged with details for debugging
- Rate limiting is handled with a 60-second delay between batches (fits Firecrawl's free tier)

## Performance Considerations

- Processing time depends on the number of URLs and response times
- Default batch size is 10 URLs processed concurrently
- A 60-second delay between batches of 10 keeps the Firecrawl free tier within its scrape quota
- For large websites, consider using `--max-urls` to limit processing

## Examples

### Small Website

```bash
python generate-llmstxt.py https://small-blog.com --max-urls 20
```

### Large Website with Limited Scope

```bash
python generate-llmstxt.py https://docs.example.com --max-urls 100 --verbose
```

### Quick Index Only

```bash
python generate-llmstxt.py https://example.com --no-full-text --max-urls 50
```

## Configuration Priority

The script checks for the API key in this order:

1. Command line argument (`--firecrawl-api-key`)
2. `.env` file in the current directory
3. Environment variable (`FIRECRAWL_API_KEY`)

## Troubleshooting

### No API Key Found

Ensure you've either:

- Created a `.env` file with your API key (copy from `.env.example`)
- Set the environment variable `FIRECRAWL_API_KEY`
- Or pass it via command line argument

### Rate Limiting

If you encounter rate limits:

- Reduce concurrent workers in the code
- Add longer delays between batches
- Process fewer URLs at once

### Memory Issues

For very large websites:

- Use `--max-urls` to limit the number of pages
- Process in smaller batches
- Use `--no-full-text` to skip full content generation

## License

MIT License. Forked from [firecrawl/create-llmstxt-py](https://github.com/firecrawl/create-llmstxt-py).
