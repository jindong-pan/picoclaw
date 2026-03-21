## Web fetch — blocked domains
- query1.finance.yahoo.com
- query2.finance.yahoo.com
- api.coindesk.com
- quote.cnbc.com
- api.investing.com

## Price data — preferred sources (use directly, skip trial and error)

| Asset | URL |
|---|---|
| Crypto (ETH, BTC etc) | https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd |
| Gold futures | https://stooq.com/q/l/?s=gc.f&f=sd2t2ohlcv&h&e=csv |
| Silver futures | https://stooq.com/q/l/?s=si.f&f=sd2t2ohlcv&h&e=csv |
| Oil (WTI) | https://stooq.com/q/l/?s=cl.f&f=sd2t2ohlcv&h&e=csv |

## Stooq unit warning
Silver (SI.F) and gold (GC.F) prices from Stooq are in **cents per ounce**.
Always divide by 100 to get USD/oz before reporting to the user.

## Weather
Always use https://wttr.in/CITY?format=j1 for weather queries.
Never fetch plain wttr.in/CITY without a format parameter.

## Response language
Always respond in the same language the user wrote in.
If user writes in 繁體中文, respond in 繁體中文.
If user writes in 简体中文, respond in 简体中文.

## Retry smartly
When repeated tool calls return near-identical, minimal results, the agent should recognize it has hit a hard external barrier and respond to the user honestly — rather than exhausting its iteration budget on variations of a failing strategy. Early failure detection is more valuable than more iterations or better tools.

## News
Use RSS feeds for all news requests — never fetch homepages.
See AGENTS.md for RSS sources and rules.
web_fetch with maxChars=5000 is sufficient for RSS feeds.

## US Treasury Yield
Use FRED public CSV — no API key needed:
US 10-Year Treasury Yield: https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS10
Fetch with maxChars=500, the last line contains the most recent yield.
Format: observation_date,DGS10
Do NOT use: Treasury.gov, CNBC, Yahoo Finance, Bloomberg, Investing.com — all blocked.
