// OHLCV data fetcher for all symbols and timeframes.
// No formula logic — data retrieval only.

#include "Defines.mqh"

// ------------------------------------------------------------
// CPriceFabric
// ------------------------------------------------------------
class CPriceFabric
{
private:
   // Symbols: EURUSD (primary) + 6 cross pairs
   string            m_symbols[7];      // EURUSD,GBPUSD,USDCHF,USDJPY,AUDUSD,XAUUSD,USOIL
   // Timeframes: M15, H1, H4, D1
   ENUM_TIMEFRAMES   m_timeframes[4];   // PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1

   // Cached bar counts verified on last Refresh()
   int               m_bar_counts[7][4];   // [symbol][timeframe]

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CPriceFabric()
   {
      // Initialise symbol list
      m_symbols[0] = "EURUSD";
      m_symbols[1] = "GBPUSD";
      m_symbols[2] = "USDCHF";
      m_symbols[3] = "USDJPY";
      m_symbols[4] = "AUDUSD";
      m_symbols[5] = "XAUUSD";
      m_symbols[6] = "USOIL";

      // Initialise timeframe list
      m_timeframes[0] = PERIOD_M15;
      m_timeframes[1] = PERIOD_H1;
      m_timeframes[2] = PERIOD_H4;
      m_timeframes[3] = PERIOD_D1;

      // Zero out bar counts
      for(int s = 0; s < 7; s++)
         for(int t = 0; t < 4; t++)
            m_bar_counts[s][t] = 0;
   }

   // ------------------------------------------------------------
   // Refresh — verify data availability for all symbol/TF pairs
   // ------------------------------------------------------------
   bool Refresh()
   {
      bool allOk = true;

      for(int s = 0; s < 7; s++)
      {
         for(int t = 0; t < 4; t++)
         {
            string sym   = m_symbols[s];
            ENUM_TIMEFRAMES tf = m_timeframes[t];

            // Attempt to copy OHLCV arrays to verify availability
            double open[];
            double high[];
            double low[];
            double close[];
            long   volume[];

            int copiedOpen   = CopyOpen(sym, tf, 0, 200, open);
            int copiedHigh   = CopyHigh(sym, tf, 0, 200, high);
            int copiedLow    = CopyLow(sym, tf, 0, 200, low);
            int copiedClose  = CopyClose(sym, tf, 0, 200, close);
            int copiedVolume = CopyTickVolume(sym, tf, 0, 200, volume);

            // Determine the minimum number of bars available across all arrays
            int minBars = MathMin(copiedOpen, MathMin(copiedHigh,
                            MathMin(copiedLow, MathMin(copiedClose, copiedVolume))));

            m_bar_counts[s][t] = minBars;

            // Warn if fewer than 100 bars
            if(minBars < 100)
            {
               PrintFormat("[LEINTUM] PriceFabric: insufficient bars for %s %s",
                           sym, EnumToString(tf));
               allOk = false;
            }
         }
      }

      // EURUSD M15 must have at least 200 bars
      int eurusdM15Bars = m_bar_counts[0][0];   // index 0 = EURUSD, index 0 = PERIOD_M15
      if(eurusdM15Bars < 200)
      {
         PrintFormat("[LEINTUM] PriceFabric: EURUSD M15 has only %d bars (need 200)",
                     eurusdM15Bars);
         allOk = false;
      }

      return allOk;
   }

   // ------------------------------------------------------------
   // OHLCV getters
   // ------------------------------------------------------------
   double GetOpen(string symbol, ENUM_TIMEFRAMES tf, int shift)
   {
      double val = iOpen(symbol, tf, shift);
      if(val == 0.0)
         return 0.0;
      return val;
   }

   double GetHigh(string symbol, ENUM_TIMEFRAMES tf, int shift)
   {
      double val = iHigh(symbol, tf, shift);
      if(val == 0.0)
         return 0.0;
      return val;
   }

   double GetLow(string symbol, ENUM_TIMEFRAMES tf, int shift)
   {
      double val = iLow(symbol, tf, shift);
      if(val == 0.0)
         return 0.0;
      return val;
   }

   double GetClose(string symbol, ENUM_TIMEFRAMES tf, int shift)
   {
      double val = iClose(symbol, tf, shift);
      if(val == 0.0)
         return 0.0;
      return val;
   }

   long GetVolume(string symbol, ENUM_TIMEFRAMES tf, int shift)
   {
      long val = iVolume(symbol, tf, shift);
      if(val == 0)
         return 0;
      return val;
   }

   // ------------------------------------------------------------
   // GetBarCount
   // ------------------------------------------------------------
   int GetBarCount(string symbol, ENUM_TIMEFRAMES tf)
   {
      // Find the index for the given symbol
      int symIdx = -1;
      for(int s = 0; s < 7; s++)
      {
         if(m_symbols[s] == symbol)
         {
            symIdx = s;
            break;
         }
      }
      if(symIdx == -1)
         return 0;

      // Find the index for the given timeframe
      int tfIdx = -1;
      for(int t = 0; t < 4; t++)
      {
         if(m_timeframes[t] == tf)
         {
            tfIdx = t;
            break;
         }
      }
      if(tfIdx == -1)
         return 0;

      return m_bar_counts[symIdx][tfIdx];
   }

   // ------------------------------------------------------------
   // GetCurrentBarNumber
   // ------------------------------------------------------------
   int GetCurrentBarNumber()
   {
      int bars = iBars("EURUSD", PERIOD_M15);
      if(bars < 1)
         return 0;
      return bars - 1;
   }
};
