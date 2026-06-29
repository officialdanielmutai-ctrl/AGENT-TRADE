// Computes VWAP value area, SDS, and BQS.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CConditionAssessor
// ------------------------------------------------------------
class CConditionAssessor
{
private:
   CPriceFabric*  m_fabric;
   SCondition     m_condition;

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CConditionAssessor(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      // Initialise condition to safe defaults
      m_condition.vwap       = 0.0;
      m_condition.vwap_upper = 0.0;
      m_condition.vwap_lower = 0.0;
      m_condition.in_value   = false;
      m_condition.sds        = 0.0;
      m_condition.bqs        = 0.0;
   }

   // ------------------------------------------------------------
   // Refresh — compute VWAP, SDS, BQS
   // ------------------------------------------------------------
   bool Refresh()
   {
      // ---------------------------------------------------------
      // 1. VWAP and value area
      // ---------------------------------------------------------
      double sumCloseVol = 0.0;
      double sumVol      = 0.0;
      int    count       = 0;

      for(int shift = 1; shift <= 96; shift++)
      {
         double close = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);
         long   vol   = m_fabric.GetVolume("EURUSD", PERIOD_M15, shift);

         if(close == 0.0 || vol == 0)
         {
            PrintFormat("[LEINTUM] ConditionAssessor: zero close/volume for VWAP at shift %d", shift);
            return false;
         }

         sumCloseVol += close * (double)vol;
         sumVol      += (double)vol;
         count++;
      }

      double vwap;
      if(sumVol == 0.0)
      {
         // fallback to current close
         double currentClose = m_fabric.GetClose("EURUSD", PERIOD_M15, 1);
         if(currentClose == 0.0)
         {
            PrintFormat("[LEINTUM] ConditionAssessor: zero current close for VWAP fallback");
            return false;
         }
         vwap = currentClose;
      }
      else
      {
         vwap = sumCloseVol / sumVol;
      }

      // Compute standard deviation of closes around VWAP
      double variance = 0.0;
      for(int shift = 1; shift <= 96; shift++)
      {
         double close = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);
         if(close == 0.0)
         {
            PrintFormat("[LEINTUM] ConditionAssessor: zero close for variance at shift %d", shift);
            return false;
         }
         double diff = close - vwap;
         variance += diff * diff;
      }
      variance /= (double)count;
      double sd = MathSqrt(variance);

      double vwapUpper = vwap + sd;
      double vwapLower = vwap - sd;

      double currentClose = m_fabric.GetClose("EURUSD", PERIOD_M15, 1);
      if(currentClose == 0.0)
      {
         PrintFormat("[LEINTUM] ConditionAssessor: zero current close for in_value check");
         return false;
      }

      bool inValue = (currentClose >= vwapLower) && (currentClose <= vwapUpper);

      // ---------------------------------------------------------
      // 2. SDS (Supply/Demand Score)
      // ---------------------------------------------------------
      double sds = 0.0;
      double proximityThreshold = 10.0 * _Point * 10.0; // 10 pips

      // Find swing highs and lows over last 50 bars (shifts 2..49)
      for(int shift = 2; shift <= 49; shift++)
      {
         double highCurr = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double highPrev = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift - 1);
         double highNext = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift + 1);

         double lowCurr  = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
         double lowPrev  = m_fabric.GetLow("EURUSD", PERIOD_M15, shift - 1);
         double lowNext  = m_fabric.GetLow("EURUSD", PERIOD_M15, shift + 1);

         if(highCurr == 0.0 || highPrev == 0.0 || highNext == 0.0 ||
            lowCurr  == 0.0 || lowPrev  == 0.0 || lowNext  == 0.0)
         {
            PrintFormat("[LEINTUM] ConditionAssessor: zero high/low for SDS at shift %d", shift);
            return false;
         }

         // Swing high
         if(highCurr > highPrev && highCurr > highNext)
         {
            double dist = MathAbs(highCurr - currentClose);
            if(dist <= proximityThreshold)
               sds += 0.2;
         }

         // Swing low
         if(lowCurr < lowPrev && lowCurr < lowNext)
         {
            double dist = MathAbs(lowCurr - currentClose);
            if(dist <= proximityThreshold)
               sds += 0.2;
         }
      }

      // Clamp SDS to [0.0, 1.0]
      sds = MathMax(0.0, MathMin(1.0, sds));

      // ---------------------------------------------------------
      // 3. BQS (Bar Quality Score)
      // ---------------------------------------------------------
      double bqsSum = 0.0;
      int    bqsCount = 0;

      for(int shift = 1; shift <= 10; shift++)
      {
         double open  = m_fabric.GetOpen("EURUSD", PERIOD_M15, shift);
         double close = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);
         double high  = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double low   = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);

         if(open == 0.0 || close == 0.0 || high == 0.0 || low == 0.0)
         {
            PrintFormat("[LEINTUM] ConditionAssessor: zero OHLC for BQS at shift %d", shift);
            return false;
         }

         double range = high - low;
         double bodyRatio;
         if(range == 0.0)
            bodyRatio = 0.0;
         else
            bodyRatio = MathAbs(close - open) / range;

         bqsSum += bodyRatio;
         bqsCount++;
      }

      double bqs;
      if(bqsCount > 0)
         bqs = bqsSum / (double)bqsCount;
      else
         bqs = 0.0;

      // Clamp BQS to [0.0, 1.0]
      bqs = MathMax(0.0, MathMin(1.0, bqs));

      // ---------------------------------------------------------
      // 4. Store results in m_condition
      // ---------------------------------------------------------
      m_condition.vwap       = vwap;
      m_condition.vwap_upper = vwapUpper;
      m_condition.vwap_lower = vwapLower;
      m_condition.in_value   = inValue;
      m_condition.sds        = sds;   // already clamped
      m_condition.bqs        = bqs;   // already clamped

      // Log
      PrintFormat("[LEINTUM] Condition: VWAP=%.5f in_value=%s SDS=%.3f BQS=%.3f",
                  m_condition.vwap,
                  m_condition.in_value ? "true" : "false",
                  m_condition.sds,
                  m_condition.bqs);

      return true;
   }

   // ------------------------------------------------------------
   // GetCondition
   // ------------------------------------------------------------
   SCondition GetCondition()
   {
      return m_condition;
   }
};
