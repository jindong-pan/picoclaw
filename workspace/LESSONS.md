## Web fetch — blocked domains
- query1.finance.yahoo.com
- query2.finance.yahoo.com
- api.coindesk.com
- quote.cnbc.com
- api.investing.com
- www.treasury.gov (JavaScript-rendered, yields not accessible)

## US Treasury Yields
Use FRED public CSV via exec/curl — web_fetch fails with HTTP/2 error on FRED.
Always use exec, never web_fetch for FRED URLs.

Use DGS series (daily data), NOT TB series (monthly):
| Series | Maturity |
|---|---|
| DGS3MO | 3-month |
| DGS1   | 1-year  |
| DGS2   | 2-year  |
| DGS10  | 10-year |

Command:
exec: curl -s "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS1" | tail -1
Returns: YYYY-MM-DD,rate

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


