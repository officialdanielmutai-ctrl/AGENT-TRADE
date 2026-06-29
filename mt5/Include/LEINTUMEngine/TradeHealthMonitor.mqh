// Computes 5-component health score for open positions.
// Emergency exit triggers below LEINTUM_HEALTH_EMERGENCY (25).

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CTradeHealthMonitor
// ------------------------------------------------------------
class CTradeHealthMonitor
{
private:
   CPriceFabric*  m_fabric;
   double         m_health_score;
   bool           m_emergency_exit;

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CTradeHealthMonitor(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      m_health_score  = 100.0;
      m_emergency_exit = false;
   }

   // ------------------------------------------------------------
   // Compute — 5-component health score
   // ------------------------------------------------------------
   double Compute(SOpenPosition &pos, SRegime &regime, SMomentum &momentum)
   {
      // If no position exists, return perfect health
      if(!pos.exists)
      {
         m_health_score  = 100.0;
         m_emergency_exit = false;
         return m_health_score;
      }

      // ---------------------------------------------------------
      // 1. Distance component (0–20)
      // ---------------------------------------------------------
      double pipDistance = MathAbs(pos.current_price - pos.entry_price) / _Point / 10.0;

      bool inProfit = false;
      if(pos.direction == 1 && pos.current_price > pos.entry_price)
         inProfit = true;
      else if(pos.direction == -1 && pos.current_price < pos.entry_price)
         inProfit = true;

      double distanceScore;
      if(inProfit)
         distanceScore = MathMin(20.0, pipDistance * 2.0);
      else
         distanceScore = MathMax(0.0, 20.0 - pipDistance * 2.0);

      // ---------------------------------------------------------
      // 2. Trend alignment (0–20)
      // ---------------------------------------------------------
      double alignScore;
      if(regime.type == REGIME_TRENDING_UP && pos.direction == 1)
         alignScore = 20.0;
      else if(regime.type == REGIME_TRENDING_DOWN && pos.direction == -1)
         alignScore = 20.0;
      else if(regime.type == REGIME_RANGING)
         alignScore = 10.0;
      else
         alignScore = 0.0;

      // ---------------------------------------------------------
      // 3. Momentum alignment (0–20)
      // ---------------------------------------------------------
      double momentumScore;
      if(momentum.phase == PHASE_WAXING)
      {
         // direction matches: WAXING with positive NPV for BUY,
         // or WAXING with negative NPV for SELL
         bool directionMatches = false;
         if(pos.direction == 1 && momentum.npv > 0.0)
            directionMatches = true;
         else if(pos.direction == -1 && momentum.npv < 0.0)
            directionMatches = true;

         if(directionMatches)
            momentumScore = 20.0;
         else
            momentumScore = 5.0;   // WAXING but opposite direction
      }
      else if(momentum.phase == PHASE_NEUTRAL)
         momentumScore = 10.0;
      else if(momentum.phase == PHASE_WANING)
         momentumScore = 5.0;
      else // PHASE_EXHAUSTED
         momentumScore = 0.0;

      // ---------------------------------------------------------
      // 4. Time decay (0–20)
      // ---------------------------------------------------------
      double timeScore = 15.0;   // fixed proxy

      // ---------------------------------------------------------
      // 5. Adverse move count (0–20)
      // ---------------------------------------------------------
      int adverseCount = 0;
      for(int shift = 1; shift <= 5; shift++)
      {
         double open  = m_fabric.GetOpen("EURUSD", PERIOD_M15, shift);
         double close = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);

         if(open == 0.0 || close == 0.0)
         {
            PrintFormat("[LEINTUM] TradeHealthMonitor: zero OHLC for adverse count at shift %d", shift);
            // skip this bar
            continue;
         }

         if(pos.direction == 1)
         {
            // BUY: bearish bar (close < open) is adverse
            if(close < open)
               adverseCount++;
         }
         else // pos.direction == -1
         {
            // SELL: bullish bar (close > open) is adverse
            if(close > open)
               adverseCount++;
         }
      }

      double adverseScore = MathMax(0.0, 20.0 - adverseCount * 4.0);

      // ---------------------------------------------------------
      // Sum components and clamp
      // ---------------------------------------------------------
      double rawScore = distanceScore + alignScore + momentumScore +
                        timeScore + adverseScore;

      m_health_score = MathMax(0.0, MathMin(100.0, rawScore));

      // ---------------------------------------------------------
      // Emergency exit check
      // ---------------------------------------------------------
      m_emergency_exit = (m_health_score < LEINTUM_HEALTH_EMERGENCY);

      // Log
      PrintFormat("[LEINTUM] HealthScore=%.1f emergency=%s",
                  m_health_score,
                  m_emergency_exit ? "true" : "false");

      return m_health_score;
   }

   // ------------------------------------------------------------
   // IsEmergency
   // ------------------------------------------------------------
   bool IsEmergency()
   {
      return m_emergency_exit;
   }

   // ------------------------------------------------------------
   // GetScore
   // ------------------------------------------------------------
   double GetScore()
   {
      return m_health_score;
   }
};
