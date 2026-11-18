# Design notes

Why CandleBase is built the way it is. This document exists because the design decisions are the interesting part — the pattern definitions themselves are textbook.

---

## The four failure modes

Naive candlestick detectors fail in four specific, mechanical ways. Each one has a fix, and each fix constrains the rest of the design.

### 1. Division blow-up

The classic hammer definition is `lowerWick / body >= 2`. A doji has a body approaching zero, so that ratio approaches infinity, and **every doji is classified as a hammer**. On a liquid intraday chart this alone can account for the majority of false detections.

**Fix:** no division anywhere in the detection path. `lowerWick >= 2 * body` is algebraically equivalent for positive values and numerically safe for a body of zero. The primary gates are expressed as fractions of the bar's own range, which cannot go to zero on a tradeable bar.

This constraint is the reason several things below look more awkward than they need to.

### 2. Scale blindness

A 4-pip hammer during a dead Asian session is noise. The identical shape at the London open may be meaningful. A detector using fixed point thresholds cannot distinguish them, so it either floods you with noise or misses real signals, depending on where you set the number.

**Fix:** every significance threshold is expressed as a multiple of a volatility reference derived from recent true range. The same configuration then works across sessions and across instruments without retuning.

### 3. Strict-equality starvation

Textbook bullish engulfing requires `open < previous close`. On a continuous feed, `open == previous close` constantly — the next bar opens exactly where the last one closed. Taken literally, the definition rejects most genuine engulfing patterns.

**Fix:** a single signed **edge tolerance** per two-bar pattern, scaled to volatility. Positive values permit the body to fall slightly short of the reference edge; negative values demand strict overshoot. One knob, one direction of meaning.

### 4. Meaningless reference candles

"Engulfing" a 2-cent doji body is trivially satisfied and carries no information. The same applies to a harami whose outer candle is itself tiny — anything fits inside nothing.

**Fix:** a minimum body size for the *reference* candle, in volatility units, on both engulfing and harami.

---

## The volatility reference

`volRef` is the median (default) or mean of the last *N* true ranges.

### Why not ATR

Pine's `ta.atr()` uses Wilder's RMA smoothing. MetaTrader 5's built-in ATR uses different smoothing, and recursive smoothing carries a seeding difference that never fully decays. That difference sits silently underneath every threshold in the system, so the two platforms would drift apart permanently and invisibly.

A non-recursive aggregate has no recursion to seed, no indicator handle to go stale, and is reproducible by hand. The cost is that it responds slightly differently to volatility shifts than an exponentially-weighted measure. That trade is worth it: a detector whose thresholds differ between platforms is not a detector, it's two detectors.

### Why median by default

A single weekend gap inflates a mean true range for the whole window, suppressing every valid detection during that period. The median absorbs it. Mean is available for anyone who wants it, but the default should not quietly break every Monday morning.

### Why the window excludes the pattern bar

A large engulfing bar included in its own volatility window raises the threshold it must clear — it would veto itself. Single-bar patterns therefore measure the *N* bars before the pattern bar; two-bar patterns measure the *N* bars before the outer bar.

---

## The harami rule

Containment is measured **body against body only**. The inner candle's wicks may break above the outer candle's high, below its low, or both, and the pattern still qualifies. `high` and `low` are never referenced in the containment test.

Most implementations test the full range, rejecting any inner candle whose wick pokes outside. We think that's wrong. A harami is a statement about where *conviction* collapsed — the body is where the market actually transacted and settled. A wick that probes outside the prior range and gets rejected is consistent with the pattern's meaning, not a contradiction of it.

This is a deliberate departure from the common implementation. If you disagree, the behaviour is a configuration away — `harChildRngCap` constrains the inner candle's range relative to the outer, and is off by default.

A second constraint: the inner body must be meaningfully smaller than the outer (default: ≤ 70%). A harami whose inner candle is 99% of the outer carries no information, and a detector that reports it is reporting noise.

---

## Cross-platform parity

The same bar must produce the same detection in Pine Script and MQL5 (a Python implementation is planned). Everything below exists to make that true.

| Hazard | Handling |
|---|---|
| **Indexing direction** | MQL5 arrays are forced chronological (`ArraySetAsSeries(arr, false)`), so Pine's `[1]` maps exactly to MQL5's `idx-1`. Series indexing inverts the direction and invites off-by-one errors that only appear on specific bars |
| **Indicator seeding** | Avoided entirely — no indicator handles, no recursion, no warm-up state to diverge |
| **Integer division** | Pine v6 returns fractional values even for integer constants; the median index is explicitly cast to match C++ truncation |
| **Lazy boolean evaluation** | Pine short-circuits `and`/`or`, so a stateful call inside a condition chain would be skipped on some bars and silently corrupt its own history. All stateful computation is hoisted to global scope |
| **Digits and point size** | Never used in detection. Every threshold is a ratio or a multiple of `volRef`, making the engine broker- and instrument-agnostic by construction |
| **Bar timing** | All three evaluate the last closed bar only. Non-repainting |

### Verifying parity yourself

Run the MQL5 scanner with CSV logging enabled and export the Pine detections from the Data Window over the same bars, then diff the two signal lists. Parity is validated at **signal level** — timestamped detections, compared one by one. Comparing charts by eye will not find the bars where the two disagree, and those bars are exactly the ones that matter.

Note that TradingView and your broker's MT5 feed produce **different candles** — different OHLC, different session boundaries, different server time. Comparing Pine against MQL5 across those two feeds measures feed differences, not implementation differences. To check the implementations, run both over the same bars.

---

## What this library deliberately does not do

**No trend context.** A Hammer and a Hanging Man are geometrically identical; so are an Inverted Hammer and a Shooting Star. Only prior trend separates them. CandleBase returns the shape and leaves the meaning to the caller, because context belongs to the strategy.

This matters more than it sounds. **The largest single source of what traders call "false hammers" is missing context, not loose geometry.** No parameter set fixes that. If your strategy needs a hammer to mean something, the trend filter is yours to write.

**No claim of profitability.** These patterns are widely published and widely tested, and the literature on their standalone predictive power in liquid markets is not encouraging. This library makes detection precise and reproducible. Whether precise detection of these shapes is *useful* is an empirical question about your market, your timeframe and your costs — and it is a question this library helps you answer honestly rather than one it answers for you.
