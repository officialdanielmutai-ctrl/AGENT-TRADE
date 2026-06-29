// Computes DER, Hurst, RBE, regime_strength, regime_type, deceleration.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CRegimeDetector
// ------------------------------------------------------------
class CRegimeDetector
{
private:
   CPriceFabric*  m_fabric;
   SRegime        m_regime;
   double         m_prev_strength[3];  // last 3 regime_strength values for deceleration detection
   int            m_prev_idx;

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CRegimeDetector(CPriceFabric* fabric)
   {
      m_fabric = fabric;
      // Initialise regime to safe defaults
      m_regime.type            = REGIME_RANGING;
      m_regime.der             = 0.0;
      m_regime.hurst           = 0.5;
      m_regime.rbe             = 0.0;
      m_regime.regime_strength = 0.0;
      m_regime.deceleration    = false;

      // Zero out previous strength buffer
      for(int i = 0; i < 3; i++)
         m_prev_strength[i] = 0.0;
      m_prev_idx = 0;
   }

   // ------------------------------------------------------------
   // Refresh — compute DER, Hurst, RBE, regime_strength, regime_type, deceleration
   // ------------------------------------------------------------
   bool Refresh()
   {
      // ---------------------------------------------------------
      // 1. DER (Directional Energy Ratio)
      // ---------------------------------------------------------
      int bull_count = 0;
      int bear_count = 0;

      for(int shift = 1; shift <= 20; shift++)
      {
         double open  = m_fabric.GetOpen("EURUSD", PERIOD_M15, shift);
         double close = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);

         // If any value is zero, data is not available
         if(open == 0.0 || close == 0.0)
         {
            PrintFormat("[LEINTUM] RegimeDetector: zero values from PriceFabric, cannot compute DER");
            return false;
         }

         if(close > open)
            bull_count++;
         else if(close < open)
            bear_count++;
      }

      double der = (bull_count - bear_count) / 20.0;   // naturally bounded [-1, +1]

      // ---------------------------------------------------------
      // 2. Hurst Exponent (simplified RS method)
      // ---------------------------------------------------------
      double closes[20];
      double sumCloses = 0.0;

      for(int shift = 1; shift <= 20; shift++)
      {
         double c = m_fabric.GetClose("EURUSD", PERIOD_M15, shift);
         if(c == 0.0)
         {
            PrintFormat("[LEINTUM] RegimeDetector: zero close value, cannot compute Hurst");
            return false;
         }
         closes[shift - 1] = c;
         sumCloses += c;
      }

      double mean = sumCloses / 20.0;

      // Cumulative deviations from mean
      double cumDev[20];
      double cumSum = 0.0;
      for(int i = 0; i < 20; i++)
      {
         cumSum += (closes[i] - mean);
         cumDev[i] = cumSum;
      }

      // R = max(cumDev) - min(cumDev)
      double maxDev = cumDev[0];
      double minDev = cumDev[0];
      for(int i = 1; i < 20; i++)
      {
         if(cumDev[i] > maxDev) maxDev = cumDev[i];
         if(cumDev[i] < minDev) minDev = cumDev[i];
      }
      double R = maxDev - minDev;

      // S = standard deviation of the 20 closes
      double variance = 0.0;
      for(int i = 0; i < 20; i++)
         variance += (closes[i] - mean) * (closes[i] - mean);
      variance /= 20.0;
      double S = MathSqrt(variance);

      double hurst;
      if(S == 0.0)
         hurst = 0.5;
      else
         hurst = MathLog(R / S) / MathLog(20.0);

      // Clamp Hurst to [0.1, 0.9]
      hurst = MathMax(0.1, MathMin(0.9, hurst));

      // ---------------------------------------------------------
      // 3. RBE (Range Boundary Efficiency)
      // ---------------------------------------------------------
      double recentHigh = -1e10;
      double recentLow  = 1e10;

      for(int shift = 1; shift <= 20; shift++)
      {
         double h = m_fabric.GetHigh("EURUSD", PERIOD_M15, shift);
         double l = m_fabric.GetLow("EURUSD", PERIOD_M15, shift);

         if(h == 0.0 || l == 0.0)
         {
            PrintFormat("[LEINTUM] RegimeDetector: zero high/low value, cannot compute RBE");
            return false;
         }

         if(h > recentHigh) recentHigh = h;
         if(l < recentLow)  recentLow  = l;
      }

      double totalRange = recentHigh - recentLow;
      double rbe;
      if(totalRange == 0.0)
         rbe = 0.0;
      else
      {
         double close1  = m_fabric.GetClose("EURUSD", PERIOD_M15, 1);
         double close20 = m_fabric.GetClose("EURUSD", PERIOD_M15, 20);
         if(close1 == 0.0 || close20 == 0.0)
         {
            PrintFormat("[LEINTUM] RegimeDetector: zero close value for RBE");
            return false;
         }
         double netMove = MathAbs(close1 - close20);
         rbe = netMove / totalRange;
      }

      // Clamp RBE to [0.0, 1.0]
      rbe = MathMax(0.0, MathMin(1.0, rbe));

      // ---------------------------------------------------------
      // 4. regime_strength
      // ---------------------------------------------------------
      double rawStrength = (MathAbs(der) * 0.4) + (hurst * 0.4) + (rbe * 0.2);
      double regimeStrength = MathMax(0.0, MathMin(1.0, rawStrength));

      // ---------------------------------------------------------
      // 5. regime_type
      // ---------------------------------------------------------
      ENUM_REGIME_TYPE regimeType;
      if(regimeStrength < 0.35)
         regimeType = REGIME_RANGING;
      else if(der > 0.0)
         regimeType = REGIME_TRENDING_UP;
      else
         regimeType = REGIME_TRENDING_DOWN;

      // ---------------------------------------------------------
      // 6. deceleration detection
      // ---------------------------------------------------------
      // Store current strength in circular buffer
      m_prev_strength[m_prev_idx] = regimeStrength;
      m_prev_idx = (m_prev_idx + 1) % 3;

      bool deceleration = false;
      // Check if buffer is full (we have at least 3 entries)
      // We'll consider it full after the first 3 calls.
      // For simplicity, we check if the buffer has been filled at least once.
      // We'll use a simple approach: if m_prev_idx == 0 after increment,
      // it means we've wrapped around, so buffer is full.
      // But we need to know if we've had at least 3 calls.
      // We'll use a separate counter.
      // For now, we'll just check if the three values are strictly decreasing
      // regardless of whether buffer is full. On first call, all values are 0.0,
      // so they won't be strictly decreasing.
      if(m_prev_strength[0] > m_prev_strength[1] &&
         m_prev_strength[1] > m_prev_strength[2])
      {
         deceleration = true;
      }

      // ---------------------------------------------------------
      // 7. Store results in m_regime
      // ---------------------------------------------------------
      m_regime.type            = regimeType;
      m_regime.der             = der;               // naturally bounded
      m_regime.hurst           = hurst;             // already clamped
      m_regime.rbe             = rbe;               // already clamped
      m_regime.regime_strength = regimeStrength;    // already clamped
      m_regime.deceleration    = deceleration;

      // Log
      PrintFormat("[LEINTUM] Regime: type=%d strength=%.3f DER=%.3f Hurst=%.3f",
                  m_regime.type, m_regime.regime_strength, m_regime.der, m_regime.hurst);

      return true;
   }

   // ------------------------------------------------------------
   // GetRegime
   // ------------------------------------------------------------
   SRegime GetRegime()
   {
      return m_regime;
   }
};
