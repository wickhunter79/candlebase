//+------------------------------------------------------------------+
//|                                                   CandleBase.mqh |
//|   CANDLE_BASE v1.0 — Candlestick pattern detection engine        |
//|   Patterns: Hammer, Inverted Hammer, Bull/Bear Engulfing,        |
//|             Bull/Bear Harami                                      |
//|                                                                   |
//|   This is a BASE MODULE. It contains no trade logic, no trend     |
//|   context, no session filter, no magic number. Strategies layer   |
//|   those on top and remain fully independent of each other.        |
//+------------------------------------------------------------------+
//  PARITY CONTRACT WITH CANDLE_BASE.pine — do not break these:
//   P1. INDEXING IS CHRONOLOGICAL. idx = bar under test, idx-1 = mother bar.
//       Every array passed in MUST be ArraySetAsSeries(arr, false).
//       Pine's [1] == MQL5 idx-1. This is why series indexing is deliberately
//       NOT used here: it inverts the direction and invites off-by-one parity bugs.
//   P2. NO INDICATOR HANDLES. The volatility reference is computed inline with the
//       same non-recursive formula as Pine. iATR() is intentionally avoided: its
//       smoothing differs from Pine's ta.atr(), and a recursive seed difference
//       never fully decays — it would silently shift every threshold forever.
//   P3. NO DIVISION in the detection path. Every ratio test is a multiplication,
//       so a zero/near-zero body cannot produce an infinite ratio.
//   P4. Harami containment reads bodyTop/bodyBot only — never high/low.
//   P5. Only CLOSED bars are evaluated. The caller must not pass the forming bar.
//+------------------------------------------------------------------+
#ifndef __CANDLE_BASE_MQH__
#define __CANDLE_BASE_MQH__

#define CANDLE_BASE_VERSION "1.0"

//--- Body-colour filter for single-bar patterns
enum ENUM_CB_COLOUR
  {
   CB_COL_ANY  = 0,   // Any
   CB_COL_BULL = 1,   // Bullish body only
   CB_COL_BEAR = 2    // Bearish body only
  };

//--- True-range aggregation method
enum ENUM_CB_VOLAGG
  {
   CB_VOL_MEDIAN = 0, // Median (robust to gaps/news)
   CB_VOL_MEAN   = 1  // Mean
  };

//+------------------------------------------------------------------+
//| Settings. Field names mirror the Pine inputs 1:1.                 |
//+------------------------------------------------------------------+
struct CandleBaseSettings
  {
   //--- 1. volatility reference
   int               volLen;            // TR window length
   ENUM_CB_VOLAGG    volMethod;         // aggregation
   //--- 2. global noise gates
   double            minRangeVol;       // min bar range, x volRef
   double            eqTolVol;          // body-direction tolerance, x volRef
   double            minBodyFracRng;    // doji threshold, body x range
   //--- 3. hammer / inverted hammer
   double            hamWickFrac;       // signal wick >= x range
   double            hamBodyFrac;       // body       <= x range
   double            hamOppWickFrac;    // opposite wick <= x range
   double            hamWickToBody;     // signal wick >= x body
   bool              hamAllowDoji;      // allow dragonfly / gravestone
   ENUM_CB_COLOUR    hamColour;         // hammer body colour filter
   ENUM_CB_COLOUR    invColour;         // inverted hammer body colour filter
   //--- 4. engulfing
   double            engPrevBodyVol;    // mother body    >= x volRef
   double            engCurBodyVol;     // engulfing body >= x volRef
   double            engRatio;          // engulfing body >= x mother body
   double            engEdgeTolVol;     // SIGNED edge tolerance, x volRef
   double            engBodyFracRng;    // conviction: body >= x own range (0 = off)
   //--- 5. harami
   double            harMotherVol;      // mother body >= x volRef
   double            harChildRatio;     // child body  <= x mother body
   double            harEdgeTolVol;     // SIGNED containment margin, x volRef
   double            harChildRngCap;    // child range <= x mother range (0 = off)
   bool              harAllowCross;     // allow doji child (harami cross)
   bool              harOppColour;      // require opposite child colour

   //--- Defaults. These MUST match the Pine input defaults.
   void SetDefaults()
     {
      volLen         = 15;    volMethod      = CB_VOL_MEDIAN;
      minRangeVol    = 0.50;  eqTolVol       = 0.02;  minBodyFracRng = 0.05;
      hamWickFrac    = 0.55;  hamBodyFrac    = 0.35;  hamOppWickFrac = 0.15;
      hamWickToBody  = 2.00;  hamAllowDoji   = true;
      hamColour      = CB_COL_ANY;  invColour = CB_COL_ANY;
      engPrevBodyVol = 0.15;  engCurBodyVol  = 0.30;  engRatio       = 1.20;
      engEdgeTolVol  = 0.02;  engBodyFracRng = 0.00;
      harMotherVol   = 0.40;  harChildRatio  = 0.70;  harEdgeTolVol  = 0.02;
      harChildRngCap = 0.00;  harAllowCross  = true;  harOppColour   = true;
     }
  };

//+------------------------------------------------------------------+
//| Detection result for one bar.                                     |
//+------------------------------------------------------------------+
struct CandleBaseResult
  {
   bool              valid;        // enough history AND non-degenerate bar
   datetime          barTime;      // open time of the bar under test (SERVER time)
   //--- flags
   bool              hammer;
   bool              invHammer;
   bool              bullEngulf;
   bool              bearEngulf;
   bool              bullHarami;
   bool              bearHarami;
   //--- metrics, exported for signal-level parity checking against Pine
   double            volRef1;
   double            volRef2;
   double            range;
   double            body;
   double            bodyTop;
   double            bodyBot;
   double            upperWick;
   double            lowerWick;

   void Clear()
     {
      valid=false; barTime=0;
      hammer=false; invHammer=false; bullEngulf=false;
      bearEngulf=false; bullHarami=false; bearHarami=false;
      volRef1=0.0; volRef2=0.0; range=0.0; body=0.0;
      bodyTop=0.0; bodyBot=0.0; upperWick=0.0; lowerWick=0.0;
     }

   bool Any() const
     {
      return(hammer || invHammer || bullEngulf || bearEngulf || bullHarami || bearHarami);
     }

   string Names() const
     {
      string s="";
      if(hammer)     s+="HAMMER ";
      if(invHammer)  s+="INV_HAMMER ";
      if(bullEngulf) s+="BULL_ENGULF ";
      if(bearEngulf) s+="BEAR_ENGULF ";
      if(bullHarami) s+="BULL_HARAMI ";
      if(bearHarami) s+="BEAR_HARAMI ";
      return(StringLen(s)>0 ? StringSubstr(s,0,StringLen(s)-1) : "NONE");
     }
  };

//+------------------------------------------------------------------+
//| Engine                                                            |
//+------------------------------------------------------------------+
class CCandleBase
  {
private:
   CandleBaseSettings m_s;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_digits;
   double            m_point;
   bool              m_ready;

   //--- True range at chronological index k. Needs close[k-1].
   static double     TrueRange(const double &h[], const double &l[], const double &c[], const int k)
     {
      if(k<=0)
         return(h[k]-l[k]);                      // mirrors Pine's na(close[1]) branch
      double a = h[k]-l[k];
      double b = MathAbs(h[k]-c[k-1]);
      double d = MathAbs(l[k]-c[k-1]);
      return(MathMax(a,MathMax(b,d)));
     }

   //--- Volatility reference over volLen true ranges, window starting `startOff`
   //--- bars before `idx`. startOff=1 for single-bar patterns, 2 for two-bar.
   //--- Deliberately excludes the pattern bars so a large pattern bar cannot
   //--- inflate its own yardstick and veto itself.
   double            VolRef(const double &h[], const double &l[], const double &c[],
                            const int idx, const int startOff) const
     {
      int n = m_s.volLen;
      if(idx - startOff - n + 1 < 0)
         return(0.0);
      double buf[];
      ArrayResize(buf,n);
      double sum = 0.0;
      for(int i=0; i<n; i++)
        {
         int k = idx - startOff - i;             // Pine: trSeries[startOff + i]
         double tr = TrueRange(h,l,c,k);
         buf[i] = tr;
         sum   += tr;
        }
      if(m_s.volMethod==CB_VOL_MEAN)
         return(sum/(double)n);
      ArraySort(buf);                            // MQL5 ArraySort is ascending
      int mid = n/2;                             // integer division == Pine's int(n/2)
      return((n%2==1) ? buf[mid] : (buf[mid-1]+buf[mid])*0.5);
     }

   static bool       ColourOK(const ENUM_CB_COLOUR f, const bool isBull, const bool isBear)
     {
      if(f==CB_COL_BULL) return(isBull);
      if(f==CB_COL_BEAR) return(isBear);
      return(true);
     }

public:
                     CCandleBase() { m_s.SetDefaults(); m_symbol=""; m_tf=PERIOD_CURRENT;
                                     m_digits=0; m_point=0.0; m_ready=false; }

   void              Settings(const CandleBaseSettings &s) { m_s = s; }
   CandleBaseSettings Settings() const { return(m_s); }

   //--- Minimum closed bars required before idx can be evaluated.
   int               MinBars() const { return(m_s.volLen + 3); }

   //+---------------------------------------------------------------+
   //| Validate settings. Fails LOUDLY — never silently clamps.       |
   //+---------------------------------------------------------------+
   bool              ValidateSettings(string &err) const
     {
      err="";
      if(m_s.volLen < 3 || m_s.volLen > 200)                 err+="volLen must be 3..200. ";
      if(m_s.minRangeVol    < 0.0)                           err+="minRangeVol < 0. ";
      if(m_s.eqTolVol       < 0.0)                           err+="eqTolVol < 0. ";
      if(m_s.minBodyFracRng < 0.0 || m_s.minBodyFracRng>0.5) err+="minBodyFracRng must be 0..0.5. ";
      if(m_s.hamWickFrac    <=0.0 || m_s.hamWickFrac   >1.0) err+="hamWickFrac must be 0..1. ";
      if(m_s.hamBodyFrac    <=0.0 || m_s.hamBodyFrac   >1.0) err+="hamBodyFrac must be 0..1. ";
      if(m_s.hamOppWickFrac < 0.0 || m_s.hamOppWickFrac>1.0) err+="hamOppWickFrac must be 0..1. ";
      if(m_s.hamWickToBody  < 0.0)                           err+="hamWickToBody < 0. ";
      if(m_s.engRatio       < 1.0)                           err+="engRatio must be >= 1.0. ";
      if(m_s.engBodyFracRng < 0.0 || m_s.engBodyFracRng>1.0) err+="engBodyFracRng must be 0..1. ";
      if(m_s.harChildRatio  <=0.0 || m_s.harChildRatio >1.0) err+="harChildRatio must be 0..1. ";
      if(m_s.harChildRngCap < 0.0)                           err+="harChildRngCap < 0. ";
      //--- geometric coherence: the three hammer fractions must admit a real shape
      if(m_s.hamWickFrac + m_s.hamOppWickFrac >= 1.0)
         err+="hamWickFrac + hamOppWickFrac >= 1.0 leaves no room for a body; detector will never fire. ";
      return(StringLen(err)==0);
     }

   //+---------------------------------------------------------------+
   //| Bind to a symbol and verify its properties exist. Nothing is   |
   //| hardcoded: digits/point/ticksize are read at runtime.          |
   //| Call from OnInit and abort the EA/indicator if this is false.  |
   //+---------------------------------------------------------------+
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, string &err)
     {
      m_ready=false;
      err="";
      m_symbol = (symbol=="" ? _Symbol : symbol);
      m_tf     = (tf==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : tf);

      if(!SymbolSelect(m_symbol,true))
        { err="SymbolSelect failed for '"+m_symbol+"' (err "+IntegerToString(GetLastError())+")"; return(false); }

      long dg=0;
      if(!SymbolInfoInteger(m_symbol,SYMBOL_DIGITS,dg))
        { err="SYMBOL_DIGITS unavailable for '"+m_symbol+"'"; return(false); }
      m_digits=(int)dg;

      m_point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(m_point<=0.0)
        { err="SYMBOL_POINT invalid for '"+m_symbol+"'"; return(false); }

      double tickSize = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSize>0.0 && MathAbs(tickSize-m_point) > m_point*0.5)
         PrintFormat("CANDLE_BASE WARNING: %s tick size (%.*f) != point (%.*f). "
                     "Price levels derived downstream must be normalised to tick size, not point.",
                     m_symbol, m_digits, tickSize, m_digits, m_point);

      string serr="";
      if(!ValidateSettings(serr))
        { err="Invalid settings: "+serr; return(false); }

      m_ready=true;
      return(true);
     }

   bool              IsReady() const { return(m_ready); }
   int               Digits_()  const { return(m_digits); }
   double            Point_()   const { return(m_point);  }

   //+---------------------------------------------------------------+
   //| CORE DETECTION.                                                |
   //| Arrays MUST be chronological (ArraySetAsSeries false).         |
   //| idx = index of the CLOSED bar under test. idx-1 = mother bar.  |
   //| Returns false if there is not enough history to decide.        |
   //+---------------------------------------------------------------+
   bool              DetectAt(const double &o[], const double &h[], const double &l[], const double &c[],
                              const int total, const int idx, CandleBaseResult &res) const
     {
      res.Clear();
      if(idx<1 || idx>=total)
         return(false);

      //=== geometry of the bar under test (Pine offset 0) ===========
      double cO=o[idx], cH=h[idx], cL=l[idx], cC=c[idx];
      double cRng  = cH-cL;
      double cBody = MathAbs(cC-cO);
      double cTop  = MathMax(cO,cC);     // body top — NOT the high
      double cBot  = MathMin(cO,cC);     // body bot — NOT the low
      double cUw   = cH-cTop;
      double cLw   = cBot-cL;

      //=== geometry of the mother bar (Pine offset 1) ===============
      double pO=o[idx-1], pH=h[idx-1], pL=l[idx-1], pC=c[idx-1];
      double pRng  = pH-pL;
      double pBody = MathAbs(pC-pO);
      double pTop  = MathMax(pO,pC);
      double pBot  = MathMin(pO,pC);

      //=== volatility references (windows exclude the pattern bars) =
      double volRef1 = VolRef(h,l,c,idx,1);
      double volRef2 = VolRef(h,l,c,idx,2);

      res.volRef1=volRef1; res.volRef2=volRef2;
      res.range=cRng; res.body=cBody; res.bodyTop=cTop; res.bodyBot=cBot;
      res.upperWick=cUw; res.lowerWick=cLw;

      bool valid1 = (cRng>0.0 && volRef1>0.0 && idx >= m_s.volLen+1);
      bool valid2 = (cRng>0.0 && pRng>0.0 && volRef2>0.0 && idx >= m_s.volLen+2);
      if(!valid1 && !valid2)
         return(false);
      res.valid = true;

      bool sig1 = valid1 && (cRng >= m_s.minRangeVol*volRef1);
      bool sig2 = valid2 && (cRng >= m_s.minRangeVol*volRef2);

      //=== tolerances, volatility-scaled (broker/digits agnostic) ===
      double tol1    = m_s.eqTolVol      * volRef1;
      double tol2    = m_s.eqTolVol      * volRef2;
      double engEdge = m_s.engEdgeTolVol * volRef2;
      double harEdge = m_s.harEdgeTolVol * volRef2;

      //=== direction. A body inside the tolerance band is DIRECTIONLESS,
      //=== not bullish — this is what keeps doji noise out of colour tests.
      bool cBull1 = (cC > cO + tol1);
      bool cBear1 = (cC < cO - tol1);
      bool cBull2 = (cC > cO + tol2);
      bool cBear2 = (cC < cO - tol2);
      bool pBull2 = (pC > pO + tol2);
      bool pBear2 = (pC < pO - tol2);

      //=== doji classification (multiplication form, P3) ============
      bool cIsDoji = (cBody < m_s.minBodyFracRng * cRng);
      bool pIsDoji = (pBody < m_s.minBodyFracRng * pRng);

      //--------------------------------------------------------------
      // HAMMER / INVERTED HAMMER
      // These are SHAPES. Hammer == Hanging Man and Inverted Hammer ==
      // Shooting Star geometrically; only prior trend separates them and
      // that belongs to the strategy, not here.
      //--------------------------------------------------------------
      bool dojiOK = (m_s.hamAllowDoji || !cIsDoji);

      res.hammer = sig1
                   && (cLw   >= m_s.hamWickFrac    * cRng)
                   && (cBody <= m_s.hamBodyFrac    * cRng)
                   && (cUw   <= m_s.hamOppWickFrac * cRng)
                   && (cLw   >= m_s.hamWickToBody  * cBody)
                   && dojiOK
                   && ColourOK(m_s.hamColour,cBull1,cBear1);

      res.invHammer = sig1
                   && (cUw   >= m_s.hamWickFrac    * cRng)
                   && (cBody <= m_s.hamBodyFrac    * cRng)
                   && (cLw   <= m_s.hamOppWickFrac * cRng)
                   && (cUw   >= m_s.hamWickToBody  * cBody)
                   && dojiOK
                   && ColourOK(m_s.invColour,cBull1,cBear1);

      //--------------------------------------------------------------
      // ENGULFING — BODY engulfing. Wicks are not consulted.
      // engEdge is SIGNED: positive lets the engulfing body fall just
      // short of the mother edge (fixes open==prior-close starvation in
      // a continuous feed); negative demands strict overshoot.
      //--------------------------------------------------------------
      bool engSizeOK = (pBody >= m_s.engPrevBodyVol * volRef2)
                    && (cBody >= m_s.engCurBodyVol  * volRef2)
                    && (cBody >= m_s.engRatio       * pBody)
                    && (cBody >= m_s.engBodyFracRng * cRng);
      bool engWraps  = (cTop >= pTop - engEdge) && (cBot <= pBot + engEdge);

      res.bullEngulf = sig2 && pBear2 && cBull2 && !pIsDoji && engSizeOK && engWraps;
      res.bearEngulf = sig2 && pBull2 && cBear2 && !pIsDoji && engSizeOK && engWraps;

      //--------------------------------------------------------------
      // HARAMI — P4. CONTAINMENT IS BODY-AGAINST-BODY ONLY.
      // cH/cL/pH/pL are NOT referenced below. The child's wicks are free
      // to break above the mother's high, below its low, or both, and the
      // pattern still qualifies. Only the child's OPEN and CLOSE must sit
      // inside the mother's open/close range.
      //--------------------------------------------------------------
      bool harInside  = (cTop <= pTop - harEdge) && (cBot >= pBot + harEdge);
      bool harSizeOK  = (pBody >= m_s.harMotherVol  * volRef2)
                     && (cBody <= m_s.harChildRatio * pBody);
      bool harCrossOK = (m_s.harAllowCross || !cIsDoji);
      bool harRangeOK = (m_s.harChildRngCap <= 0.0) || (cRng <= m_s.harChildRngCap * pRng);
      bool harCommon  = sig2 && !pIsDoji && harInside && harSizeOK && harCrossOK && harRangeOK;

      // Direction comes from the MOTHER. Child colour is optional confirmation.
      res.bullHarami = harCommon && pBear2 && (!m_s.harOppColour || cBull2);
      res.bearHarami = harCommon && pBull2 && (!m_s.harOppColour || cBear2);

      return(true);
     }

   //+---------------------------------------------------------------+
   //| Convenience wrapper for EA use: pulls its own history.         |
   //| shift = 1 means "the last CLOSED bar" (never pass 0).          |
   //| Stateless — safe across EA restarts, nothing to rebuild.       |
   //+---------------------------------------------------------------+
   bool              Detect(const int shift, CandleBaseResult &res)
     {
      res.Clear();
      if(!m_ready)
        { Print("CANDLE_BASE: Detect() called before successful Init()"); return(false); }
      if(shift < 1)
        { Print("CANDLE_BASE: shift must be >= 1 (bar 0 is still forming)"); return(false); }

      int need = MinBars();
      MqlRates r[];
      ArraySetAsSeries(r,false);                       // P1: chronological
      int got = CopyRates(m_symbol,m_tf,shift,need,r);
      if(got < need)
        {
         PrintFormat("CANDLE_BASE: CopyRates(%s,%s,%d,%d) returned %d (err %d) — history not ready",
                     m_symbol,EnumToString(m_tf),shift,need,got,GetLastError());
         return(false);
        }

      double o[],h[],l[],c[];
      ArrayResize(o,got); ArrayResize(h,got); ArrayResize(l,got); ArrayResize(c,got);
      for(int i=0;i<got;i++)
        { o[i]=r[i].open; h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; }

      int idx = got-1;                                  // last copied bar == bar `shift`
      bool ok = DetectAt(o,h,l,c,got,idx,res);
      res.barTime = r[idx].time;                        // SERVER time
      return(ok);
     }
  };

#endif // __CANDLE_BASE_MQH__
//+------------------------------------------------------------------+
