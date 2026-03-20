---
name: price-check
description: Get current prices for commodities (crude oil, gold, silver, gas), stocks, forex (currency exchange rates), and crypto (bitcoin, ethereum). Use for any question about current market prices, exchange rates, or asset values.
---

# Price Check

Fetch from stooq.com. Use maxChars:300. One web_fetch per symbol.

URL: https://stooq.com/q/l/?s=SYMBOL&f=sd2t2ohlcv&h&e=csv

Response: Symbol,Date,Time,Open,High,Low,Close,Volume — use Close as price.

Symbols:
cl.f=WTI油(USD/桶) cb.f=布伦特油(USD/桶) gc.f=黄金(USD/盎司) ng.f=天然气
si.f=白银 — 特别注意: Close单位是美分/盎司，必须除以100换算为美元 (8134.3÷100=$81.34/oz)
btcusd=比特币(USD) ^spx=标普500 ^ndx=纳斯达克
usdthb=美元/泰铢 usdjpy=美元/日元 usdcny=美元/人民币 eurusd=欧元/美元
stocks: TICKER.us (aapl.us, tsla.us, nvda.us)
