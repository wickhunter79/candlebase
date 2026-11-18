# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-18

First public release.

### Added
- Pine Script v6 implementation with chart plots and Data Window exports
- MQL5 implementation: `CandleBase.mqh` engine plus `CandleBaseScanner.mq5`
  visual scanner with CSV signal logging
- Six patterns: Hammer, Inverted Hammer, Bullish/Bearish Engulfing,
  Bullish/Bearish Harami
- Non-recursive volatility reference (median or mean of true range) with the
  pattern bar excluded from its own window
- Division-free detection path throughout
- Signed edge tolerances on engulfing and harami
- Full design rationale in `docs/DESIGN.md`

### Known gaps
- Python implementation not yet included — tracked in #1
