// Computes NPV, IER, acceleration, jerk, and momentum phase.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CMomentumPhase
// ------------------------------------------------------------
class CMomentumPhase
{
private:
   CPriceFabric*    m_fabric;
   SMomentum        m_momentum;
   double           m_prev_npv[3];   // last 3 NPV values for acceleration/jerk
   int              m_prev_idx;
   int              m_callCount;
   double           m_prevAcceleration;

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CMomentumPhase(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      m_momentum.phase        = PHASE_NEUTRAL;
      m_momentum.npv          = 0.0;
      m_momentum.ier          = 1.0;
      m_momentum.acceleration = 0.0;
      m_momentum.jerk         = 0.0;

      for(int i = 0; i < 3; i++)
         m_prev_npv[i] = 0.0;
      m_prev_idx = 0;
      m_callCount = 0;
      m_prevAcceleration = 0.0;
   }

   // ------------------------------------------------------------
   // Refresh
   // ------------------------------------------------------------
   bool Refresh()
   {
      m_callCount++;

      // ---------------------------------------------------------
      // 1. NPV
      // ---------------------------------------------------------
      double close1  = m_fabric.GetClose("EURUSD", PERIOD_M15, 1);
      double close20 = m_fabric.GetClose("EURUSD", PERIOD_M15, 20);

      if(close1 == 0.0 || close20 == 0.0)
      {
         PrintFormat("[LEINTUM] MomentumPhase: zero close value, cannot compute NPV");
         return false;
      }

      double netMove = close1 - close20;

      double maxHigh = -1e10;
      double minLow  = 1e10;
      for(int shift = 1; shift <= 20; shift++)
      {
         double h = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double l = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
         if(h == 0.0 || l == 0.0)
         {
            PrintFormat("[LEINTUM] MomentumPhase: zero high/low value, cannot compute NPV");
            return false;
         }
         if(h > maxHigh) maxHigh = h;
         if(l < minLow)  minLow  = l;
      }

      double maxRange = maxHigh - minLow;
      double npv;
      if(maxRange == 0.0)
         npv = 0.0;
      else
         npv = netMove / maxRange;

      npv = MathMax(-1.0, MathMin(1.0, npv));

      // ---------------------------------------------------------
      // 2. IER
      // ---------------------------------------------------------
      double recentSum = 0.0;
      for(int shift = 1; shift <= 5; shift++)
      {
         double h = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double l = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
         if(h == 0.0 || l == 0.0)
         {
            PrintFormat("[LEINTUM] MomentumPhase: zero high/low for IER recent");
            return false;
         }
         recentSum += (h - l);
      }
      double recentAvgRange = recentSum / 5.0;

      double baselineSum = 0.0;
      for(int shift = 6; shift <= 10; shift++)
      {
         double h = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double l = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);
         if(h == 0.0 || l == 0.0)
         {
            PrintFormat("[LEINTUM] MomentumPhase: zero high/low for IER baseline");
            return false;
         }
         baselineSum += (h - l);
      }
      double baselineAvgRange = baselineSum / 5.0;

      double ier;
      if(baselineAvgRange == 0.0)
         ier = 1.0;
      else
         ier = recentAvgRange / baselineAvgRange;

      ier = MathMax(0.1, MathMin(5.0, ier));

      // ---------------------------------------------------------
      // 3. acceleration
      // ---------------------------------------------------------
      double prevNpv = m_prev_npv[m_prev_idx];
      m_prev_npv[m_prev_idx] = npv;
      m_prev_idx = (m_prev_idx + 1) % 3;

      double acceleration;
      if(m_callCount <= 2)
         acceleration = 0.0;
      else
         acceleration = npv - prevNpv;

      acceleration = MathMax(-2.0, MathMin(2.0, acceleration));

      // ---------------------------------------------------------
      // 4. jerk
      // ---------------------------------------------------------
      double jerk;
      if(m_callCount <= 3)
         jerk = 0.0;
      else
         jerk = acceleration - m_prevAcceleration;

      jerk = MathMax(-2.0, MathMin(2.0, jerk));

      m_prevAcceleration = acceleration;

      // ---------------------------------------------------------
      // 5. momentum phase
      // ---------------------------------------------------------
      ENUM_MOMENTUM_PHASE phase;
      if(ier > 2.5 && MathAbs(acceleration) < 0.05)
         phase = PHASE_EXHAUSTED;
      else if(acceleration > 0.02)
         phase = PHASE_WAXING;
      else if(acceleration < -0.02)
         phase = PHASE_WANING;
      else
         phase = PHASE_NEUTRAL;

      // ---------------------------------------------------------
      // 6. store results
      // ---------------------------------------------------------
      m_momentum.phase        = phase;
      m_momentum.npv          = npv;
      m_momentum.ier          = ier;
      m_momentum.acceleration = acceleration;
      m_momentum.jerk         = jerk;

      PrintFormat("[LEINTUM] Momentum: phase=%d NPV=%.3f IER=%.3f acc=%.3f",
                  m_momentum.phase, m_momentum.npv, m_momentum.ier, m_momentum.acceleration);

      return true;
   }

   // ------------------------------------------------------------
   // GetMomentum
   // ------------------------------------------------------------
   SMomentum GetMomentum()
   {
      return m_momentum;
   }
};
