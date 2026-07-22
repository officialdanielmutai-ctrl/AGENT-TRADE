// Monitors 8 intra-bar structural events that trigger an immediate
// /alert POST to the Bridge without waiting for the next bar close.
// Called from OnTick() on every tick, not just on new bars.

#include "Defines.mqh"
#include "PriceFabric.mqh"

// ------------------------------------------------------------
// Event type strings — match the LLM watch condition vocabulary
// ------------------------------------------------------------
#define EVT_REGIME_CHANGE       "REGIME_CHANGE"
#define EVT_HEALTH_CRITICAL     "HEALTH_CRITICAL"
#define EVT_MOMENTUM_FLIP       "MOMENTUM_FLIP"
#define EVT_PRICE_LEVEL_BREACH  "PRICE_LEVEL_BREACH"
#define EVT_VOLUME_SPIKE        "VOLUME_SPIKE"
#define EVT_HTF_DIVERGENCE      "HTF_DIVERGENCE"
#define EVT_SL_PROXIMITY        "SL_PROXIMITY"
#define EVT_DRAWDOWN_LIMIT      "DRAWDOWN_LIMIT"

// ------------------------------------------------------------
// CEventTriggerMonitor
// ------------------------------------------------------------
class CEventTriggerMonitor
{
private:
   CPriceFabric*      m_fabric;

   // State snapshots — used to detect changes between ticks/bars
   ENUM_REGIME_TYPE   m_last_regime;
   int                m_last_npv_sign;       // +1 / -1 / 0
   int                m_last_htf_sign;       // sign of htf.consensus
   bool               m_health_alert_sent;   // one alert per health dip
   bool               m_volume_alert_sent;   // one alert per spike
   bool               m_sl_alert_sent;       // one alert per proximity

   // Watch price levels registered from the LLM watch array
   double             m_watch_levels[8];
   int                m_watch_level_count;
   bool               m_level_breached[8];   // prevent re-firing

   // --------------------------------------------------------
   // Helper: build a minimal alert JSON payload
   // --------------------------------------------------------
   string BuildAlertJson(const string eventType, const string detail,
                         double currentPrice, int barNumber)
   {
      string j = "{";
      j += "\"event\":\"" + eventType + "\",";
      j += "\"detail\":\"" + detail + "\",";
      j += "\"price\":" + StringFormat("%.5f", currentPrice) + ",";
      j += "\"bar_number\":" + IntegerToString(barNumber);
      j += "}";
      return j;
   }

public:
   // --------------------------------------------------------
   // Constructor
   // --------------------------------------------------------
   CEventTriggerMonitor(CPriceFabric* fabric)
   {
      m_fabric             = fabric;
      m_last_regime        = REGIME_RANGING;
      m_last_npv_sign      = 0;
      m_last_htf_sign      = 0;
      m_health_alert_sent  = false;
      m_volume_alert_sent  = false;
      m_sl_alert_sent      = false;
      m_watch_level_count  = 0;
      ArrayInitialize(m_watch_levels, 0.0);
      ArrayInitialize(m_level_breached, false);
   }

   // --------------------------------------------------------
   // RegisterWatchLevels — called after each LLM response.
   // Parses watch price levels from the LLM watch[] array.
   // Only numeric tokens (e.g. "1.16525") are registered.
   // --------------------------------------------------------
   void RegisterWatchLevels(const string watchJson)
   {
      m_watch_level_count = 0;
      ArrayInitialize(m_level_breached, false);

      int pos = 0;
      int len = StringLen(watchJson);
      while(pos < len && m_watch_level_count < 8)
      {
         // Find next quoted string in the array
         int q1 = StringFind(watchJson, "\"", pos);
         if(q1 < 0) break;
         int q2 = StringFind(watchJson, "\"", q1 + 1);
         if(q2 < 0) break;
         string token = StringSubstr(watchJson, q1 + 1, q2 - q1 - 1);
         pos = q2 + 1;

         // Check if this token looks like a price (starts with digit or '1.')
         double val = StringToDouble(token);
         if(val > 0.5 && val < 5.0)   // EURUSD range sanity check
         {
            m_watch_levels[m_watch_level_count] = val;
            m_watch_level_count++;
         }
      }

      if(m_watch_level_count > 0)
         PrintFormat("[LEINTUM] EventMonitor: registered %d watch levels", m_watch_level_count);
   }

   // --------------------------------------------------------
   // ResetBarAlerts — call at the start of each new bar
   // to allow events to re-fire on the next bar.
   // --------------------------------------------------------
   void ResetBarAlerts()
   {
      m_health_alert_sent = false;
      m_volume_alert_sent = false;
      m_sl_alert_sent     = false;
   }

   // --------------------------------------------------------
   // CheckAll — run all 8 event checks on the current tick.
   // Returns the event type string if any fired, "" otherwise.
   // The caller posts the alert JSON to the Bridge /alert endpoint.
   // --------------------------------------------------------
   string CheckAll(const SMarketState &state, string &alertJson)
   {
      double currentPrice = SymbolInfoDouble("EURUSD", SYMBOL_BID);
      int    barNumber    = state.bar_number;

      // ── 1. REGIME_CHANGE ────────────────────────────────
      if(state.regime.type != m_last_regime)
      {
         string detail = "Regime flipped";
         alertJson = BuildAlertJson(EVT_REGIME_CHANGE, detail, currentPrice, barNumber);
         m_last_regime = state.regime.type;
         return EVT_REGIME_CHANGE;
      }

      // ── 2. HEALTH_CRITICAL ──────────────────────────────
      if(state.position.exists && !m_health_alert_sent
         && state.position.health_score < 40.0)
      {
         string detail = StringFormat("Health=%.1f", state.position.health_score);
         alertJson = BuildAlertJson(EVT_HEALTH_CRITICAL, detail, currentPrice, barNumber);
         m_health_alert_sent = true;
         return EVT_HEALTH_CRITICAL;
      }

      // ── 3. MOMENTUM_FLIP ────────────────────────────────
      int npvSign = (state.momentum.npv > 0.005) ? 1
                  : (state.momentum.npv < -0.005) ? -1 : 0;
      if(npvSign != 0 && npvSign != m_last_npv_sign && m_last_npv_sign != 0)
      {
         string detail = StringFormat("NPV flipped to %.4f", state.momentum.npv);
         alertJson = BuildAlertJson(EVT_MOMENTUM_FLIP, detail, currentPrice, barNumber);
         m_last_npv_sign = npvSign;
         return EVT_MOMENTUM_FLIP;
      }
      if(npvSign != 0) m_last_npv_sign = npvSign;

      // ── 4. PRICE_LEVEL_BREACH ───────────────────────────
      for(int i = 0; i < m_watch_level_count; i++)
      {
         if(m_level_breached[i]) continue;
         double level = m_watch_levels[i];
         if(MathAbs(currentPrice - level) < 0.00005)   // within 0.5 pip
         {
            string detail = StringFormat("Price %.5f breached watch level %.5f",
                                          currentPrice, level);
            alertJson = BuildAlertJson(EVT_PRICE_LEVEL_BREACH, detail, currentPrice, barNumber);
            m_level_breached[i] = true;
            return EVT_PRICE_LEVEL_BREACH;
         }
      }

      // ── 5. VOLUME_SPIKE ─────────────────────────────────
      if(!m_volume_alert_sent && state.current_bar.volume_avg > 0
         && state.current_bar.volume > state.current_bar.volume_avg * 2.5)
      {
         string detail = StringFormat("Volume=%.0f avg=%.0f",
                                       state.current_bar.volume,
                                       state.current_bar.volume_avg);
         alertJson = BuildAlertJson(EVT_VOLUME_SPIKE, detail, currentPrice, barNumber);
         m_volume_alert_sent = true;
         return EVT_VOLUME_SPIKE;
      }

      // ── 6. HTF_DIVERGENCE ───────────────────────────────
      if(state.position.exists)
      {
         int htfSign = (state.htf.consensus > 0.05) ? 1
                     : (state.htf.consensus < -0.05) ? -1 : 0;
         // Divergence: long position but HTF turns bearish, or vice versa
         bool diverging = (state.position.direction == 1  && htfSign == -1)
                       || (state.position.direction == -1 && htfSign == 1);
         if(diverging && htfSign != m_last_htf_sign)
         {
            string detail = StringFormat("HTF consensus=%.4f diverging from position",
                                          state.htf.consensus);
            alertJson = BuildAlertJson(EVT_HTF_DIVERGENCE, detail, currentPrice, barNumber);
            m_last_htf_sign = htfSign;
            return EVT_HTF_DIVERGENCE;
         }
         if(htfSign != 0) m_last_htf_sign = htfSign;
      }

      // ── 7. SL_PROXIMITY ─────────────────────────────────
      if(state.position.exists && !m_sl_alert_sent && state.position.sl > 0.0)
      {
         double slDist = MathAbs(currentPrice - state.position.sl) / _Point / 10.0;
         if(slDist <= 2.0)
         {
            string detail = StringFormat("Price %.5f within %.1f pips of SL %.5f",
                                          currentPrice, slDist, state.position.sl);
            alertJson = BuildAlertJson(EVT_SL_PROXIMITY, detail, currentPrice, barNumber);
            m_sl_alert_sent = true;
            return EVT_SL_PROXIMITY;
         }
      }

      // ── 8. DRAWDOWN_LIMIT ───────────────────────────────
      if(state.position.exists && state.position.pips_at_risk > 0.0)
      {
         double lossNow = 0.0;
         if(state.position.direction == 1)
            lossNow = (state.position.entry_price - currentPrice) / _Point / 10.0;
         else
            lossNow = (currentPrice - state.position.entry_price) / _Point / 10.0;

         if(lossNow > state.position.pips_at_risk * 1.5)
         {
            string detail = StringFormat("Drawdown %.1f pips > 1.5x SL (%.1f pips)",
                                          lossNow, state.position.pips_at_risk);
            alertJson = BuildAlertJson(EVT_DRAWDOWN_LIMIT, detail, currentPrice, barNumber);
            return EVT_DRAWDOWN_LIMIT;
         }
      }

      alertJson = "";
      return "";
   }
};
