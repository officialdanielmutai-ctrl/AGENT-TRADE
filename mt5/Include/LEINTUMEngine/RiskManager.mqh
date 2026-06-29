// Conviction gate, spread gate, daily loss limit, lot sizing.
// This is the only module that enforces hard entry restrictions.

#include "Defines.mqh"

// ------------------------------------------------------------
// CRiskManager
// ------------------------------------------------------------
class CRiskManager
{
private:
   double   m_daily_loss_limit;   // in account currency
   double   m_daily_loss_so_far;  // running daily loss
   double   m_base_lot_size;      // from input params
   double   m_max_spread_points;  // max allowed spread in points

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CRiskManager(double dailyLossLimit, double baseLotSize, double maxSpreadPoints)
   {
      m_daily_loss_limit   = dailyLossLimit;
      m_daily_loss_so_far  = 0.0;
      m_base_lot_size      = baseLotSize;
      m_max_spread_points  = maxSpreadPoints;
   }

   // ------------------------------------------------------------
   // ResetDailyLoss — call at start of each new day
   // ------------------------------------------------------------
   void ResetDailyLoss()
   {
      m_daily_loss_so_far = 0.0;
   }

   // ------------------------------------------------------------
   // RecordLoss — add to daily loss tracker
   // ------------------------------------------------------------
   void RecordLoss(double amount)
   {
      m_daily_loss_so_far += amount;
   }

   // ------------------------------------------------------------
   // CanEnter — check all entry gates
   // ------------------------------------------------------------
   bool CanEnter(double conviction, double currentSpreadPoints)
   {
      // 1. Conviction gate
      if(conviction < LEINTUM_MIN_CONVICTION)
      {
         PrintFormat("[LEINTUM] RiskManager: conviction %.3f below minimum %.3f",
                     conviction, LEINTUM_MIN_CONVICTION);
         return false;
      }

      // 2. Spread gate
      if(currentSpreadPoints > m_max_spread_points)
      {
         PrintFormat("[LEINTUM] RiskManager: spread %.1f exceeds limit %.1f",
                     currentSpreadPoints, m_max_spread_points);
         return false;
      }

      // 3. Max positions gate
      if(PositionsTotal() >= LEINTUM_MAX_POSITIONS)
      {
         PrintFormat("[LEINTUM] RiskManager: max positions reached (%d)",
                     LEINTUM_MAX_POSITIONS);
         return false;
      }

      // 4. Daily loss limit gate
      if(IsDailyLimitHit())
      {
         PrintFormat("[LEINTUM] RiskManager: daily loss limit hit");
         return false;
      }

      return true;
   }

   // ------------------------------------------------------------
   // ComputeLotSize — risk-based lot sizing
   // ------------------------------------------------------------
   double ComputeLotSize(double slPips, double riskPercent)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * riskPercent;
      double lot = riskAmount / (slPips * 10.0);   // simplified for EURUSD

      // Clamp lot to [0.01, 10.0]
      lot = MathMax(0.01, MathMin(10.0, lot));

      // If calculation fails (e.g., slPips == 0), return base lot size
      if(lot <= 0.0 || !MathIsValidNumber(lot))
         lot = m_base_lot_size;

      return lot;
   }

   // ------------------------------------------------------------
   // IsDailyLimitHit
   // ------------------------------------------------------------
   bool IsDailyLimitHit()
   {
      return (m_daily_loss_so_far >= m_daily_loss_limit);
   }
};
