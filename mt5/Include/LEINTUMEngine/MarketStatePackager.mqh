// Serialises SMarketState to JSON string for Bridge transmission.
// All numeric values use StringFormat() — no implicit conversions.

#include "Defines.mqh"

// ------------------------------------------------------------
// CMarketStatePackager
// ------------------------------------------------------------
class CMarketStatePackager
{
public:
   // ------------------------------------------------------------
   // Serialize — build JSON string from SMarketState
   // ------------------------------------------------------------
   string Serialize(SMarketState &state)
   {
      string json = "";
      StringAdd(json, "{");

      // schema_version
      StringAdd(json, "\"schema_version\":\"1.0\",");
      // bar_number
      StringAdd(json, "\"bar_number\":");
      json += IntegerToString(state.bar_number);
      StringAdd(json, ",");

      // session
      StringAdd(json, "\"session\":{");
      StringAdd(json, "\"type\":\"");
      json += SessionTypeStr(state.session.type);
      StringAdd(json, "\",");
      StringAdd(json, "\"svr\":");
      json += StringFormat("%.4f", state.session.svr);
      StringAdd(json, "},");

      // regime
      StringAdd(json, "\"regime\":{");
      StringAdd(json, "\"type\":\"");
      json += RegimeTypeStr(state.regime.type);
      StringAdd(json, "\",");
      StringAdd(json, "\"der\":");
      json += StringFormat("%.4f", state.regime.der);
      StringAdd(json, ",");
      StringAdd(json, "\"hurst\":");
      json += StringFormat("%.4f", state.regime.hurst);
      StringAdd(json, ",");
      StringAdd(json, "\"regime_strength\":");
      json += StringFormat("%.4f", state.regime.regime_strength);
      StringAdd(json, ",");
      StringAdd(json, "\"deceleration\":");
      json += (state.regime.deceleration ? "true" : "false");
      StringAdd(json, "},");

      // momentum
      StringAdd(json, "\"momentum\":{");
      StringAdd(json, "\"phase\":\"");
      json += MomentumPhaseStr(state.momentum.phase);
      StringAdd(json, "\",");
      StringAdd(json, "\"npv\":");
      json += StringFormat("%.4f", state.momentum.npv);
      StringAdd(json, ",");
      StringAdd(json, "\"ier\":");
      json += StringFormat("%.4f", state.momentum.ier);
      StringAdd(json, ",");
      StringAdd(json, "\"acceleration\":");
      json += StringFormat("%.4f", state.momentum.acceleration);
      StringAdd(json, "},");

      // htf
      StringAdd(json, "\"htf\":{");
      StringAdd(json, "\"h1\":");
      json += StringFormat("%.4f", state.htf.h1_flow);
      StringAdd(json, ",");
      StringAdd(json, "\"h4\":");
      json += StringFormat("%.4f", state.htf.h4_flow);
      StringAdd(json, ",");
      StringAdd(json, "\"d1\":");
      json += StringFormat("%.4f", state.htf.d1_flow);
      StringAdd(json, ",");
      StringAdd(json, "\"consensus\":");
      json += StringFormat("%.4f", state.htf.consensus);
      StringAdd(json, ",");
      StringAdd(json, "\"agree_count\":");
      json += IntegerToString(state.htf.agree_count);
      StringAdd(json, "},");

      // cross_pairs
      StringAdd(json, "\"cross_pairs\":{");
      for(int i = 0; i < 6; i++)
      {
         if(i > 0)
            StringAdd(json, ",");
         json += "\"";
         json += state.cross_pairs[i].symbol;
         json += "\":\"";
         json += PairStateStr(state.cross_pairs[i].state);
         json += " ";
         json += PairDirStr(state.cross_pairs[i].direction);
         json += "\"";
      }
      StringAdd(json, "},");

      // current_bar
      StringAdd(json, "\"current_bar\":{");
      StringAdd(json, "\"body_ratio\":");
      json += StringFormat("%.4f", state.current_bar.body_ratio);
      StringAdd(json, ",");
      StringAdd(json, "\"upper_wick_ratio\":");
      json += StringFormat("%.4f", state.current_bar.upper_wick_ratio);
      StringAdd(json, ",");
      StringAdd(json, "\"lower_wick_ratio\":");
      json += StringFormat("%.4f", state.current_bar.lower_wick_ratio);
      StringAdd(json, ",");
      StringAdd(json, "\"volume\":");
      json += StringFormat("%.0f", state.current_bar.volume);
      StringAdd(json, ",");
      StringAdd(json, "\"volume_avg\":");
      json += StringFormat("%.0f", state.current_bar.volume_avg);
      StringAdd(json, "},");

      // health_score
      StringAdd(json, "\"health_score\":");
      if(!state.position.exists)
         StringAdd(json, "null");
      else
         json += StringFormat("%.1f", state.position.health_score);
      StringAdd(json, ",");

      // macro_calendar
      StringAdd(json, "\"macro_calendar\":{");
      StringAdd(json, "\"minutes_to_next\":");
      json += IntegerToString(state.macro_calendar.minutes_to_next);
      StringAdd(json, ",");
      StringAdd(json, "\"event\":\"");
      json += EscapeJsonString(state.macro_calendar.event_name);
      StringAdd(json, "\",");
      StringAdd(json, "\"impact\":\"");
      json += EscapeJsonString(state.macro_calendar.impact);
      StringAdd(json, "\"}");

      // close
      StringAdd(json, "}");

      return json;
   }

private:
   // ------------------------------------------------------------
   // Helper: SessionTypeStr
   // ------------------------------------------------------------
   string SessionTypeStr(ENUM_SESSION_TYPE t)
   {
      switch(t)
      {
         case SESSION_SPIKE:  return "SPIKE";
         case SESSION_HOT:    return "HOT";
         case SESSION_NORMAL: return "NORMAL";
         case SESSION_QUIET:  return "QUIET";
         default:             return "NORMAL";
      }
   }

   // ------------------------------------------------------------
   // Helper: RegimeTypeStr
   // ------------------------------------------------------------
   string RegimeTypeStr(ENUM_REGIME_TYPE t)
   {
      switch(t)
      {
         case REGIME_TRENDING_UP:   return "TRENDING_UP";
         case REGIME_TRENDING_DOWN: return "TRENDING_DOWN";
         case REGIME_RANGING:       return "RANGING";
         default:                   return "RANGING";
      }
   }

   // ------------------------------------------------------------
   // Helper: MomentumPhaseStr
   // ------------------------------------------------------------
   string MomentumPhaseStr(ENUM_MOMENTUM_PHASE p)
   {
      switch(p)
      {
         case PHASE_WAXING:    return "WAXING";
         case PHASE_WANING:    return "WANING";
         case PHASE_NEUTRAL:   return "NEUTRAL";
         case PHASE_EXHAUSTED: return "EXHAUSTED";
         default:              return "NEUTRAL";
      }
   }

   // ------------------------------------------------------------
   // Helper: PairStateStr
   // ------------------------------------------------------------
   string PairStateStr(ENUM_PAIR_STATE s)
   {
      switch(s)
      {
         case PAIR_ACTIVE:   return "ACTIVE";
         case PAIR_COASTING: return "COASTING";
         case PAIR_DEAD:     return "DEAD";
         default:            return "DEAD";
      }
   }

   // ------------------------------------------------------------
   // Helper: PairDirStr
   // ------------------------------------------------------------
   string PairDirStr(int dir)
   {
      if(dir > 0)
         return "UP";
      else if(dir < 0)
         return "DOWN";
      else
         return "FLAT";
   }

   // ------------------------------------------------------------
   // Helper: EscapeJsonString — replace " with \"
   // ------------------------------------------------------------
   string EscapeJsonString(string s)
   {
      string result = "";
      int len = StringLen(s);
      for(int i = 0; i < len; i++)
      {
         ushort ch = StringGetCharacter(s, i);
         if(ch == '"')
            StringAdd(result, "\\\"");
         else
            StringAdd(result, ShortToString(ch));
      }
      return result;
   }
};
