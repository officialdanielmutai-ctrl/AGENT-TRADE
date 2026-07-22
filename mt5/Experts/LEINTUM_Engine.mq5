// Main Expert Advisor. Orchestrator only — no formula logic.
// Phase 4: Full execution loop — entry, management, event monitoring.

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
#include <LEINTUMEngine/BridgeClient.mqh>
#include <LEINTUMEngine/DecisionExecutor.mqh>
#include <LEINTUMEngine/EventTriggerMonitor.mqh>

// ------------------------------------------------------------
// Input parameters
// ------------------------------------------------------------
input double InpDailyLossLimit   = 50.0;    // Daily loss limit (account currency)
input double InpBaseLotSize      = 0.01;    // Base lot size
input double InpMaxSpreadPoints  = 30.0;    // Max spread in points
input double InpRiskPercent      = 0.005;   // Risk per trade (0.5%)
input int    InpCooldownBars     = 12;      // Bars to wait after any trade entry

// ------------------------------------------------------------
// Global module instances
// ------------------------------------------------------------
CPriceFabric*          g_fabric;
CSessionProfile*       g_session;
CRegimeDetector*       g_regime;
CMomentumPhase*        g_momentum;
CConditionAssessor*    g_condition;
CContextAnalyzer*      g_context;
CCorrelationMonitor*   g_correlation;
CTradeHealthMonitor*   g_health;
CMarketStatePackager*  g_packager;
CRiskManager*          g_risk;
CBridgeClient*         g_bridge;
CDecisionExecutor*     g_executor;
CEventTriggerMonitor*  g_events;

// ------------------------------------------------------------
// Runtime state
// ------------------------------------------------------------
datetime g_last_bar_time      = 0;
int      g_bars_since_trade   = 9999;    // cooldown counter (server-side)
int      g_current_bar_number = 0;
datetime g_day_start          = 0;       // for daily loss reset

// ------------------------------------------------------------
// OnInit
// ------------------------------------------------------------
int OnInit()
{
   g_fabric      = new CPriceFabric();
   g_session     = new CSessionProfile(g_fabric);
   g_regime      = new CRegimeDetector(g_fabric);
   g_momentum    = new CMomentumPhase(g_fabric);
   g_condition   = new CConditionAssessor(g_fabric);
   g_context     = new CContextAnalyzer(g_fabric);
   g_correlation = new CCorrelationMonitor(g_fabric);
   g_health      = new CTradeHealthMonitor(g_fabric);
   g_risk        = new CRiskManager(InpDailyLossLimit, InpBaseLotSize, InpMaxSpreadPoints);
   g_bridge      = new CBridgeClient(8000);
   g_packager    = new CMarketStatePackager();
   g_executor    = new CDecisionExecutor(g_risk, InpRiskPercent);
   g_events      = new CEventTriggerMonitor(g_fabric);

   g_day_start   = iTime("EURUSD", PERIOD_D1, 0);

   Print("[LEINTUM] EA initialised — Phase 4 (Execution + Management)");
   return INIT_SUCCEEDED;
}

// ------------------------------------------------------------
// OnDeinit
// ------------------------------------------------------------
void OnDeinit(const int reason)
{
   delete g_fabric;
   delete g_session;
   delete g_regime;
   delete g_momentum;
   delete g_condition;
   delete g_context;
   delete g_correlation;
   delete g_health;
   delete g_risk;
   delete g_bridge;
   delete g_packager;
   delete g_executor;
   delete g_events;

   Print("[LEINTUM] EA deinitialised");
}

// ------------------------------------------------------------
// OnTick — runs on every price tick
// ------------------------------------------------------------
void OnTick()
{
   // ── Daily loss reset ──────────────────────────────────────
   datetime dayNow = iTime("EURUSD", PERIOD_D1, 0);
   if(dayNow != g_day_start)
   {
      g_risk.ResetDailyLoss();
      g_day_start = dayNow;
      Print("[LEINTUM] Daily loss counter reset for new day");
   }

   // ── Refresh formula data ──────────────────────────────────
   if(!g_fabric.Refresh())     { Print("[LEINTUM] PriceFabric failed");     return; }

   // ── Intra-bar event check (every tick) ───────────────────
   // Build a lightweight state snapshot for the event monitor.
   // Full state is built later only on new bars.
   {
      SMarketState evtState;
      evtState.bar_number        = g_current_bar_number;
      evtState.regime            = g_regime.GetRegime();
      evtState.momentum          = g_momentum.GetMomentum();
      evtState.htf               = g_context.GetHTF();
      evtState.current_bar.volume     = (double)g_fabric.GetVolume("EURUSD", PERIOD_M15, 0);
      evtState.current_bar.volume_avg = (double)g_fabric.GetVolume("EURUSD", PERIOD_M15, 1);

      // Build position state for event checks
      evtState.position.exists = false;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(PositionGetSymbol(i) == "EURUSD")
         {
            evtState.position.exists        = true;
            evtState.position.ticket        = PositionGetInteger(POSITION_TICKET);
            evtState.position.direction     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
            evtState.position.entry_price   = PositionGetDouble(POSITION_PRICE_OPEN);
            evtState.position.current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            evtState.position.sl            = PositionGetDouble(POSITION_SL);
            evtState.position.health_score  = g_health.GetScore();
            double slPips = MathAbs(evtState.position.entry_price - evtState.position.sl) / _Point / 10.0;
            evtState.position.pips_at_risk  = slPips;
            break;
         }
      }

      string alertJson = "";
      string evtType   = g_events.CheckAll(evtState, alertJson);
      if(evtType != "" && alertJson != "")
      {
         PrintFormat("[LEINTUM] Event fired: %s", evtType);
         string alertResponse = "";
         g_bridge.SendAlert(alertJson, alertResponse);
      }
   }

   // ── New bar detection ─────────────────────────────────────
   datetime currentBarTime = iTime("EURUSD", PERIOD_M15, 0);
   if(currentBarTime == g_last_bar_time)
      return;
   g_last_bar_time = currentBarTime;
   g_bars_since_trade++;
   g_events.ResetBarAlerts();

   // ── Run remaining formula modules (new bar only) ──────────
   if(!g_session.Refresh())    { Print("[LEINTUM] SessionProfile failed");    return; }
   if(!g_regime.Refresh())     { Print("[LEINTUM] RegimeDetector failed");    return; }
   if(!g_momentum.Refresh())   { Print("[LEINTUM] MomentumPhase failed");     return; }
   if(!g_condition.Refresh())  { Print("[LEINTUM] ConditionAssessor failed"); return; }
   if(!g_context.Refresh())    { Print("[LEINTUM] ContextAnalyzer failed");   return; }
   if(!g_correlation.Refresh()){ Print("[LEINTUM] CorrelationMonitor failed"); return; }

   // ── Build SMarketState ────────────────────────────────────
   SMarketState state;
   state.bar_number = g_fabric.GetCurrentBarNumber();
   g_current_bar_number = state.bar_number;
   state.session    = g_session.GetState();
   state.regime     = g_regime.GetRegime();
   state.momentum   = g_momentum.GetMomentum();
   state.condition  = g_condition.GetCondition();
   state.htf        = g_context.GetHTF();
   g_correlation.GetPairs(state.cross_pairs);

   // Build current_bar anatomy
   double open   = g_fabric.GetOpen("EURUSD",  PERIOD_M15, 1);
   double high   = g_fabric.GetHigh("EURUSD",  PERIOD_M15, 1);
   double low    = g_fabric.GetLow("EURUSD",   PERIOD_M15, 1);
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
   state.current_bar.body_ratio       = (range > 0) ? MathAbs(close - open) / range : 0;
   state.current_bar.upper_wick_ratio = (range > 0) ? (high - MathMax(open, close)) / range : 0;
   state.current_bar.lower_wick_ratio = (range > 0) ? (MathMin(open, close) - low) / range : 0;
   state.current_bar.volume           = vol;
   state.current_bar.volume_avg       = volAvg;

   // Build position state
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

   // ── Emergency close check (independent of LLM) ───────────
   if(g_health.IsEmergency() && state.position.exists)
   {
      Print("[LEINTUM] Health emergency — forcing position close");
      g_executor.EmergencyClose(state.position);
      g_bars_since_trade = 0;
      return;
   }

   // Build macro_calendar (placeholder — Phase 5 will wire live API)
   state.macro_calendar.event_name     = "PLACEHOLDER";
   state.macro_calendar.impact         = "low";
   state.macro_calendar.minutes_to_next = 999;

   // ── Serialize + POST to Bridge ────────────────────────────
   string payload  = g_packager.Serialize(state);
   PrintFormat("[LEINTUM] Payload: %s", payload);

   string response = "";
   bool   sent     = g_bridge.SendHeartbeat(payload, response);

   if(!sent || response == "")
   {
      Print("[LEINTUM] Bridge unreachable — HOLD this bar");
      return;
   }

   PrintFormat("[LEINTUM] LLM Response: %s", response);

   // ── Parse LLM response ────────────────────────────────────
   SDecision dec;
   if(!g_executor.ParseResponse(response, dec))
   {
      Print("[LEINTUM] Failed to parse LLM response — HOLD");
      return;
   }

   // ── Register watch levels from LLM response ───────────────
   // Extract the watch array string and pass to event monitor
   int watchStart = StringFind(response, "\"watch\":");
   if(watchStart >= 0)
      g_events.RegisterWatchLevels(StringSubstr(response, watchStart));

   // ── Execute decision ──────────────────────────────────────
   bool positionOpen = state.position.exists;
   double spread     = SymbolInfoInteger("EURUSD", SYMBOL_SPREAD) * _Point;

   if(!positionOpen)
   {
      // No position — check for entry
      bool cooldownActive = (g_bars_since_trade < InpCooldownBars);
      if(cooldownActive)
      {
         PrintFormat("[LEINTUM] Cooldown active (%d/%d bars). HOLD.",
                     g_bars_since_trade, InpCooldownBars);
      }
      else if(dec.action == ACTION_OPEN_BUY || dec.action == ACTION_OPEN_SELL)
      {
         long ticket = g_executor.OpenTrade(dec, spread);
         if(ticket > 0)
         {
            g_bars_since_trade = 0;
            // Record a nominal loss amount for daily tracker (will be updated on close)
            // Here we just flag that a trade was opened
         }
      }
   }
   else
   {
      // Position is open — apply management
      g_executor.ManageTrade(dec, state.position);

      // If the position was just closed by the LLM (CLOSE_ALL response),
      // reset the cooldown
      if(dec.action == ACTION_CLOSE_ALL)
         g_bars_since_trade = 0;
   }

   Print("[LEINTUM] Bar complete");
}
