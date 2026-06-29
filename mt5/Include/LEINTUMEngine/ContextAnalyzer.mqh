// Computes H1/H4/D1 flow scores, consensus, and agree_count.
// H4 carries double weight in consensus.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CContextAnalyzer
// ------------------------------------------------------------
class CContextAnalyzer
{
private:
   CPriceFabric*  m_fabric;
   SHTFContext    m_htf;

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CContextAnalyzer(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      // Initialise HTF context to safe defaults
      m_htf.h1_flow     = 0.0;
      m_htf.h4_flow     = 0.0;
      m_htf.d1_flow     = 0.0;
      m_htf.consensus   = 0.0;
      m_htf.agree_count = 0;
   }

   // ------------------------------------------------------------
   // Refresh — compute flow scores, consensus, agree_count
   // ------------------------------------------------------------
   bool Refresh()
   {
      // ---------------------------------------------------------
      // Helper lambda to compute flow score for a given timeframe
      // ---------------------------------------------------------
      auto computeFlow = [&](ENUM_TIMEFRAMES tf) -> double
      {
         int bull = 0;
         int bear = 0;

         for(int shift = 1; shift <= 20; shift++)
         {
            double open  = m_fabric.GetOpen("EURUSD", tf, shift);
            double close = m_fabric.GetClose("EURUSD", tf, shift);

            if(open == 0.0 || close == 0.0)
            {
               PrintFormat("[LEINTUM] ContextAnalyzer: zero OHLC for %s at shift %d",
                           EnumToString(tf), shift);
               return 0.0;   // will cause caller to return false
            }

            if(close > open)
               bull++;
            else if(close < open)
               bear++;
         }

         return (bull - bear) / 20.0;   // naturally bounded [-1, +1]
      };

      // ---------------------------------------------------------
      // Compute flow scores for H1, H4, D1
      // ---------------------------------------------------------
      double h1Flow = computeFlow(PERIOD_H1);
      double h4Flow = computeFlow(PERIOD_H4);
      double d1Flow = computeFlow(PERIOD_D1);

      // If any flow score is exactly 0.0 due to zero data, we treat
      // that as an error (the helper returned 0.0 on zero data).
      // We'll check if any of the three returned 0.0 because of
      // zero OHLC. Since 0.0 is a valid flow score, we need a
      // different indicator. We'll use a separate flag.
      // For simplicity, we'll just check if any of the three
      // returned 0.0 AND the corresponding OHLC was zero.
      // But we already printed a warning. We'll just proceed.
      // If any flow score is 0.0 due to zero data, we'll return false.
      // We'll use a separate bool.
      bool dataOk = true;

      // Recompute with error detection
      auto computeFlowSafe = [&](ENUM_TIMEFRAMES tf, double &result) -> bool
      {
         int bull = 0;
         int bear = 0;

         for(int shift = 1; shift <= 20; shift++)
         {
            double open  = m_fabric.GetOpen("EURUSD", tf, shift);
            double close = m_fabric.GetClose("EURUSD", tf, shift);

            if(open == 0.0 || close == 0.0)
            {
               PrintFormat("[LEINTUM] ContextAnalyzer: zero OHLC for %s at shift %d",
                           EnumToString(tf), shift);
               return false;
            }

            if(close > open)
               bull++;
            else if(close < open)
               bear++;
         }

         result = (bull - bear) / 20.0;
         return true;
      };

      if(!computeFlowSafe(PERIOD_H1, h1Flow) ||
         !computeFlowSafe(PERIOD_H4, h4Flow) ||
         !computeFlowSafe(PERIOD_D1, d1Flow))
      {
         return false;
      }

      // ---------------------------------------------------------
      // Consensus: H4 gets double weight
      // ---------------------------------------------------------
      double consensus = (h1Flow + (h4Flow * 2.0) + d1Flow) / 4.0;

      // Clamp consensus to [-1.0, 1.0]
      consensus = MathMax(-1.0, MathMin(1.0, consensus));

      // ---------------------------------------------------------
      // agree_count
      // ---------------------------------------------------------
      int agree = 0;

      if(consensus > 0.0)
      {
         if(h1Flow > 0.0) agree++;
         if(h4Flow > 0.0) agree++;
         if(d1Flow > 0.0) agree++;
      }
      else if(consensus < 0.0)
      {
         if(h1Flow < 0.0) agree++;
         if(h4Flow < 0.0) agree++;
         if(d1Flow < 0.0) agree++;
      }
      // else consensus == 0.0 → agree stays 0

      // ---------------------------------------------------------
      // Store results in m_htf
      // ---------------------------------------------------------
      m_htf.h1_flow     = h1Flow;
      m_htf.h4_flow     = h4Flow;
      m_htf.d1_flow     = d1Flow;
      m_htf.consensus   = consensus;
      m_htf.agree_count = agree;

      // Log
      PrintFormat("[LEINTUM] HTF: H1=%.3f H4=%.3f D1=%.3f consensus=%.3f agree=%d",
                  m_htf.h1_flow, m_htf.h4_flow, m_htf.d1_flow,
                  m_htf.consensus, m_htf.agree_count);

      return true;
   }

   // ------------------------------------------------------------
   // GetHTF
   // ------------------------------------------------------------
   SHTFContext GetHTF()
   {
      return m_htf;
   }
};
