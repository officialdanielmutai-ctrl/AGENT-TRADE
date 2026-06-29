// Main Expert Advisor. Orchestrator only — no formula logic.
// Phase 2: Formula loop only. No Bridge calls. No execution.

#include <LEINTUMEngine/Defines.mqh>
#include <LEINTUMEngine/PriceFabric.mqh>
#include <LEINTUMEngine/SessionProfile.mqh>
#include <LEINTUMEngine/RegimeDetector.mqh>
#include <LEINTUMEngine/MomentumPhase.mqh>
#include <LEINTUMEngine/ConditionAssessor.mqh>
#include <LEINTUMEngine/ContextAnalyzer.mqh>
#include <LEINTUMEngine/CorrelationMonitor.mqh>
#include <LEINTUMEngine/TradeHealthMonitor.mqh>
#include <LEINTUMEngine/MarketStatePackager.mqh>
#include <LEINTUMEngine/RiskManager.mqh>

// ------------------------------------------------------------
// Input parameters
// ------------------------------------------------------------
input double InpDailyLossLimit   = 50.0;   // Daily loss limit (account currency)
input double InpBaseLotSize      = 0.01;   // Base lot size
input double InpMaxSpreadPoints  = 30.0;   // Max spread in points
input double InpRiskPercent      = 0.005;  // Risk per trade (0.5%)

// ------------------------------------------------------------
// Global module instances (pointers)
// ------------------------------------------------------------
CPriceFabric*         g_fabric;
CSessionProfile*      g_session;
CRegimeDetector*      g_regime;
CMomentumPhase*       g_momentum;
CConditionAssessor*   g_condition;
CContextAnalyzer*     g_context;
CCorrelationMonitor*  g_correlation;
CTradeHealthMonitor*  g_health;
CMarketStatePackager* g_packager;
CRiskManager*         g_risk;

// ------------------------------------------------------------
// Track last bar time
// ------------------------------------------------------------
datetime g_last_bar_time = 0;

// ------------------------------------------------------------
// OnInit
// ------------------------------------------------------------
int OnInit()
{
   // Instantiate all modules
   g_fabric      = new CPriceFabric();
   g_session     = new CSessionProfile(g_fabric);
   g_regime      = new CRegimeDetector(g_fabric);
   g_momentum    = new CMomentumPhase(g_fabric);
   g_condition   = new CConditionAssessor(g_fabric);
   g_context     = new CContextAnalyzer(g_fabric);
   g_correlation = new CCorrelationMonitor(g_fabric);
   g_health      = new CTradeHealthMonitor(g_fabric);
   g_risk        = new CRiskManager(InpDailyLossLimit, InpBaseLotSize, InpMaxSpreadPoints);
   g_packager    = new CMarketStatePackager();

   Print("[LEINTUM] EA initialised");
   return INIT_SUCCEEDED;
}

// ------------------------------------------------------------
// OnDeinit
// ------------------------------------------------------------
void OnDeinit(const int reason)
{
   // Delete all module pointers
   delete g_fabric;
   delete g_session;
   delete g_regime;
   delete g_momentum;
   delete g_condition;
   delete g_context;
   delete g_correlation;
   delete g_health;
   delete g_risk;
   delete g_packager;

   Print("[LEINTUM] EA deinitialised");
}

// ------------------------------------------------------------
// OnTick
// ------------------------------------------------------------
void OnTick()
{
   // Detect new M15 bar
   datetime currentBarTime = iTime("EURUSD", PERIOD_M15, 0);
   if(currentBarTime == g_last_bar_time)
      return;
   g_last_bar_time = currentBarTime;

   // Call modules in sequence, return on any failure
   if(!g_fabric.Refresh())
   {
      Print("[LEINTUM] PriceFabric failed");
      return;
   }
   if(!g_session.Refresh())
   {
      Print("[LEINTUM] SessionProfile failed");
      return;
   }
   if(!g_regime.Refresh())
   {
      Print("[LEINTUM] RegimeDetector failed");
      return;
   }
   if(!g_momentum.Refresh())
   {
      Print("[LEINTUM] MomentumPhase failed");
      return;
   }
   if(!g_condition.Refresh())
   {
      Print("[LEINTUM] ConditionAssessor failed");
      return;
   }
   if(!g_context.Refresh())
   {
      Print("[LEINTUM] ContextAnalyzer failed");
      return;
   }
   if(!g_correlation.Refresh())
   {
      Print("[LEINTUM] CorrelationMonitor failed");
      return;
   }

   // Build SMarketState
   SMarketState state;
   state.bar_number = g_fabric.GetCurrentBarNumber();
   state.session    = g_session.GetState();
   state.regime     = g_regime.GetRegime();
   state.momentum   = g_momentum.GetMomentum();
   state.condition  = g_condition.GetCondition();
   state.htf        = g_context.GetHTF();
   g_correlation.GetPairs(state.cross_pairs);

   // Build current_bar anatomy
   double open   = g_fabric.GetOpen("EURUSD", PERIOD_M15, 1);
   double high   = g_fabric.GetHigh("EURUSD", PERIOD_M15, 1);
   double low    = g_fabric.GetLow("EURUSD", PERIOD_M15, 1);
   double close  = g_fabric.GetClose("EURUSD", PERIOD_M15, 1);
   double vol    = (double)g_fabric.GetVolume("EURUSD", PERIOD_M15, 1);
   double volAvg = 0.0;
   for(int i = 1; i <= 20; i++)
      volAvg += (double)g_fabric.GetVolume("EURUSD", PERIOD_M15, i);
   volAvg /= 20.0;
   double range = high - low;
   state.current_bar.open             = open;
   state.current_bar.high             = high;
   state.current_bar.low              = low;
   state.current_bar.close            = close;
   state.current_bar.body_ratio       = (range > 0) ? MathAbs(close-open)/range : 0;
   state.current_bar.upper_wick_ratio = (range > 0) ? (high - MathMax(open,close))/range : 0;
   state.current_bar.lower_wick_ratio = (range > 0) ? (MathMin(open,close) - low)/range : 0;
   state.current_bar.volume           = vol;
   state.current_bar.volume_avg       = volAvg;

   // Build position state (check if any EURUSD position is open)
   state.position.exists = false;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == "EURUSD")
      {
         state.position.exists        = true;
         state.position.ticket        = PositionGetInteger(POSITION_TICKET);
         state.position.direction     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         state.position.entry_price   = PositionGetDouble(POSITION_PRICE_OPEN);
         state.position.current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         state.position.sl            = PositionGetDouble(POSITION_SL);
         state.position.unrealised_pnl = PositionGetDouble(POSITION_PROFIT);
         double slPips = MathAbs(state.position.entry_price - state.position.sl) / _Point / 10.0;
         state.position.pips_at_risk  = slPips;
         break;
      }
   }

   // Compute health score
   SRegime  reg = state.regime;
   SMomentum mom = state.momentum;
   state.position.health_score = g_health.Compute(state.position, reg, mom);

   // Build macro_calendar (hardcoded placeholder for Phase 2)
   state.macro_calendar.event_name    = "PLACEHOLDER";
   state.macro_calendar.impact        = "low";
   state.macro_calendar.minutes_to_next = 999;

   // Serialize and print payload
   string payload = g_packager.Serialize(state);
   PrintFormat("[LEINTUM] Payload: %s", payload);
   Print("[LEINTUM] Bar complete — Bridge not yet connected (Phase 2)");
}
