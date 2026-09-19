#!/usr/bin/env python3
"""
Generate llms.txt and llms-full.txt files for a website using Firecrawl.

This script:
1. Maps all URLs from a website using Firecrawl's /map endpoint
2. Scrapes each URL to get the content
3. Takes title and description from page metadata (or the page body)
4. Creates llms.txt (list of pages with descriptions) and llms-full.txt (full content)
"""

import os
import sys
import time
import argparse
import logging
import re
from typing import Dict, List, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class FirecrawlLLMsTextGenerator:
    """Generate llms.txt files using Firecrawl."""

    def __init__(self, firecrawl_api_key: str):
        """Initialize the generator with the API key."""
        self.firecrawl_api_key = firecrawl_api_key
        self.firecrawl_base_url = "https://api.firecrawl.dev/v1"
        self.headers = {
            "Authorization": f"Bearer {self.firecrawl_api_key}",
            "Content-Type": "application/json"
        }
    
    def map_website(self, url: str, limit: int = 100) -> List[str]:
        """Map a website to get all URLs."""
        logger.info(f"Mapping website: {url} (limit: {limit})")
        
        try:
            response = requests.post(
                f"{self.firecrawl_base_url}/map",
                headers=self.headers,
                json={
                    "url": url,
                    "limit": limit,
                    "includeSubdomains": False,
                    "ignoreSitemap": False
                }
            )
            response.raise_for_status()
            
            data = response.json()
            if data.get("success") and data.get("links"):
                urls = data["links"]
                logger.info(f"Found {len(urls)} URLs")
                return urls
            else:
                logger.error(f"Failed to map website: {data}")
                return []
                
        except Exception as e:
            logger.error(f"Error mapping website: {e}")
            return []
    
    def scrape_url(self, url: str) -> Optional[Dict]:
        """Scrape a single URL."""
        logger.debug(f"Scraping URL: {url}")
        
        try:
            response = requests.post(
                f"{self.firecrawl_base_url}/scrape",
                headers=self.headers,
                json={
                    "url": url,
                    "formats": ["markdown"],
                    "onlyMainContent": True,
                    "timeout": 30000
                }
            )
            response.raise_for_status()
            
            data = response.json()
            if data.get("success") and data.get("data"):
                return {
                    "url": url,
                    "markdown": data["data"].get("markdown", ""),
                    "metadata": data["data"].get("metadata", {})
                }
            else:
                logger.error(f"Failed to scrape {url}: {data}")
                return None
                
        except Exception as e:
            logger.error(f"Error scraping {url}: {e}")
            return None
    
    @staticmethod
    def generate_description(metadata: Dict, markdown: str) -> Tuple[str, str]:
        """Title and description from Firecrawl metadata, falling back to the markdown itself."""
        # ponytail: no LLM; meta description first, else first sentence of the body
        title = (metadata.get("title") or "").split(" | ")[0].strip()  # drop "| Site Name" suffix
        if not title:
            m = re.search(r'^#\s+(.+)$', markdown, re.M)
            title = m.group(1).strip() if m else "Page"

        description = (metadata.get("description") or metadata.get("ogDescription") or "").strip()
        if not description:
            body = re.sub(r'^\s*(#.*|!\[.*|\[.*\]\(.*\)|[-*|>].*)?$', '', markdown, flags=re.M)
            body = re.sub(r'\s+', ' ', body).strip()
            m = re.match(r'(.+?[.!?])(\s|$)', body)
            description = (m.group(1) if m else body[:160]) or "No description available"
        return title, description

    def process_url(self, url: str, index: int) -> Optional[Dict]:
        """Process a single URL: scrape and generate description."""
        scraped_data = self.scrape_url(url)
        if not scraped_data or not scraped_data.get("markdown"):
            return None

        title, description = self.generate_description(
            scraped_data["metadata"],
            scraped_data["markdown"]
        )
        
        return {
            "url": url,
            "title": title,
            "description": description,
            "markdown": scraped_data["markdown"],
            "index": index
        }
    
    def remove_page_separators(self, text: str) -> str:
        """Remove page separators from text."""
        return re.sub(r'<\|firecrawl-page-\d+-lllmstxt\|>\n', '', text)
    
    def limit_pages(self, full_text: str, max_pages: int) -> str:
        """Limit the number of pages in full text."""
        pages = full_text.split('<|firecrawl-page-')
        if len(pages) <= 1:
            return full_text
        
        # First element is the header
        result = pages[0]
        
        # Add up to max_pages
        for i in range(1, min(len(pages), max_pages + 1)):
            result += '<|firecrawl-page-' + pages[i]
        
        return result
    
    def generate_llmstxt(self, url: str, max_urls: int = 100, show_full_text: bool = True) -> Dict[str, str]:
        """Generate llms.txt and llms-full.txt for a website."""
        logger.info(f"Generating llms.txt for {url}")
        
        # Step 1: Map the website
        urls = self.map_website(url, max_urls)
        if not urls:
            raise ValueError("No URLs found for the website")
        
        # Limit URLs to max_urls
        urls = urls[:max_urls]
        
        # Initialize output strings
        llmstxt = f"# {url} llms.txt\n\n"
        llms_fulltxt = f"# {url} llms-full.txt\n\n"
        
        # Process URLs in batches of 10
        batch_size = 10
        all_results = []
        
        for i in range(0, len(urls), batch_size):
            batch = urls[i:i + batch_size]
            logger.info(f"Processing batch {i//batch_size + 1}/{(len(urls) + batch_size - 1)//batch_size}")
            
            # Process batch concurrently
            with ThreadPoolExecutor(max_workers=5) as executor:
                futures = {
                    executor.submit(self.process_url, url, i + j): (url, i + j)
                    for j, url in enumerate(batch)
                }
                
                for future in as_completed(futures):
                    try:
                        result = future.result()
                        if result:
                            all_results.append(result)
                    except Exception as e:
                        url, idx = futures[future]
                        logger.error(f"Failed to process {url}: {e}")
            
            # ponytail: Firecrawl free tier allows ~10 scrapes/min; one batch per minute stays inside it
            if i + batch_size < len(urls):
                time.sleep(60)
        
        # Sort results by index to maintain order
        all_results.sort(key=lambda x: x["index"])
        
        # Build output strings
        for i, result in enumerate(all_results, 1):
            llmstxt += f"- [{result['title']}]({result['url']}): {result['description']}\n"
            llms_fulltxt += f"<|firecrawl-page-{i}-lllmstxt|>\n## {result['title']}\n{result['markdown']}\n\n"
        
        # Optionally remove page separators for clean output
        clean_full_text = self.remove_page_separators(llms_fulltxt) if not show_full_text else llms_fulltxt
        
        return {
            "llmstxt": llmstxt,
            "llms_fulltxt": clean_full_text,
            "num_urls_processed": len(all_results),
            "num_urls_total": len(urls)
        }


def main():
    """Main function to run the script."""
    parser = argparse.ArgumentParser(
        description="Generate llms.txt and llms-full.txt files for a website using Firecrawl"
    )
    parser.add_argument("url", help="The website URL to process")
    parser.add_argument(
        "--max-urls", 
        type=int, 
        default=20, 
        help="Maximum number of URLs to process (default: 20)"
    )
    parser.add_argument(
        "--output-dir", 
        default=".", 
        help="Directory to save output files (default: current directory)"
    )
    parser.add_argument(
        "--firecrawl-api-key",
        default=os.getenv("FIRECRAWL_API_KEY"),
        help="Firecrawl API key (default: from FIRECRAWL_API_KEY env var)"
    )
    parser.add_argument(
        "--no-full-text",
        action="store_true",
        help="Don't generate llms-full.txt file"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )
    
    args = parser.parse_args()
    
    # Set logging level
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Validate API keys
    if not args.firecrawl_api_key:
        logger.error("Firecrawl API key not provided. Set FIRECRAWL_API_KEY environment variable or use --firecrawl-api-key")
        sys.exit(1)

    # Create generator
    generator = FirecrawlLLMsTextGenerator(args.firecrawl_api_key)
    
    try:
        # Generate llms.txt files
        result = generator.generate_llmstxt(
            args.url,
            args.max_urls,
            not args.no_full_text
        )
        
        # Create output directory if it doesn't exist
        os.makedirs(args.output_dir, exist_ok=True)
        
        # Extract domain from URL for filename
        from urllib.parse import urlparse
        domain = urlparse(args.url).netloc.replace("www.", "")
        
        # Save llms.txt
        llmstxt_path = os.path.join(args.output_dir, f"{domain}-llms.txt")
        with open(llmstxt_path, "w", encoding="utf-8") as f:
            f.write(result["llmstxt"])
        logger.info(f"Saved llms.txt to {llmstxt_path}")
        
        # Save llms-full.txt if requested
        if not args.no_full_text:
            llms_fulltxt_path = os.path.join(args.output_dir, f"{domain}-llms-full.txt")
            with open(llms_fulltxt_path, "w", encoding="utf-8") as f:
                f.write(result["llms_fulltxt"])
            logger.info(f"Saved llms-full.txt to {llms_fulltxt_path}")
        
        # Print summary
        print(f"\nSuccess! Processed {result['num_urls_processed']} out of {result['num_urls_total']} URLs")
        print(f"Files saved to {args.output_dir}/")
        
    except Exception as e:
        logger.error(f"Failed to generate llms.txt: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
