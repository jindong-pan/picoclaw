---
name: weather
description: Provides real-time weather information, including current conditions, five-day forecasts, and severe weather alerts for global locations. **Use when** the user asks about the temperature, needs to know if it will rain, or requires a clothing recommendation based on the local climate.
---
# Weather

Use web_fetch to get weather from wttr.in. No API key needed.

## Quick current weather
web_fetch: `https://wttr.in/CITY?format=3`
Example: `https://wttr.in/Hong+Kong?format=3`
Output: `Hong Kong: ⛅️ +19°C`

## Detailed current weather
web_fetch: `https://wttr.in/CITY?format=%l:+%c+%t+%h+%w`
Output: `Hong Kong: ⛅️ +19°C 73% ↙11km/h`

## Tips
- URL-encode spaces: `New+York`
- Airport codes: `JFK`  
- Units: `?m` metric, `?u` USCS
- maxChars: 200 is sufficient
