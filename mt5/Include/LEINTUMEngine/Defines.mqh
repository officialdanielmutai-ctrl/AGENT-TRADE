// All enums, constants, and structs. No logic.
// Part of LEINTUMEngine include library.

// ------------------------------------------------------------
// 1. ENUMS
// ------------------------------------------------------------

enum ENUM_SESSION_TYPE
{
   SESSION_SPIKE,
   SESSION_HOT,
   SESSION_NORMAL,
   SESSION_QUIET
};

enum ENUM_REGIME_TYPE
{
   REGIME_TRENDING_UP,
   REGIME_TRENDING_DOWN,
   REGIME_RANGING
};

enum ENUM_MOMENTUM_PHASE
{
   PHASE_WAXING,
   PHASE_WANING,
   PHASE_NEUTRAL,
   PHASE_EXHAUSTED
};

enum ENUM_PAIR_STATE
{
   PAIR_ACTIVE,
   PAIR_COASTING,
   PAIR_DEAD
};

enum ENUM_ACTION_TYPE
{
   ACTION_OPEN_BUY,
   ACTION_OPEN_SELL,
   ACTION_HOLD,
   ACTION_CLOSE_ALL,
   ACTION_CLOSE_PARTIAL
};

enum ENUM_MANAGEMENT_ACTION
{
   MGMT_HOLD,
   MGMT_TIGHTEN_SL,
   MGMT_MOVE_TO_BE,
   MGMT_CLOSE_ALL
};

// ------------------------------------------------------------
// 2. CONSTANTS
// ------------------------------------------------------------

#define LEINTUM_SCHEMA_VERSION    "1.0"
#define LEINTUM_BRIDGE_URL        "http://localhost:3001/heartbeat"
#define LEINTUM_ALERT_URL         "http://localhost:3001/alert"
#define LEINTUM_STATUS_URL        "http://localhost:3001/status"
#define LEINTUM_MAX_POSITIONS     1
#define LEINTUM_MIN_CONVICTION    0.50
#define LEINTUM_HEALTH_EMERGENCY  25.0
#define LEINTUM_HEALTH_CAUTION    60.0
#define LEINTUM_MACRO_BUFFER_MINS 15
#define LEINTUM_HTF_MIN_AGREE     2

// ------------------------------------------------------------
// 3. STRUCTS
// ------------------------------------------------------------

struct SSessionState
{
   ENUM_SESSION_TYPE   type;
   double              svr;
   double              slMultiplier;
};

struct SRegime
{
   ENUM_REGIME_TYPE    type;
   double              der;
   double              hurst;
   double              rbe;
   double              regime_strength;
   bool                deceleration;
};

struct SMomentum
{
   ENUM_MOMENTUM_PHASE phase;
   double              npv;
   double              ier;
   double              acceleration;
   double              jerk;
};

struct SCondition
{
   double              vwap;
   double              vwap_upper;
   double              vwap_lower;
   bool                in_value;
   double              sds;
   double              bqs;
};

struct SCrossPair
{
   string              symbol;
   ENUM_PAIR_STATE     state;
   int                 direction;        // +1 UP, -1 DOWN, 0 DEAD
   bool                velocity_reversal;
};

struct SHTFContext
{
   double              h1_flow;
   double              h4_flow;
   double              d1_flow;
   double              consensus;
   int                 agree_count;
};

struct SBarAnatomy
{
   double              open;
   double              high;
   double              low;
   double              close;
   double              body_ratio;
   double              upper_wick_ratio;
   double              lower_wick_ratio;
   double              volume;
   double              volume_avg;
};

struct SMacroEvent
{
   string              event_name;
   string              impact;
   int                 minutes_to_next;
};

struct SOpenPosition
{
   bool                exists;
   int                 direction;        // +1 BUY, -1 SELL
   double              entry_price;
   double              current_price;
   double              sl;
   double              pips_at_risk;
   double              unrealised_pnl;
   double              health_score;
   ulong               ticket;
};

struct SMarketState
{
   int                 bar_number;
   SSessionState       session;
   SRegime             regime;
   SMomentum           momentum;
   SCondition          condition;
   SHTFContext         htf;
   SCrossPair          cross_pairs[6];
   SBarAnatomy         current_bar;
   SMacroEvent         macro_calendar;
   SOpenPosition       position;
};

struct SEntryParams
{
   double              price;
   double              sl;
   double              tp;
   string              tp_basis;
   double              lot_size;
};

struct SManagement
{
   ENUM_MANAGEMENT_ACTION action;
   double              sl_adjustment;
   double              close_percent;
};

struct SReasoningBlock
{
   string              summary;
   string              supporting_factors[];
   string              concerns[];
   string              confidence_reasoning;
};

struct SDecision
{
   string              schema_version;
   string              decision_type;
   int                 bar_number;
   ENUM_ACTION_TYPE    action;
   SEntryParams        entry;
   SManagement         management;
   SReasoningBlock     reasoning;
   string              watch[];
   bool                fallback;
   string              fallback_reason;
   double              conviction;
};
