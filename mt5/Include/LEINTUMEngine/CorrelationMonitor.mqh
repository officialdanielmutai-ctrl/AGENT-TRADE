// Computes state, direction, and velocity reversal for 6 cross pairs.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// CCorrelationMonitor
// ------------------------------------------------------------
class CCorrelationMonitor
{
private:
   CPriceFabric*  m_fabric;
   SCrossPair     m_pairs[6];
   string         m_symbols[6];

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CCorrelationMonitor(CPriceFabric* fabric)
   {
      m_fabric = fabric;

      // Initialise symbol list
      m_symbols[0] = "GBPUSD";
      m_symbols[1] = "USDCHF";
      m_symbols[2] = "USDJPY";
      m_symbols[3] = "AUDUSD";
      m_symbols[4] = "XAUUSD";
      m_symbols[5] = "USOIL";

      // Initialise pairs to safe defaults
      for(int i = 0; i < 6; i++)
      {
         m_pairs[i].symbol           = m_symbols[i];
         m_pairs[i].state            = PAIR_DEAD;
         m_pairs[i].direction        = 0;
         m_pairs[i].velocity_reversal = false;
      }
   }

   // ------------------------------------------------------------
   // Refresh — compute state, direction, velocity_reversal for each pair
   // ------------------------------------------------------------
   bool Refresh()
   {
      for(int i = 0; i < 6; i++)
      {
         string sym = m_symbols[i];

         // ---------------------------------------------------------
         // 1. state (ACTIVE / COASTING / DEAD)
         // ---------------------------------------------------------
         double avgRange = 0.0;
         for(int shift = 1; shift <= 10; shift++)
         {
            double h = m_fabric.GetHigh(sym, PERIOD_M15, shift);
            double l = m_fabric.GetLow(sym, PERIOD_M15, shift);
            if(h == 0.0 || l == 0.0)
            {
               PrintFormat("[LEINTUM] CorrelationMonitor: zero high/low for %s at shift %d", sym, shift);
               return false;
            }
            avgRange += (h - l);
         }
         avgRange /= 10.0;

         double baselineRange = 0.0;
         for(int shift = 11; shift <= 20; shift++)
         {
            double h = m_fabric.GetHigh(sym, PERIOD_M15, shift);
            double l = m_fabric.GetLow(sym, PERIOD_M15, shift);
            if(h == 0.0 || l == 0.0)
            {
               PrintFormat("[LEINTUM] CorrelationMonitor: zero high/low for %s at shift %d", sym, shift);
               return false;
            }
            baselineRange += (h - l);
         }
         baselineRange /= 10.0;

         ENUM_PAIR_STATE state;
         if(baselineRange == 0.0)
            state = PAIR_DEAD;
         else
         {
            double ratio = avgRange / baselineRange;
            if(ratio > 1.2)
               state = PAIR_ACTIVE;
            else if(ratio >= 0.6)
               state = PAIR_COASTING;
            else
               state = PAIR_DEAD;
         }

         // ---------------------------------------------------------
         // 2. direction
         // ---------------------------------------------------------
         int direction;
         if(state == PAIR_DEAD)
            direction = 0;
         else
         {
            double close1  = m_fabric.GetClose(sym, PERIOD_M15, 1);
            double close10 = m_fabric.GetClose(sym, PERIOD_M15, 10);
            if(close1 == 0.0 || close10 == 0.0)
            {
               PrintFormat("[LEINTUM] CorrelationMonitor: zero close for %s direction", sym);
               return false;
            }

            if(close1 > close10)
               direction = +1;
            else if(close1 < close10)
               direction = -1;
            else
               direction = 0;
         }

         // ---------------------------------------------------------
         // 3. velocity_reversal
         // ---------------------------------------------------------
         bool velocityReversal = false;
         if(state != PAIR_DEAD)
         {
            double close1  = m_fabric.GetClose(sym, PERIOD_M15, 1);
            double close5  = m_fabric.GetClose(sym, PERIOD_M15, 5);
            double close6  = m_fabric.GetClose(sym, PERIOD_M15, 6);
            double close10 = m_fabric.GetClose(sym, PERIOD_M15, 10);

            if(close1 == 0.0 || close5 == 0.0 || close6 == 0.0 || close10 == 0.0)
            {
               PrintFormat("[LEINTUM] CorrelationMonitor: zero close for %s reversal", sym);
               return false;
            }

            int recentDir = (close1 > close5) ? +1 : -1;
            int olderDir  = (close6 > close10) ? +1 : -1;

            velocityReversal = (recentDir != olderDir);
         }

         // ---------------------------------------------------------
         // Store results
         // ---------------------------------------------------------
         m_pairs[i].symbol           = sym;
         m_pairs[i].state            = state;
         m_pairs[i].direction        = direction;
         m_pairs[i].velocity_reversal = velocityReversal;

         // Log
         PrintFormat("[LEINTUM] CrossPair %s: state=%d dir=%d reversal=%s",
                     m_pairs[i].symbol,
                     m_pairs[i].state,
                     m_pairs[i].direction,
                     m_pairs[i].velocity_reversal ? "true" : "false");
      }

      return true;
   }

   // ------------------------------------------------------------
   // GetPairs — copy m_pairs into output array
   // ------------------------------------------------------------
   void GetPairs(SCrossPair &pairs[])
   {
      ArrayResize(pairs, 6);
      for(int i = 0; i < 6; i++)
         pairs[i] = m_pairs[i];
   }
};
