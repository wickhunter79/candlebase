# CandleBase

**Candlestick pattern detection that doesn't fire on noise — with identical results in Pine Script and MQL5.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Platforms](https://img.shields.io/badge/platforms-Pine%20v6%20%7C%20MQL5-lightgrey)

---

Most published candlestick detectors fire constantly on noise. Four reasons, and all four are fixable:

- A doji's near-zero body makes `wick / body` explode toward infinity, so **every doji becomes a hammer**.
- Fixed point thresholds treat a 4-pip hammer at 03:00 the same as one at the London open.
- Strict inequalities (`open < previous close`) starve on a continuous feed, where `open ≈ previous close` constantly — so the real signals get rejected.
- "Engulfing" a 2-cent doji body is trivially satisfied and means nothing.

CandleBase handles each of these explicitly, and [documents why](docs/DESIGN.md).

## What's different

**No division anywhere in the detection path.** Every ratio test is written as a multiplication — `lowerWick >= 2 * body` rather than `lowerWick / body >= 2`. A near-zero body can't produce an infinite ratio, so dojis stop masquerading as hammers.

**Thresholds scale with volatility.** Significance is measured against a non-recursive median of recent true range, not fixed points. The same settings work in a dead Asian session and at the London open, with no retuning.

**Verified identical across platforms.** The same bar produces the same detection in Pine Script and MQL5. Shipping one implementation is easy; keeping two in agreement is the hard part, and most of the design decisions here exist to make it possible. See [Parity](docs/DESIGN.md#cross-platform-parity).

## Patterns

| Single bar | Two bar |
|---|---|
| Hammer | Bullish / Bearish Engulfing |
| Inverted Hammer | Bullish / Bearish Harami |

These are returned as **shapes, not signals**. A Hammer and a Hanging Man are geometrically identical — only prior trend separates them, and trend context is the strategy's job, not the detector's. CandleBase tells you what the bar looks like and leaves what it means to you.

## Quick start

### Pine Script (TradingView)

Copy `pine/candle_base.pine` into the Pine Editor and add to chart. Detections plot as markers; every intermediate value is exported to the Data Window for verification.

### MQL5 (MetaTrader 5)

```
MQL5/Include/CandleBase.mqh           <- the engine
MQL5/Indicators/CandleBaseScanner.mq5 <- visual scanner + CSV logger
```

```cpp
#include <CandleBase.mqh>

CCandleBase        engine;
CandleBaseSettings s;  s.SetDefaults();
engine.Settings(s);

string err;
if(!engine.Init(_Symbol, PERIOD_CURRENT, err))
   { Print("Init failed: ", err); return INIT_FAILED; }

CandleBaseResult r;
if(engine.Detect(1, r) && r.Any())   // shift 1 = last closed bar
   Print(r.Names());
```

The scanner writes a timestamped CSV of every detection, which is what makes parity checking possible — see [Parity](docs/DESIGN.md#cross-platform-parity).

## Detection rules

Full numbered rules in [docs/SPEC.md](docs/SPEC.md). In brief:

**Volatility reference** — median (default) or mean of the last *N* true ranges. Non-recursive, so there's no seeding difference between platforms. The window **excludes the pattern bar itself**, so a large bar can't inflate its own yardstick and veto its own detection.

**Hammer** — lower wick ≥ 55% of range, body ≤ 35% of range, upper wick ≤ 15% of range, and lower wick ≥ 2× body. Inverted Hammer mirrors it.

**Engulfing** — body engulfs body; wicks are not consulted. The engulfed body must itself be meaningful (≥ 0.15 × volRef), and the engulfing body must dominate (≥ 1.2×), so a one-tick engulf of a doji doesn't qualify.

**Harami** — containment is measured **body against body only**. The inner candle's wicks may break the outer candle's high, its low, or both, and it still counts. `high` and `low` are never referenced in the containment test. This is stricter than the common implementation and, we'd argue, more correct — [reasoning here](docs/DESIGN.md#the-harami-rule).

## Configuration

Every threshold is exposed and documented. Defaults are a starting point tuned for XAUUSD, not a recommendation — [SPEC.md](docs/SPEC.md) explains what each one does so you can reason about changes rather than guess.

## What this library does not do

- No trend context, no trade signals, no entries or exits
- No opinion on what a pattern means
- No claim that these patterns are profitable

It is a detector. What you build on top is yours.

## Roadmap

- **Python implementation** with a test suite, so the detection rules can be verified
  against fixtures rather than taken on trust — tracked in [#1](../../issues/1)
- Parity-checking utility that diffs signal logs between platforms

## Contributing

Issues and pull requests welcome. If you find a bar where the two implementations disagree, that's the most valuable bug report possible — please include the OHLC values and the settings used.

## License

MIT — see [LICENSE](LICENSE).

Built by Aradhya Vikram · [AURAXIS](https://auraxis.com)
