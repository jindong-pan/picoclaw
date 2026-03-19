- oil price queries: Sites like oilprice.com/oil-price-charts and investing.com return paywalled or JS-rendered pages with no price data. Use wttr.in style approach — fetch https://query1.finance.yahoo.com/v8/finance/chart/CL=F?interval=1d&range=1d for WTI crude price directly as JSON.

- oil price repeat: If Yahoo Finance CL=F returns truncated JSON (200 chars not enough), retry with maxChars=1000 — the price data is deeper in the JSON response.

## Web fetch — blocked domains
These domains are blocked and will always fail. Never attempt them:
- query1.finance.yahoo.com
- query2.finance.yahoo.com  
- api.coindesk.com

## Price data — preferred sources (use directly, skip trial and error)

| Asset | URL |
|---|---|
| Crypto (ETH, BTC etc) | https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd |
| Gold futures | https://stooq.com/q/l/?s=gc.f&f=sd2t2ohlcv&h&e=csv |
| Silver futures | https://stooq.com/q/l/?s=si.f&f=sd2t2ohlcv&h&e=csv |
| Oil (WTI) | https://stooq.com/q/l/?s=cl.f&f=sd2t2ohlcv&h&e=csv |
| Weather | https://wttr.in/CITY?format=3 |

## Stooq unit warning
Silver (SI.F) and gold (GC.F) prices from Stooq are in **cents per ounce**.
Always divide by 100 to get USD/oz before reporting to the user.

## Weather queries
Always use https://wttr.in/CITY?format=3 directly — one fetch, one answer.
Do not use multi-step weather APIs.

## Response language
Always respond in the same language the user wrote in.
If user writes in 繁體中文, respond in 繁體中文.
If user writes in 简体中文, respond in 简体中文.
