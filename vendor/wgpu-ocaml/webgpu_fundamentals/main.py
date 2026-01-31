#!/usr/bin/env python3
"""
Scraper for WebGPU Fundamentals lesson pages.

Fetches a lesson page, extracts all iframe examples, and saves
the JavaScript module scripts to organized directories.
"""

import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urljoin, urlparse

import requests
from bs4 import BeautifulSoup


def fetch_page(url: str) -> str:
    """Fetch a URL and return the HTML content."""
    response = requests.get(url)
    response.raise_for_status()
    return response.text


def extract_iframes(html: str) -> list[str]:
    """Extract all iframe src attributes from HTML."""
    soup = BeautifulSoup(html, "lxml")
    iframes = soup.find_all("iframe")
    return [iframe.get("src") for iframe in iframes if iframe.get("src")]


def extract_url_param(iframe_src: str) -> str | None:
    """Extract the 'url' query parameter from an iframe src."""
    parsed = urlparse(iframe_src)
    params = parse_qs(parsed.query)
    url_list = params.get("url", [])
    if url_list:
        return unquote(url_list[0])
    return None


def build_destination_url(base_url: str, relative_path: str) -> str:
    """Build the full destination URL from base URL and relative path."""
    # Get the base (scheme + netloc)
    parsed = urlparse(base_url)
    base = f"{parsed.scheme}://{parsed.netloc}"
    # Join with the relative path
    return urljoin(base, relative_path)


def extract_module_script(html: str) -> str | None:
    """Extract the content of <script type='module'> from HTML."""
    soup = BeautifulSoup(html, "lxml")
    script = soup.find("script", {"type": "module"})
    if script:
        return script.string
    return None


def extract_lesson_content(html: str) -> str | None:
    """Extract text content from .lesson-main, excluding .modifiedlines elements.

    Preserves whitespace in <pre> elements, and breaks on block-level elements.
    """
    soup = BeautifulSoup(html, "lxml")
    lesson_main = soup.find(class_="lesson-main")
    if not lesson_main:
        return None

    # Remove all .modifiedlines elements
    for modified in lesson_main.find_all(class_="modifiedlines"):
        modified.decompose()

    # Block-level elements that should cause paragraph breaks
    block_tags = {
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "blockquote", "hr", "table", "tr",
        "section", "article", "header", "footer", "nav",
        "pre", "figure", "figcaption",
    }

    def extract_text(element) -> list[str]:
        """Recursively extract text, handling block elements and <pre> specially."""
        parts = []

        for child in element.children:
            if isinstance(child, str):
                # NavigableString - just text
                text = child
                # Collapse whitespace for non-pre content
                text = re.sub(r"\s+", " ", text)
                if text:
                    parts.append(text)
            elif child.name == "pre":
                # Preserve whitespace in <pre> blocks
                pre_text = child.get_text()
                parts.append("\n\n```\n" + pre_text + "\n```\n\n")
            elif child.name in block_tags:
                # Block element - add paragraph break before and after
                inner = extract_text(child)
                inner_text = "".join(inner).strip()
                if inner_text:
                    parts.append("\n\n" + inner_text + "\n\n")
            elif child.name:
                # Inline element - just get its content
                inner = extract_text(child)
                parts.extend(inner)

        return parts

    parts = extract_text(lesson_main)
    text = "".join(parts)

    # Clean up whitespace-only lines and excessive newlines
    text = re.sub(r"\n[ \t]+\n", "\n\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def get_lesson_name(url: str) -> str:
    """Extract lesson name from URL like webgpu-multisampling.html -> multisampling."""
    parsed = urlparse(url)
    filename = Path(parsed.path).stem  # e.g., "webgpu-multisampling"
    # Remove "webgpu-" prefix if present
    if filename.startswith("webgpu-"):
        filename = filename[7:]
    return filename


def get_example_name(relative_path: str) -> str:
    """Extract example name from relative path."""
    # e.g., "/webgpu/lessons/../webgpu-multisample-centroid.html" -> "multisample-centroid"
    filename = Path(relative_path).stem
    # Remove "webgpu-" prefix if present
    if filename.startswith("webgpu-"):
        filename = filename[7:]
    return filename


def scrape_lesson(lesson_url: str, output_dir: Path) -> None:
    """
    Scrape a WebGPU Fundamentals lesson page and save all example scripts.

    Args:
        lesson_url: URL to a webgpufundamentals.org lesson page
        output_dir: Base directory for output (e.g., ./webgpu_fundamentals)
    """
    print(f"Fetching lesson page: {lesson_url}")
    html = fetch_page(lesson_url)

    lesson_name = get_lesson_name(lesson_url)
    lesson_dir = output_dir / lesson_name
    lesson_dir.mkdir(parents=True, exist_ok=True)

    print(f"Lesson name: {lesson_name}")

    # Extract and save lesson content
    lesson_content = extract_lesson_content(html)
    if lesson_content:
        lesson_file = lesson_dir / "lesson.txt"
        lesson_file.write_text(lesson_content + "\n")
        print(f"Saved lesson content: {lesson_file}")
    else:
        print("Warning: No .lesson-main content found")

    iframes = extract_iframes(html)
    print(f"Found {len(iframes)} iframe(s)")

    for iframe_src in iframes:
        relative_path = extract_url_param(iframe_src)
        if not relative_path:
            print(f"  Skipping iframe without url param: {iframe_src}")
            continue

        destination_url = build_destination_url(lesson_url, relative_path)
        example_name = get_example_name(relative_path)

        print(f"  Fetching example: {example_name}")
        print(f"    URL: {destination_url}")

        try:
            example_html = fetch_page(destination_url)
            script_content = extract_module_script(example_html)

            if script_content:
                output_file = lesson_dir / f"{example_name}.js"
                output_file.write_text(script_content.strip() + "\n")
                print(f"    Saved: {output_file}")
            else:
                print(f"    Warning: No <script type='module'> found")
        except requests.RequestException as e:
            print(f"    Error fetching {destination_url}: {e}")


def main():
    if len(sys.argv) < 2:
        print("Usage: uv run main.py <lesson_url>")
        print("Example: uv run main.py https://webgpufundamentals.org/webgpu/lessons/webgpu-multisampling.html")
        sys.exit(1)

    lesson_url = sys.argv[1]

    # Output directory is the same directory as this script
    script_dir = Path(__file__).parent

    scrape_lesson(lesson_url, script_dir)
    print("Done!")


if __name__ == "__main__":
    main()
