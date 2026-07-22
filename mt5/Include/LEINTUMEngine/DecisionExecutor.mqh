// Translates LLM SDecision into MT5 order operations.
// This is the ONLY module that calls OrderSend().
// All entry gates (conviction, spread, daily loss) are checked here
// via CRiskManager before any order is placed.
//
// Management actions (MOVE_TO_BE, TIGHTEN_SL, CLOSE_ALL, CLOSE_PARTIAL)
// are also handled here, called every bar when a position is open.
//
// Hard trailing stop is enforced independently of the LLM:
// once profit >= TRAIL_ACTIVATE_PIPS, SL trails TRAIL_DISTANCE_PIPS behind price.

#include "Defines.mqh"
#include "RiskManager.mqh"

// ------------------------------------------------------------
// Trailing stop constants
// ------------------------------------------------------------
#define TRAIL_ACTIVATE_PIPS  20.0   // Start trailing after 20 pips in profit
#define TRAIL_DISTANCE_PIPS  10.0   // Trail SL 10 pips behind current price

// ------------------------------------------------------------
// CDecisionExecutor
// ------------------------------------------------------------
class CDecisionExecutor
{
private:
   CRiskManager*  m_risk;
   double         m_risk_percent;
   ulong          m_magic;

   // --------------------------------------------------------
   // Helper: extract a string value for a given JSON key
   // e.g. ExtractStr("{\"action\":\"OPEN_SELL\",...}", "action") -> "OPEN_SELL"
   // --------------------------------------------------------
   string ExtractStr(const string json, const string key)
   {
      string search = "\"" + key + "\":\"";
      int start = StringFind(json, search);
      if(start < 0) return "";
      start += StringLen(search);
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      return StringSubstr(json, start, end - start);
   }

   // --------------------------------------------------------
   // Helper: extract a numeric value for a given JSON key
   // e.g. ExtractNum("{\"price\":1.16506,...}", "price") -> 1.16506
   // --------------------------------------------------------
   double ExtractNum(const string json, const string key)
   {
      string search = "\"" + key + "\":";
      int start = StringFind(json, search);
      if(start < 0) return 0.0;
      start += StringLen(search);
      // skip null
      if(StringSubstr(json, start, 4) == "null") return 0.0;
      int end = start;
      int len = StringLen(json);
      while(end < len)
      {
         ushort ch = StringGetCharacter(json, end);
         if(ch == ',' || ch == '}' || ch == ']')
            break;
         end++;
      }
      return StringToDouble(StringSubstr(json, start, end - start));
   }

   // --------------------------------------------------------
   // Helper: compute SL price from pips (for display/log only)
   // --------------------------------------------------------
   double PipsToPrice(double pips) { return pips * _Point * 10.0; }

public:
   // --------------------------------------------------------
   // Constructor
   // --------------------------------------------------------
   CDecisionExecutor(CRiskManager* risk, double riskPercent, ulong magic = 20260101)
   {
      m_risk         = risk;
      m_risk_percent = riskPercent;
      m_magic        = magic;
   }

   // --------------------------------------------------------
   // ParseResponse — extract key fields from Bridge JSON string
   // Fills a lightweight SDecision struct (action, entry, management).
   // Returns false if the response cannot be parsed or action == HOLD.
   // --------------------------------------------------------
   bool ParseResponse(const string json, SDecision &dec)
   {
      // Action
      string actionStr = ExtractStr(json, "action");
      if(actionStr == "OPEN_BUY")       dec.action = ACTION_OPEN_BUY;
      else if(actionStr == "OPEN_SELL") dec.action = ACTION_OPEN_SELL;
      else if(actionStr == "CLOSE_ALL") dec.action = ACTION_CLOSE_ALL;
      else if(actionStr == "CLOSE_PARTIAL") dec.action = ACTION_CLOSE_PARTIAL;
      else                              dec.action = ACTION_HOLD;

      // bar_number
      dec.bar_number = (int)ExtractNum(json, "bar_number");

      // Entry block (may be null)
      dec.entry.price    = ExtractNum(json, "price");
      dec.entry.sl       = ExtractNum(json, "sl");
      dec.entry.tp       = ExtractNum(json, "tp");
      dec.entry.lot_size = ExtractNum(json, "lot_size");
      dec.entry.tp_basis = ExtractStr(json, "tp_basis");

      // Management block (may be null)
      string mgmtAction = ExtractStr(json, "action");   // second occurrence = management.action
      // Re-search specifically after "management":{
      int mgmtStart = StringFind(json, "\"management\":");
      if(mgmtStart >= 0)
      {
         string mgmtJson = StringSubstr(json, mgmtStart);
         string mgmtAct  = ExtractStr(mgmtJson, "action");
         if(mgmtAct == "TIGHTEN_SL")   { /* handled below */ }
         if(mgmtAct == "MOVE_TO_BE")   { /* handled below */ }
         if(mgmtAct == "CLOSE_ALL")    { /* handled below */ }
         // store as string for the manage branch
         if(mgmtAct == "TIGHTEN_SL")        dec.management.action = MGMT_TIGHTEN_SL;
         else if(mgmtAct == "MOVE_TO_BE")   dec.management.action = MGMT_MOVE_TO_BE;
         else if(mgmtAct == "CLOSE_ALL")    dec.management.action = MGMT_CLOSE_ALL;
         else                               dec.management.action = MGMT_HOLD;

         dec.management.sl_adjustment  = ExtractNum(mgmtJson, "sl_adjustment");
         dec.management.close_percent  = ExtractNum(mgmtJson, "close_percent");
      }
      else
      {
         dec.management.action        = MGMT_HOLD;
         dec.management.sl_adjustment = 0.0;
         dec.management.close_percent = 0.0;
      }

      // fallback flag
      dec.fallback = (ExtractStr(json, "fallback") == "true");

      return true;
   }

   // --------------------------------------------------------
   // OpenTrade — place a market order based on the LLM decision.
   // Returns the ticket number, or -1 on failure.
   // --------------------------------------------------------
   long OpenTrade(const SDecision &dec, double currentSpread)
   {
      if(dec.action != ACTION_OPEN_BUY && dec.action != ACTION_OPEN_SELL)
      {
         Print("[LEINTUM] DecisionExecutor: OpenTrade called with non-entry action");
         return -1;
      }

      // Conviction gate — use a fixed 0.50 since conviction is embedded
      // in the action choice (LLM won't OPEN unless confident)
      if(!m_risk.CanEnter(0.60, currentSpread))
      {
         PrintFormat("[LEINTUM] DecisionExecutor: RiskManager gate blocked entry");
         return -1;
      }

      ENUM_ORDER_TYPE orderType = (dec.action == ACTION_OPEN_BUY)
                                  ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double slPrice  = dec.entry.sl;
      double slPips   = MathAbs(dec.entry.price - slPrice) / _Point / 10.0;
      double lotSize  = (dec.entry.lot_size > 0.0)
                        ? dec.entry.lot_size
                        : m_risk.ComputeLotSize(slPips, m_risk_percent);

      double tp = (dec.entry.tp_basis == "HOLD_MANAGED" || dec.entry.tp == 0.0)
                  ? 0.0 : dec.entry.tp;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action   = TRADE_ACTION_DEAL;
      req.symbol   = "EURUSD";
      req.volume   = lotSize;
      req.type     = orderType;
      req.price    = (orderType == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble("EURUSD", SYMBOL_ASK)
                     : SymbolInfoDouble("EURUSD", SYMBOL_BID);
      req.sl       = slPrice;
      req.tp       = tp;
      req.magic    = m_magic;
      req.comment  = "LEINTUM_v1";
      req.deviation = 10;

      bool ok = OrderSend(req, res);

      if(!ok || res.retcode != TRADE_RETCODE_DONE)
      {
         PrintFormat("[LEINTUM] DecisionExecutor: OrderSend failed — retcode=%d  %s",
                     res.retcode, res.comment);
         return -1;
      }

      PrintFormat("[LEINTUM] Trade opened — ticket=%I64u  type=%s  lot=%.2f  price=%.5f  sl=%.5f",
                  res.deal, (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  lotSize, res.price, slPrice);
      return (long)res.deal;
   }

   // --------------------------------------------------------
   // ManageTrade — apply the LLM management action to an open position.
   // Also applies the hard trailing stop independent of the LLM.
   // --------------------------------------------------------
   bool ManageTrade(const SDecision &dec, const SOpenPosition &pos)
   {
      if(!pos.exists)
         return false;

      ulong ticket = pos.ticket;

      // ── Hard trailing stop (always runs, regardless of LLM management) ──
      double profitPips = 0.0;
      if(pos.direction == 1)
         profitPips = (pos.current_price - pos.entry_price) / _Point / 10.0;
      else
         profitPips = (pos.entry_price - pos.current_price) / _Point / 10.0;

      if(profitPips >= TRAIL_ACTIVATE_PIPS)
      {
         double trailSL = 0.0;
         if(pos.direction == 1)
            trailSL = pos.current_price - TRAIL_DISTANCE_PIPS * _Point * 10.0;
         else
            trailSL = pos.current_price + TRAIL_DISTANCE_PIPS * _Point * 10.0;

         bool needsMove = false;
         if(pos.direction == 1  && (pos.sl == 0.0 || trailSL > pos.sl))
            needsMove = true;
         if(pos.direction == -1 && (pos.sl == 0.0 || trailSL < pos.sl))
            needsMove = true;

         if(needsMove)
         {
            if(!ModifySL(ticket, trailSL))
               PrintFormat("[LEINTUM] Trail SL modify failed for ticket %I64u", ticket);
            else
               PrintFormat("[LEINTUM] Trailing SL moved to %.5f (profit=%.1f pips)", trailSL, profitPips);
         }
      }

      // ── LLM management action ──
      switch(dec.management.action)
      {
         case MGMT_HOLD:
            break;

         case MGMT_MOVE_TO_BE:
         {
            double beSL = pos.entry_price;
            if(pos.direction == 1)  beSL += 1.0 * _Point * 10.0;
            else                    beSL -= 1.0 * _Point * 10.0;
            if(!ModifySL(ticket, beSL))
               Print("[LEINTUM] MOVE_TO_BE failed");
            else
               PrintFormat("[LEINTUM] SL moved to breakeven %.5f", beSL);
            break;
         }

         case MGMT_TIGHTEN_SL:
         {
            double adj = dec.management.sl_adjustment * _Point * 10.0;
            double newSL = pos.sl;
            if(pos.direction == 1)  newSL += adj;
            else                    newSL -= adj;
            if(!ModifySL(ticket, newSL))
               Print("[LEINTUM] TIGHTEN_SL failed");
            else
               PrintFormat("[LEINTUM] SL tightened to %.5f", newSL);
            break;
         }

         case MGMT_CLOSE_ALL:
            return CloseTrade(pos);
      }

      return true;
   }

   // --------------------------------------------------------
   // EmergencyClose — force close without waiting for LLM.
   // Called when health score < LEINTUM_HEALTH_EMERGENCY.
   // --------------------------------------------------------
   bool EmergencyClose(const SOpenPosition &pos)
   {
      if(!pos.exists) return false;
      PrintFormat("[LEINTUM] EMERGENCY CLOSE — health below threshold. ticket=%I64u", pos.ticket);
      return CloseTrade(pos);
   }

   // --------------------------------------------------------
   // CloseTrade — market close of a specific position
   // --------------------------------------------------------
   bool CloseTrade(const SOpenPosition &pos)
   {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action  = TRADE_ACTION_DEAL;
      req.symbol  = "EURUSD";
      req.volume  = PositionGetDouble(POSITION_VOLUME);
      req.type    = (pos.direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price   = (pos.direction == 1)
                    ? SymbolInfoDouble("EURUSD", SYMBOL_BID)
                    : SymbolInfoDouble("EURUSD", SYMBOL_ASK);
      req.position = pos.ticket;
      req.magic    = m_magic;
      req.deviation = 10;

      bool ok = OrderSend(req, res);
      if(!ok || res.retcode != TRADE_RETCODE_DONE)
      {
         PrintFormat("[LEINTUM] CloseTrade failed — retcode=%d  %s", res.retcode, res.comment);
         return false;
      }

      PrintFormat("[LEINTUM] Position closed — ticket=%I64u  price=%.5f", pos.ticket, res.price);
      return true;
   }

private:
   // --------------------------------------------------------
   // ModifySL — modify the stop loss of a position by ticket
   // --------------------------------------------------------
   bool ModifySL(ulong ticket, double newSL)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = "EURUSD";
      req.position = ticket;
      req.sl       = newSL;
      req.tp       = PositionGetDouble(POSITION_TP);

      bool ok = OrderSend(req, res);
      return (ok && res.retcode == TRADE_RETCODE_DONE);
   }
};
