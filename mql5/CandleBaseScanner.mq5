//+------------------------------------------------------------------+
//|                                           CandleBaseScanner.mq5  |
//|   CANDLE_BASE v1.0 — visual scanner + signal logger               |
//|                                                                   |
//|   Purpose: (a) eyeball the detections on the BROKER's own chart,  |
//|            (b) emit a timestamped signal log so parity with       |
//|                CANDLE_BASE.pine is validated at SIGNAL level,     |
//|                not by comparing pictures.                          |
//|                                                                   |
//|   This is NOT a strategy and places no orders. No magic number is |
//|   involved because nothing here touches positions.                 |
//+------------------------------------------------------------------+
#property copyright "CANDLE_BASE"
#property version   "1.00"
#property description "Hammer / Inverted Hammer / Engulfing / Harami detector. Base module — no trade logic."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

// Shared module in MQL5\Include\CandleBase.mqh — angle brackets resolve from
// MQL5\Include regardless of where this .mq5 sits.
#include <CandleBase.mqh>

//--- plot 0 : Hammer
#property indicator_label1  "Hammer"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrSeaGreen
#property indicator_width1  1
//--- plot 1 : Inverted Hammer
#property indicator_label2  "Inverted Hammer"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1
//--- plot 2 : Bullish Engulfing
#property indicator_label3  "Bullish Engulfing"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2
//--- plot 3 : Bearish Engulfing
#property indicator_label4  "Bearish Engulfing"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2
//--- plot 4 : Bullish Harami
#property indicator_label5  "Bullish Harami"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrMediumSpringGreen
#property indicator_width5  1
//--- plot 5 : Bearish Harami
#property indicator_label6  "Bearish Harami"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrOrangeRed
#property indicator_width6  1

enum ENUM_CB_LOGMODE
  {
   CB_LOG_OFF     = 0,  // Off
   CB_LOG_NEWBARS = 1,  // New bars only
   CB_LOG_ALL     = 2   // All history (use for parity export)
  };

//================== INPUTS — mirror CANDLE_BASE.pine 1:1 ============
input group "1 · Volatility reference"
input int             InpVolLen          = 15;              // TR window length (bars)
input ENUM_CB_VOLAGG  InpVolMethod       = CB_VOL_MEDIAN;   // TR aggregation

input group "2 · Global noise gates"
input double          InpMinRangeVol     = 0.50;            // Min bar range (x volRef)
input double          InpEqTolVol        = 0.02;            // Body-direction tolerance (x volRef)
input double          InpMinBodyFracRng  = 0.05;            // Doji threshold: body >= (x range)

input group "3 · Hammer / Inverted Hammer"
input double          InpHamWickFrac     = 0.55;            // Signal wick >= (x range)
input double          InpHamBodyFrac     = 0.35;            // Body <= (x range)
input double          InpHamOppWickFrac  = 0.15;            // Opposite wick <= (x range)
input double          InpHamWickToBody   = 2.00;            // Signal wick >= (x body)
input bool            InpHamAllowDoji    = true;            // Allow doji body
input ENUM_CB_COLOUR  InpHamColour       = CB_COL_ANY;      // Hammer body colour
input ENUM_CB_COLOUR  InpInvColour       = CB_COL_ANY;      // Inv. Hammer body colour

input group "4 · Engulfing"
input double          InpEngPrevBodyVol  = 0.15;            // Mother body >= (x volRef)
input double          InpEngCurBodyVol   = 0.30;            // Engulfing body >= (x volRef)
input double          InpEngRatio        = 1.20;            // Engulfing body >= (x mother body)
input double          InpEngEdgeTolVol   = 0.02;            // SIGNED edge tolerance (x volRef)
input double          InpEngBodyFracRng  = 0.00;            // Conviction: body >= (x own range), 0=off

input group "5 · Harami"
input double          InpHarMotherVol    = 0.40;            // Mother body >= (x volRef)
input double          InpHarChildRatio   = 0.70;            // Child body <= (x mother body)
input double          InpHarEdgeTolVol   = 0.02;            // SIGNED containment margin (x volRef)
input bool            InpHarAllowCross   = true;            // Allow doji child (harami cross)
input bool            InpHarOppColour    = true;            // Require opposite child colour
input double          InpHarChildRngCap  = 0.00;            // Child RANGE <= (x mother range), 0=off

input group "6 · Display & logging"
input int             InpArrowHammer     = 233;             // Wingdings code: Hammer
input int             InpArrowInvHammer  = 233;             // Wingdings code: Inverted Hammer
input int             InpArrowBullEng    = 225;             // Wingdings code: Bullish Engulfing
input int             InpArrowBearEng    = 226;             // Wingdings code: Bearish Engulfing
input int             InpArrowBullHar    = 159;             // Wingdings code: Bullish Harami
input int             InpArrowBearHar    = 159;             // Wingdings code: Bearish Harami
input double          InpArrowOffsetVol  = 0.60;            // Arrow offset from bar (x volRef)
input ENUM_CB_LOGMODE InpLogMode         = CB_LOG_NEWBARS;  // Journal logging
input bool            InpWriteCsv        = false;           // Also write CSV to MQL5/Files
input string          InpCsvName         = "CANDLE_BASE_signals.csv"; // CSV file name

//================== GLOBALS =========================================
double g_bufHammer[], g_bufInvHam[], g_bufBullEng[], g_bufBearEng[], g_bufBullHar[], g_bufBearHar[];
CCandleBase g_engine;
int         g_csvHandle = INVALID_HANDLE;
datetime    g_lastLogged = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,g_bufHammer,  INDICATOR_DATA);
   SetIndexBuffer(1,g_bufInvHam,  INDICATOR_DATA);
   SetIndexBuffer(2,g_bufBullEng, INDICATOR_DATA);
   SetIndexBuffer(3,g_bufBearEng, INDICATOR_DATA);
   SetIndexBuffer(4,g_bufBullHar, INDICATOR_DATA);
   SetIndexBuffer(5,g_bufBearHar, INDICATOR_DATA);

   //--- chronological orientation everywhere (parity contract P1)
   ArraySetAsSeries(g_bufHammer, false);
   ArraySetAsSeries(g_bufInvHam, false);
   ArraySetAsSeries(g_bufBullEng,false);
   ArraySetAsSeries(g_bufBearEng,false);
   ArraySetAsSeries(g_bufBullHar,false);
   ArraySetAsSeries(g_bufBearHar,false);

   int codes[6]; codes[0]=InpArrowHammer; codes[1]=InpArrowInvHammer; codes[2]=InpArrowBullEng;
                 codes[3]=InpArrowBearEng; codes[4]=InpArrowBullHar;  codes[5]=InpArrowBearHar;
   for(int i=0;i<6;i++)
     {
      PlotIndexSetInteger(i,PLOT_ARROW,codes[i]);
      PlotIndexSetDouble (i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(i,PLOT_DRAW_BEGIN,InpVolLen+3);
     }

   //--- settings
   CandleBaseSettings s;
   s.SetDefaults();
   s.volLen         = InpVolLen;          s.volMethod      = InpVolMethod;
   s.minRangeVol    = InpMinRangeVol;     s.eqTolVol       = InpEqTolVol;
   s.minBodyFracRng = InpMinBodyFracRng;
   s.hamWickFrac    = InpHamWickFrac;     s.hamBodyFrac    = InpHamBodyFrac;
   s.hamOppWickFrac = InpHamOppWickFrac;  s.hamWickToBody  = InpHamWickToBody;
   s.hamAllowDoji   = InpHamAllowDoji;    s.hamColour      = InpHamColour;
   s.invColour      = InpInvColour;
   s.engPrevBodyVol = InpEngPrevBodyVol;  s.engCurBodyVol  = InpEngCurBodyVol;
   s.engRatio       = InpEngRatio;        s.engEdgeTolVol  = InpEngEdgeTolVol;
   s.engBodyFracRng = InpEngBodyFracRng;
   s.harMotherVol   = InpHarMotherVol;    s.harChildRatio  = InpHarChildRatio;
   s.harEdgeTolVol  = InpHarEdgeTolVol;   s.harChildRngCap = InpHarChildRngCap;
   s.harAllowCross  = InpHarAllowCross;   s.harOppColour   = InpHarOppColour;
   g_engine.Settings(s);

   //--- fail LOUDLY on bad configuration or symbol
   string err="";
   if(!g_engine.Init(_Symbol,(ENUM_TIMEFRAMES)Period(),err))
     {
      Print("CANDLE_BASE INIT FAILED: ",err);
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpWriteCsv)
     {
      g_csvHandle = FileOpen(InpCsvName,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_csvHandle==INVALID_HANDLE)
         Print("CANDLE_BASE: could not open CSV '",InpCsvName,"' (err ",GetLastError(),") — logging to journal only");
      else
         FileWrite(g_csvHandle,"server_time","symbol","tf","pattern",
                   "open","high","low","close","volRef1","volRef2","range","body");
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("CANDLE_BASE %s (TR%d %s)",CANDLE_BASE_VERSION,InpVolLen,
                                   (InpVolMethod==CB_VOL_MEDIAN ? "med" : "mean")));
   PrintFormat("CANDLE_BASE %s initialised on %s %s — digits=%d point=%.*f",
               CANDLE_BASE_VERSION,_Symbol,EnumToString((ENUM_TIMEFRAMES)Period()),
               g_engine.Digits_(),g_engine.Digits_(),g_engine.Point_());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_csvHandle!=INVALID_HANDLE)
     { FileClose(g_csvHandle); g_csvHandle=INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
void LogSignal(const datetime t,const CandleBaseResult &res,
               const double o,const double h,const double l,const double c)
  {
   string names = res.Names();
   int dg = g_engine.Digits_();
   if(InpLogMode!=CB_LOG_OFF)
      PrintFormat("CANDLE_BASE,%s,%s,%s,%s,O=%.*f,H=%.*f,L=%.*f,C=%.*f,volRef1=%.*f,volRef2=%.*f",
                  TimeToString(t,TIME_DATE|TIME_MINUTES),_Symbol,
                  EnumToString((ENUM_TIMEFRAMES)Period()),names,
                  dg,o,dg,h,dg,l,dg,c,dg,res.volRef1,dg,res.volRef2);

   if(g_csvHandle!=INVALID_HANDLE)
      FileWrite(g_csvHandle,TimeToString(t,TIME_DATE|TIME_MINUTES),_Symbol,
                EnumToString((ENUM_TIMEFRAMES)Period()),names,
                DoubleToString(o,dg),DoubleToString(h,dg),
                DoubleToString(l,dg),DoubleToString(c,dg),
                DoubleToString(res.volRef1,dg),DoubleToString(res.volRef2,dg),
                DoubleToString(res.range,dg),DoubleToString(res.body,dg));
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   //--- chronological indexing: index 0 = oldest. Pine's [1] == idx-1.
   ArraySetAsSeries(time, false);
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low,  false);
   ArraySetAsSeries(close,false);

   int minBars = g_engine.MinBars();
   if(rates_total < minBars+2)
      return(0);                       // refuse to decide on insufficient history

   bool firstPass = (prev_calculated==0);
   int  start     = firstPass ? minBars : MathMax(prev_calculated-1, minBars);

   //--- the newest bar (rates_total-1) is still FORMING. Never evaluate it.
   if(firstPass)
     {
      ArrayInitialize(g_bufHammer, EMPTY_VALUE);
      ArrayInitialize(g_bufInvHam, EMPTY_VALUE);
      ArrayInitialize(g_bufBullEng,EMPTY_VALUE);
      ArrayInitialize(g_bufBearEng,EMPTY_VALUE);
      ArrayInitialize(g_bufBullHar,EMPTY_VALUE);
      ArrayInitialize(g_bufBearHar,EMPTY_VALUE);
     }

   CandleBaseResult res;
   for(int idx=start; idx<=rates_total-2; idx++)
     {
      g_bufHammer[idx]=EMPTY_VALUE;  g_bufInvHam[idx]=EMPTY_VALUE;
      g_bufBullEng[idx]=EMPTY_VALUE; g_bufBearEng[idx]=EMPTY_VALUE;
      g_bufBullHar[idx]=EMPTY_VALUE; g_bufBearHar[idx]=EMPTY_VALUE;

      if(!g_engine.DetectAt(open,high,low,close,rates_total,idx,res))
         continue;

      double ref  = (res.volRef1>0.0 ? res.volRef1 : res.volRef2);
      double off  = InpArrowOffsetVol * ref;
      double below = low[idx]  - off;
      double above = high[idx] + off;

      if(res.hammer)     g_bufHammer[idx]  = below;
      if(res.invHammer)  g_bufInvHam[idx]  = below;
      if(res.bullEngulf) g_bufBullEng[idx] = below;
      if(res.bearEngulf) g_bufBearEng[idx] = above;
      if(res.bullHarami) g_bufBullHar[idx] = below;
      if(res.bearHarami) g_bufBearHar[idx] = above;

      //--- logging
      if(res.Any() && InpLogMode!=CB_LOG_OFF)
        {
         bool wantLog = (InpLogMode==CB_LOG_ALL) || (!firstPass && time[idx]>g_lastLogged);
         if(wantLog)
           {
            LogSignal(time[idx],res,open[idx],high[idx],low[idx],close[idx]);
            if(time[idx]>g_lastLogged)
               g_lastLogged = time[idx];
           }
        }
      if(time[idx]>g_lastLogged && InpLogMode==CB_LOG_NEWBARS && firstPass)
         g_lastLogged = time[idx];   // suppress backfill spam on the first pass
     }

   //--- keep the forming bar clean
   if(rates_total>0)
     {
      int last = rates_total-1;
      g_bufHammer[last]=EMPTY_VALUE;  g_bufInvHam[last]=EMPTY_VALUE;
      g_bufBullEng[last]=EMPTY_VALUE; g_bufBearEng[last]=EMPTY_VALUE;
      g_bufBullHar[last]=EMPTY_VALUE; g_bufBearHar[last]=EMPTY_VALUE;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
