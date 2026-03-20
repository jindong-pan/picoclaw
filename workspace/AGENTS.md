## Tool Selection
- Default to web_fetch for all fetching tasks
- Switch to agent-browser only when:
  - web_fetch returns under 500 chars from a content-rich page
  - Task requires clicking, filling forms, or screenshots
  - Site requires JavaScript rendering

## News Fetching
Always fetch RSS feeds directly — never start with homepages.
Use maxChars=5000 minimum on the first fetch.

### RSS Sources
- 日本新闻 (Japanese): https://www3.nhk.or.jp/rss/news/cat0.xml
- BBC 中文 (Traditional): https://feeds.bbci.co.uk/zhongwen/trad/rss.xml
- BBC 中文 (Simplified): https://feeds.bbci.co.uk/zhongwen/simp/rss.xml
- Reuters (English): https://feeds.reuters.com/reuters/topNews

### Rules
1. Fetch the RSS feed with web_fetch, maxChars=5000 minimum
   Use agent-browser only if web_fetch returns under 500 chars
2. If the result is under 500 characters, do not try another source —
   increase content retrieval before moving on
3. Do not attempt more than 2 sources before synthesizing a response
