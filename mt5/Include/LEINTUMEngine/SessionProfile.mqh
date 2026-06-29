// Computes SVR, session type, and SL multiplier.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CSessionProfile
// ------------------------------------------------------------
class CSessionProfile
{
private:
   CPriceFabric*     m_fabric;
   SSessionState     m_state;
   double            m_atr_values[20];   // rolling ATR buffer

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CSessionProfile(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      // Initialise state to safe defaults
      m_state.type         = SESSION_NORMAL;
      m_state.svr          = 1.0;
      m_state.slMultiplier = 1.0;

      // Zero out ATR buffer
      for(int i = 0; i < 20; i++)
         m_atr_values[i] = 0.0;
   }

   // ------------------------------------------------------------
   // Refresh — compute SVR, session type, slMultiplier
   // ------------------------------------------------------------
   bool Refresh()
   {
      // 1. Compute current ATR (14-period) on EURUSD M15
      //    using the last 15 bars from m_fabric.
      //    For each of the last 14 bars (shift 1..14) compute TR,
      //    then ATR = average of those 14 TR values.

      double trSum = 0.0;
      bool   valid = true;

      for(int shift = 1; shift <= 14; shift++)
      {
         double high = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double low  = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
         double closePrev = m_fabric.GetClose("EURUSD", PERIOD_M15, shift + 1);

         // If any value is zero, data is not available
         if(high == 0.0 || low == 0.0 || closePrev == 0.0)
         {
            valid = false;
            break;
         }

         double tr1 = high - low;
         double tr2 = MathAbs(high - closePrev);
         double tr3 = MathAbs(low  - closePrev);

         double tr = MathMax(tr1, MathMax(tr2, tr3));
         trSum += tr;
      }

      if(!valid)
      {
         PrintFormat("[LEINTUM] SessionProfile: zero values from PriceFabric, cannot compute ATR");
         return false;
      }

      double currentATR = trSum / 14.0;

      // 2. Compute ATR_avg = average ATR over the previous 20 bars
      //    (shifts 1..20). We compute ATR for each shift window
      //    (shift 1..20) and store in m_atr_values, then average.

      double atrAvgSum = 0.0;
      int    atrCount  = 0;

      for(int baseShift = 1; baseShift <= 20; baseShift++)
      {
         double sumTR = 0.0;
         bool   ok    = true;

         for(int offset = 0; offset < 14; offset++)
         {
            int shift = baseShift + offset;

            double high = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
            double low  = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
            double closePrev = m_fabric.GetClose("EURUSD", PERIOD_M15, shift + 1);

            if(high == 0.0 || low == 0.0 || closePrev == 0.0)
            {
               ok = false;
               break;
            }

            double tr1 = high - low;
            double tr2 = MathAbs(high - closePrev);
            double tr3 = MathAbs(low  - closePrev);

            double tr = MathMax(tr1, MathMax(tr2, tr3));
            sumTR += tr;
         }

         if(!ok)
         {
            // Not enough data for this window — skip
            continue;
         }

         double atr = sumTR / 14.0;
         m_atr_values[atrCount] = atr;
         atrAvgSum += atr;
         atrCount++;
      }

      // If we couldn't compute any ATR values, fall back to currentATR
      double atrAvg;
      if(atrCount > 0)
         atrAvg = atrAvgSum / (double)atrCount;
      else
         atrAvg = currentATR;

      // 3. Compute SVR = currentATR / atrAvg
      //    Clamp SVR to [0.1, 5.0]
      double rawSvr = (atrAvg > 0.0) ? (currentATR / atrAvg) : 1.0;
      double svr    = MathMax(0.1, MathMin(5.0, rawSvr));

      // 4. Determine session type from SVR
      ENUM_SESSION_TYPE sessionType;
      if(svr > 2.0)
         sessionType = SESSION_SPIKE;
      else if(svr >= 1.2)
         sessionType = SESSION_HOT;
      else if(svr >= 0.7)
         sessionType = SESSION_NORMAL;
      else
         sessionType = SESSION_QUIET;

      // 5. Compute slMultiplier based on session type
      double slMultiplier;
      switch(sessionType)
      {
         case SESSION_SPIKE:  slMultiplier = 2.0; break;
         case SESSION_HOT:    slMultiplier = 1.5; break;
         case SESSION_NORMAL: slMultiplier = 1.0; break;
         case SESSION_QUIET:  slMultiplier = 0.8; break;
         default:             slMultiplier = 1.0; break;
      }

      // Store results in m_state
      m_state.type         = sessionType;
      m_state.svr          = svr;          // already clamped
      m_state.slMultiplier = slMultiplier;

      return true;
   }

   // ------------------------------------------------------------
   // GetState
   // ------------------------------------------------------------
   SSessionState GetState()
   {
      return m_state;
   }
};
