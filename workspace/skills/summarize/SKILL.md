---
name: summarize
description: Summarize URLs, articles, and YouTube videos. Use when user shares a link and wants a summary, asks "what is this about", or wants a YouTube video summarized.
---

# Summarize

Use exec tool with this exact command:

/home/rose_oasis_tw/.picoclaw/workspace/summarize.sh "URL" --length short --plain

## Length
short = 1-2 paragraphs (default)
medium = 3-5 paragraphs
long = full summary

## Examples
/home/rose_oasis_tw/.picoclaw/workspace/summarize.sh "https://example.com" --length short --plain
/home/rose_oasis_tw/.picoclaw/workspace/summarize.sh "https://youtube.com/watch?v=..." --length short --plain

Do not use for price data or weather.
