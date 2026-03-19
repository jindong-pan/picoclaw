## News Fetching

Always use `agent-browser` instead of `web_fetch` for news requests.
Use RSS feeds as the first and preferred source — never start with homepages.

### RSS Sources
- 日本新闻 (Japanese): https://www3.nhk.or.jp/rss/news/cat0.xml
- BBC 中文 (Traditional): https://feeds.bbci.co.uk/zhongwen/trad/rss.xml
- BBC 中文 (Simplified): https://feeds.bbci.co.uk/zhongwen/simp/rss.xml
- Reuters (English): https://feeds.reuters.com/reuters/topNews

### Rules
1. Fetch the RSS feed directly with `agent-browser get text "body"`
2. If the result is under 500 characters, do not try another source —
   increase content retrieval before moving on
3. Do not attempt more than 2 sources before synthesizing a response
