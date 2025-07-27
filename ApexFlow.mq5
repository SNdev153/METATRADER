//+------------------------------------------------------------------+
//|                 Git ApexFlowEA.mq5 (統合戦略モデル)                |
//|               (傾斜ダイナミクス + 大循環MACD 先行指標)             |
//|                         Version: 7.x (Full-Commented)            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "7.61"
#property description "Ver7.62: パラメータ整理　パフォーマンス改善 MTFスイング分析実装　バイアス新定義、TP至近スキップ HTインジ対応　MTF対応傾斜ダイナミクスと大循環MACDを統合したFSM分析エンジン。日本語コメントを完全復元。"

//+------------------------------------------------------------------+
//|                            定数定義                              |
//+------------------------------------------------------------------+
// --- ラインカラー定数 ---
#define CLR_S1 2970272
#define CLR_R1 13434880
#define CLR_S2 36095
#define CLR_R2 16748574
#define CLR_S3 42495
#define CLR_R3 15453831

// --- ボタン名定義 ---
#define BUTTON_BUY_CLOSE_ALL  "Button_BuyCloseAll"
#define BUTTON_SELL_CLOSE_ALL "Button_SellCloseAll"
#define BUTTON_ALL_CLOSE      "Button_AllClose"
#define BUTTON_RESET_BUY_TP   "Button_ResetBuyTP"
#define BUTTON_RESET_SELL_TP  "Button_ResetSellTP"
#define BUTTON_RESET_BUY_SL   "Button_ResetBuySL"
#define BUTTON_RESET_SELL_SL  "Button_ResetSellSL"
#define BUTTON_TOGGLE_ZONES   "Button_ToggleZones"

// --- MTF分析用定数 ---
#define ENUM_TIMEFRAMES_COUNT 3 // 執行足, 中間足, 上位足の合計数
#define TF_CURRENT_INDEX      0 // 執行足 (_Period) のインデックス
#define TF_INTERMEDIATE_INDEX 1 // 中間時間足 (例: H4) のインデックス
#define TF_HIGHER_INDEX       2 // 上位時間足 (例: D1) のインデックス

//+------------------------------------------------------------------+
//|                  すべての enum / struct 定義                     |
//+------------------------------------------------------------------+

// ---【新規追加】ストキャスのシグナルモード定義 ---
enum ENUM_STOCH_MODE
{
    MODE_EVERYWHERE,    // どこでもシグナルを出す
    MODE_ZONE_ONLY      // ゾーン内でのみシグナルを出す

};
// ==================================================================
// --- 状態定義 (enum) ---
// ==================================================================

// 傾斜状態の定義 (変更なし)
enum ENUM_SLOPE_STATE
{
    SLOPE_UP_STRONG,    // 強い上昇
    SLOPE_UP_WEAK,      // 弱い上昇
    SLOPE_FLAT,         // 横ばい
    SLOPE_DOWN_WEAK,    // 弱い下降
    SLOPE_DOWN_STRONG   // 強い下降
};

// マスター状態の定義 (EAの統合的な状態) (変更なし)
enum ENUM_MASTER_STATE
{
    STATE_UNKNOWN,          // 不明 / 初期状態
    STATE_1A_NASCENT,       // [買] 1-A (上昇トレンド予兆)
    STATE_1B_CONFIRMED,     // [買] 1-B (上昇トレンド本物)
    STATE_1C_MATURE,        // [待] 1-C (上昇トレンド成熟)
    STATE_2_PULLBACK,       // [買] 2 (押し目買いチャンス)
    STATE_2_REVERSAL_WARN,  // [売] 2 (トレンド転換警告)
    STATE_3_TRANSITION_DOWN,// [売] 3 (下降へ反転開始)
    STATE_4A_NASCENT,       // [売] 4-A (下降トレンド予兆)
    STATE_4B_CONFIRMED,     // [売] 4-B (下降トレンド本物)
    STATE_4C_MATURE,        // [待] 4-C (下降トレンド成熟)
    STATE_5_RALLY,          // [売] 5 (戻り売りチャンス)
    STATE_5_REVERSAL_WARN,  // [買] 5 (トレンド転換警告)
    STATE_6_TRANSITION_UP,  // [買] 6 (上昇へ反転開始)
    STATE_6_REJECTION,      // [売] 6 (上昇失敗/拒絶)
    STATE_3_REJECTION       // [買] 3 (下降失敗/シェイクアウト)
};

// サポート/レジスタンスの種別 (変更なし)
enum ENUM_LINE_TYPE
{
    LINE_TYPE_SUPPORT,
    LINE_TYPE_RESISTANCE
};

// 分割決済の順序ロジック (変更なし)
enum ENUM_EXIT_LOGIC
{
    EXIT_FIFO,          // 先入れ先出し
    EXIT_UNFAVORABLE,   // 不利なポジションから決済
    EXIT_FAVORABLE      // 有利なポジションから決済
};

// TPラインの計算モード (変更なし)
enum ENUM_TP_MODE
{
    MODE_ZIGZAG,
    MODE_PIVOT
};

// パネルの表示コーナー (変更なし)
enum ENUM_PANEL_CORNER
{
    PC_LEFT_UPPER,      // 左上
    PC_RIGHT_UPPER,     // 右上
    PC_LEFT_LOWER,      // 左下
    PC_RIGHT_LOWER      // 右下
};

// 新しい取引バイアスの定義 (市場サイクルモデル)
enum ENUM_TRADE_BIAS
{
    // --- Neutral States (中立状態) ---
    BIAS_UNCLEAR,                           // 不明確
    BIAS_RANGE_BOUND,                       // レンジ・方向感なし
    BIAS_RANGE_SQUEEZE,                     // レンジ・収縮
    BIAS_RANGE_BREAKOUT_POTENTIAL_UP,       // レンジブレイク期待・上
    BIAS_RANGE_BREAKOUT_POTENTIAL_DOWN,     // レンジブレイク期待・下

    // --- Bullish States (買い優位) ---
    BIAS_ALIGNED_EARLY_ENTRY_BUY,           // 順張りアーリーエントリー・買
    BIAS_SHAKEOUT_BUY,                      // シェイクアウト・買
    BIAS_DOMINANT_CORE_TREND_BUY,           // 完全順行コアトレンド・買
    BIAS_DOMINANT_PULLBACK_BUY,             // 完全順行プルバック・買
    BIAS_ALIGNED_CORE_TREND_BUY,            // 順張りコアトレンド・買
    BIAS_CONFLICTING_PULLBACK_BUY,          // 逆行プルバック・買
    BIAS_TREND_EXHAUSTION_BUY,              // トレンド枯渇・買

    // --- Bearish States (売り優位) ---
    BIAS_ALIGNED_EARLY_ENTRY_SELL,          // 順張りアーリーエントリー・売
    BIAS_SHAKEOUT_SELL,                     // シェイクアウト・売
    BIAS_DOMINANT_CORE_TREND_SELL,          // 完全順行コアトレンド・売
    BIAS_DOMINANT_PULLBACK_SELL,            // 完全順行プルバック・売
    BIAS_ALIGNED_CORE_TREND_SELL,           // 順張りコアトレンド・売
    BIAS_CONFLICTING_PULLBACK_SELL,         // 逆行プルバック・売
    BIAS_TREND_EXHAUSTION_SELL              // トレンド枯渇・売
};

// --- 新規: バイアスの段階の定義 ---
enum ENUM_BIAS_PHASE
{
    PHASE_NONE,         // 段階なし
    PHASE_INITIATING,   // 初期、形成中、兆候期
    PHASE_PROGRESSING,  // 進行中、本格期、調整期
    PHASE_MATURING      // 後期、成熟/減速期、反転期、膠着期、準備期
};


// ==================================================================
// --- データ保持構造 (struct) ---
// ==================================================================

// 大循環MACDの構成要素 (変更なし)
struct DaijunkanMACDValues
{
    double macd1;           // 短期MA - 中期MA
    double macd2;           // 短期MA - 長期MA
    double obi_macd;        // 中期MA - 長期MA (帯MACD)
    double signal;          // 帯MACDのシグナル
    bool   is_obi_gc;       // 帯MACDがシグナルとGCしたか
    bool   is_obi_dc;       // 帯MACDがシグナルとDCしたか
    double obi_macd_slope;  // 帯MACDの傾き
};

// 【新版】環境分析結果を保持する構造体 (既存を以下で上書き)
struct EnvironmentState
{
    ENUM_MASTER_STATE   master_state;           // 執行足のマスター状態
    int                 primary_stage;          // 執行足の伝統的ステージ
    int                 prev_primary_stage;     // 執行足の前の足の伝統的ステージ (将来的に使用)
    ENUM_SLOPE_STATE    slope_short;            // 執行足の短期MA傾き
    ENUM_SLOPE_STATE    slope_middle;           // 執行足の中期MA傾き
    ENUM_SLOPE_STATE    slope_long;             // 執行足の長期MA傾き
    DaijunkanMACDValues macd_values;            // 執行足の大循環MACD値
    int                 currentBuyScore;        // 旧スコア (必要に応じて後で統合/削除)
    int                 currentSellScore;       // 旧スコア (必要に応じて後で統合/削除)

    // --- 新規: MTF分析用フィールド ---
    ENUM_MASTER_STATE   mtf_master_state[ENUM_TIMEFRAMES_COUNT];     // 各時間足のマスター状態
    ENUM_SLOPE_STATE    mtf_slope_short[ENUM_TIMEFRAMES_COUNT];      // 各時間足の短期MA傾き
    ENUM_SLOPE_STATE    mtf_slope_middle[ENUM_TIMEFRAMES_COUNT];     // 各時間足の中期MA傾き
    ENUM_SLOPE_STATE    mtf_slope_long[ENUM_TIMEFRAMES_COUNT];       // 各時間足の長期MA傾き
    DaijunkanMACDValues mtf_macd_values[ENUM_TIMEFRAMES_COUNT];      // 各時間足の大循環MACD値

    // --- 新規: 総合優位性スコア ---
    int                 total_buy_score;        // 統合買い優位性スコア
    int                 total_sell_score;       // 統合売り優位性スコア

    // --- 新規: 現在の取引バイアスと段階 ---
    ENUM_TRADE_BIAS     current_trade_bias;     // 現在の取引バイアス (例: コアトレンド、プルバック)
    ENUM_BIAS_PHASE     current_bias_phase;     // 現在のバイアスの段階 (例: 初期、進行中、後期)
};

// ライン情報を一元管理するための構造体
struct Line
{
    string           name;
    double           price;
    ENUM_LINE_TYPE   type;
    color            signalColor;
    datetime         startTime;
    datetime         breakTime;
    bool             isBrokeUp;
    bool             isBrokeDown;
    bool             waitForRetest;
    bool             isInZone;
};

// 保有ポジションの情報を管理するための構造体
struct PositionInfo
{
    long ticket; // ポジションのチケット番号
    int  score;  // エントリー時のスコア
};

// 集約ポジションモードでのグループデータを管理
struct PositionGroup
{
    bool     isActive;
    bool     isBuy;
    double   averageEntryPrice;
    double   totalLotSize;
    double   initialTotalLotSize;
    double   previousTotalLotSize;
    ulong    positionTickets[];
    double   splitPrices[];
    string   splitLineNames[];
    datetime splitLineTimes[];
    int      splitsDone;
    int      lockedInSplitCount;
    datetime openTime;
    double   stampedFinalTP;
    double   averageScore;
    int      highestScore;
    int      positionCount;
    bool     timeExitResetDone; // 【新規】時間経過によるTPリセットが実行されたか

};

// 決済順序をソートするための構造体
struct SortablePosition
{
    ulong  ticket;
    double openPrice;
};

// ラインのブレイク状態を永続化するための構造体
struct LineState
{
    string   name;
    bool     isBrokeUp;
    bool     isBrokeDown;
    bool     waitForRetestUp;
    bool     waitForRetestDown;
    datetime breakTime;
};

// スイングの頂点情報（時間と価格）を保持する構造体
struct SwingPoint
{
    datetime time;
    double   price;
};

// 互換性のために残す古い構造体（最終的に削除予定）
struct ScoreComponentInfo { int total_score; };

//+------------------------------------------------------------------+
//|                     入力パラメータ (input) - 整理版                |
//+------------------------------------------------------------------+

// ==================================================================
// === ① 基本分析設定 ===
// ==================================================================
input group "--- 大循環分析 (移動平均線) ---";
input int               InpGCMAShortPeriod      = 5;         // 短期MAの期間
input int               InpGCMAMiddlePeriod     = 20;        // 中期MAの期間
input int               InpGCMALongPeriod       = 40;        // 長期MAの期間
input ENUM_MA_METHOD    InpGCMAMethod           = MODE_EMA;  // MAの種別
input ENUM_APPLIED_PRICE InpGCMAAppliedPrice    = PRICE_CLOSE;// MAの適用価格

input group "--- 傾斜ダイナミクス (MAの傾き) ---";
input double InpSlopeUpStrong   = 0.3;   // 「強い上昇」と判断する正規化傾斜の閾値
input double InpSlopeUpWeak     = 0.1;   // 「弱い上昇」と判断する正規化傾斜の閾値
input double InpSlopeDownWeak   = -0.1;  // 「弱い下降」と判断する正規化傾斜の閾値
input double InpSlopeDownStrong = -0.3;  // 「強い下降」と判断する正規化傾斜の閾値
input int    InpSlopeLookback   = 1;     // 傾き計算のルックバック期間(n)
input int    InpSlopeAtrPeriod  = 14;    // 傾き正規化のためのATR期間(p)

input group "--- MTF (マルチタイムフレーム) ---";
input ENUM_TIMEFRAMES InpHigherTimeframe       = PERIOD_D1; // 上位時間足の選択
input ENUM_TIMEFRAMES InpIntermediateTimeframe = PERIOD_H4; // 中間時間足の選択

input group "--- 外部インジケーター連携 ---";
input bool InpUseExternalIndicator = true; // 外部インジケーター(HT_Turning_Point)を使用する

// ==================================================================
// === ② エントリーシグナル設定 ===
// ==================================================================
input group "--- プライスアクション (ピンバー) ---";
input bool   InpUsePriceActionSignal = true;   // プライスアクション・シグナルを有効にする
input double InpPinbarBodyRatio      = 0.33; // ピンバーの定義: 実体が全体の何割以下か
input double InpPinbarWickRatio      = 2.0;  // ピンバーの定義: 長いヒゲが実体の何倍以上か

input group "--- 大循環ストキャスティクス ---";
input bool              InpStoch_UseDaiJunkan    = true;            // 大循環ストキャスを有効にする
input ENUM_STOCH_MODE   InpStoch_SignalMode      = MODE_EVERYWHERE; // シグナルモード (ゾーン内 or どこでも)
input int               InpMainStoch_K_Period    = 20;              // メイン: %K期間
input int               InpMainStoch_D_Period    = 3;               // メイン: %D期間
input int               InpMainStoch_Slowing     = 3;               // メイン: スローイング
input int               InpMainStoch_Upper_Level = 80;              // メイン: 上限レベル
input int               InpMainStoch_Lower_Level = 20;              // メイン: 下限レベル
input bool              InpStoch_UseFilters      = true;            // フィルター機能を有効にする
input int               InpSubStoch_K_Period     = 40;              // サブ(フィルター用): %K期間
input int               InpSubStoch_D_Period     = 3;               // サブ(フィルター用): %D期間
input int               InpSubStoch_Slowing      = 3;               // サブ(フィルター用): スローイング

input group "--- RSI MAクロス ---";
input bool   Inp_RSI_EnableLogic = true;      // このロジックを有効にする
input int    Inp_RSI_Period      = 14;      // RSIの期間
input int    Inp_RSI_MAPeriod    = 5;       // RSIの移動平均期間
input double Inp_RSI_UpperLevel  = 60.0;    // RSIの上限レベル
input double Inp_RSI_LowerLevel  = 40.0;    // RSIの下限レベル
input ENUM_MA_METHOD Inp_RSI_MAMethod = MODE_EMA; // RSIの移動平均の種別

input group "--- ダイバージェンス ---";
input bool   InpShowDivergenceSignals = true;        // ダイバージェンスサインを表示するか
input color  InpBullishDivColor       = clrDeepSkyBlue; // 強気ダイバージェンスの色
input color  InpBearishDivColor       = clrHotPink;   // 弱気ダイバージェンスの色

// ==================================================================
// === ③ エントリーロジック & フィルター ===
// ==================================================================
input group "--- エントリーモード & 共通フィルター ---";
enum ENTRY_MODE { TOUCH_MODE, ZONE_MODE };
input ENTRY_MODE      InpEntryMode               = ZONE_MODE; // エントリーモード
input bool            InpAllowRangeEntry         = true;      // レンジ相場でのエントリーを許可する
input bool            InpBreakMode               = true;      // (タッチモード用) ブレイクをシグナルと見なす
input bool            InpAllowSignalAfterBreak   = true;      // (タッチモード用) ブレイク後の再シグナルを許可
input double          InpZonePips                = 50.0;      // ゾーン幅 (pips)
input bool            InpEnableZoneMacdCross     = true;      // (ゾーンモード限定) ゾーン内MACDクロスでエントリー
input double          InpEntry_MinRewardRiskRatio= 1.2;      // エントリーの最低リスクリワード比率 (RRR)
input bool            InpUseUniversalZoneFilter  = true;      // 全シグナル共通のゾーン・フィルターを有効にする
input bool            InpZoneFilter_UseStatic    = true;      // フィルター: 静的ゾーン(ピボット/手動ライン)
input bool            InpZoneFilter_UseMA        = true;      // フィルター: 動的ゾーン(MAバンド)
input bool            Inp_RSI_UseZoneFilter      = true;      // (RSIロジック用) ゾーンフィルターを使用する

input group "--- MTFスコアリング ---";
input int    InpEntryScore              = 5;       // エントリーの最低スコア
input bool   InpAllowEntryOnScoreDiff   = true;    // バイアス不一致でもスコア差でエントリーを許可する
input int    InpMinScoreDiffForEntry    = 25;      // ↑を許可する場合のエントリーに必要な最低スコア差
input int    InpWeightCurrentTF         = 10;      // 執行時間足のスコア重み付け
input int    InpWeightIntermediateTF    = 15;      // 中間時間足のスコア重み付け
input int    InpWeightHigherTF          = 20;      // 上位時間足のスコア重み付け
input int    InpScore_State_Confirmed   = 10;      // [スコア] 状態: 本物 (1-B, 4-B)
input int    InpScore_State_Rejection   = 9;       // [スコア] 状態: 失敗/拒絶 (3-Rej, 6-Rej)
input int    InpScore_State_Nascent     = 7;       // [スコア] 状態: 予兆 (1-A, 4-A)
input int    InpScore_State_Pullback    = 6;       // [スコア] 状態: 押し目/戻り (2-Pull, 5-Rally)
input int    InpScore_State_Transition  = 5;       // [スコア] 状態: 移行中 (6-TransUp, 3-TransDown)
input int    InpScore_State_Mature      = 3;       // [スコア] 状態: 成熟 (1-C, 4-C)
input int    InpScore_Slope_Long_Strong = 4;       // [スコア] 長期MA傾き: 強い
input int    InpScore_Slope_Long_Weak   = 2;       // [スコア] 長期MA傾き: 弱い
input int    InpScore_Slope_Short       = 2;       // [スコア] 短期MA傾き (執行足のみ)
input int    InpScore_MACD_Cross        = 5;       // [スコア] 帯MACDクロス (GC/DC)
input int    InpScore_MACD_Momentum     = 3;       // [スコア] 帯MACDモメンタム
input int    InpBias_ScoreDiff_Dominant = 30;      // [バイアス] 優位性と判断するスコア差
input int    InpBias_Score_Range        = 20;      // [バイアス] レンジと判断するスコア閾値

input group "--- シグナル有効期限 ---";
input int InpSignalEntryExpiryBars  = 3;    // シグナルの【エントリー】有効期限 (バーの本数)
input int InpSignalVisualExpiryBars = 100;  // シグナルの【表示】有効期限 (バーの本数, 0で実質無期限)
input int InpRetestExpiryBars     = 10;     // ブレイク後のリテスト有効期限 (バーの本数)

// ==================================================================
// === ④ 資金・ポジション管理 ===
// ==================================================================
input group "--- ロットサイズ設定 ---";
input double InpLotSize              = 0.1;   // 基本ロットサイズ
input bool   InpEnableRiskBasedLot   = true;  // リスクベースの自動ロット計算を有効にする
input double InpRiskPercent          = 1.0;   // 1トレードあたりのリスク許容率 (%)
input bool   InpEnableHighScoreRisk  = true;  // 高スコア時にリスクを変更する
input double InpHighScoreRiskPercent = 2.0;   // 高スコア時のリスク許容率 (%)
input int    InpHighScoreThreshold   = 8;     // 高スコアと判断する閾値

input group "--- ポジション設定 ---";
input int    InpMagicNumber        = 123456; // マジックナンバー
input int    InpMaxPositions       = 5;      // 同方向の最大ポジション数
input bool   InpEnableEntrySpacing = true;   // ポジション間隔フィルターを有効にする
input double InpEntrySpacingPips   = 10.0;   // 最低限確保するポジション間隔 (pips)

// ==================================================================
// === ⑤ 決済ロジック設定 ===
// ==================================================================
input group "--- 利確 (TP) 設定 ---";
input ENUM_TP_MODE    InpTPLineMode           = MODE_ZIGZAG; // TPラインの計算モード
input ENUM_TIMEFRAMES InpTP_Timeframe         = PERIOD_H4;   // TP計算用の時間足 (ZigZag/Pivot共用)
input int             InpZigzagDepth          = 12;          // (ZigZagモード用) Depth
input int             InpZigzagDeviation      = 5;           // (ZigZagモード用) Deviation
input int             InpZigzagBackstep       = 3;           // (ZigZagモード用) Backstep
input int             InpSplitCount           = 3;           // 分割決済の回数
input double          InpFinalTpRR_Ratio      = 2.5;         // 最終TPのRR比
input double          InpHighSchoreTpRratio   = 1.5;         // 高スコア時のTP倍率

input group "--- 損切 (SL) 設定 ---";
enum ENUM_SL_MODE { SL_MODE_MANUAL, SL_MODE_OPPOSITE_TP };
input ENUM_SL_MODE    InpSlMode              = SL_MODE_MANUAL;    // SLモード
input double          InpAtrBufferMultiplier = 1.5;              // SLに加えるATRバッファーの倍率
input ENUM_TIMEFRAMES InpAtrSlTimeframe      = PERIOD_H1;         // バッファー計算に使うATRの時間足
input bool            InpEnableTrailingSL      = true;            // トレーリングSLを有効にする
input double          InpTrailingAtrMultiplier = 2.0;              // トレーリングATRの倍率

input group "--- 動的決済 (自動イグジット) ---";
input bool            InpExit_OnTrendEnd         = true;    // 決済ON/OFF: 執行足のトレンド終焉
input bool            InpExit_OnCounterBias      = true;    // 決済ON/OFF: 反対バイアス発生
input bool            InpExit_OnRange            = true;    // 決済ON/OFF: レンジ相場突入
input bool            InpEnableCounterSignalExit = true;    // 決済ON/OFF: 反対スコア到達
input int             InpCounterSignalScore      = 7;       // ↑のトリガーとなる反対シグナルの最低スコア
input bool            InpEnableTimeExit          = true;    // 決済ON/OFF: 時間経過
input int             InpExitAfterBars           = 48;      // 何本経過したら決済判断を行うか
input double          InpExitMinProfit           = 1.0;     // この利益額(口座通貨)未満の場合、時間で決済される
enum ENUM_TIME_EXIT_ACTION { TIME_EXIT_CLOSE, TIME_EXIT_RESET_TP };
input ENUM_TIME_EXIT_ACTION InpTimeExitAction = TIME_EXIT_CLOSE; // 時間経過時のアクション (決済 or TPリセット)

input group "--- その他決済設定 ---";
input ENUM_EXIT_LOGIC InpExitLogic            = EXIT_UNFAVORABLE; // 分割決済のポジション選択ロジック
input int             InpBreakEvenAfterSplits = 1;                // N回分割決済後にストップを建値(BE)に設定
input bool            InpEnableProfitBE       = true;             // 利益確保型BEを有効にする
input double          InpProfitBE_Pips        = 2.0;              // 利益確保BEの幅 (pips)
input double          InpExitBufferPips       = 1.0;              // 決済バッファ (Pips)

// ==================================================================
// === ⑥ UI・表示設定 ===
// ==================================================================
input group "--- 情報パネル ---";
input bool              InpShowInfoPanel     = true;           // 情報パネルを表示する
input ENUM_PANEL_CORNER InpPanelCorner       = PC_RIGHT_LOWER; // パネルの表示コーナー
input int               p_panel_x_offset     = 10;             // パネルX位置
input int               p_panel_y_offset     = 130;            // パネルY位置
input int               InpPanelFontSize     = 14;             // パネルのフォントサイズ
input int               InpPanelIconGapRight = 30;             // [右揃え用] アイコンとテキストの間隔
input int               InpScorePerSymbol    = 20;             // スコアバーの1●あたりの点数
input bool              InpEnableButtons     = true;           // 決済・操作ボタンを表示する

input group "--- スイング分析表示 ---";
input int    InpSwing_ZigzagDepth      = 12;    // ZigZag: Depth
input int    InpSwing_ZigzagDeviation  = 5;     // ZigZag: Deviation
input int    InpSwing_ZigzagBackstep   = 3;     // ZigZag: Backstep
input double InpSwing_MinAtrMultiplier = 0.5;   // 分析対象とする最小スイングサイズ (ATR倍率)
input bool   InpSwing_VisualizeSwings  = true;  // 参照スイングをチャートに描画する

input group "--- ピボットライン表示 ---";
input bool            InpUsePivotLines     = true;    // ピボTットラインを使用する
input ENUM_TIMEFRAMES InpPivotPeriod       = PERIOD_H1; // ピボット時間足
input bool            InpShowS2R2          = true;    // S2/R2ラインを表示
input bool            InpShowS3R3          = true;    // S3/R3ラインを表示
input int             InpPivotHistoryCount = 1;       // 表示する過去ピボットの数

input group "--- オブジェクト外観 ---";
input bool   InpVisualizeZones         = true;           // ゾーンを可視化する
input bool   InpVisualizeExternalLines = true;           // 外部ラインの価格をチャートに表示する
input color  InpVisResistColor         = clrSalmon;      // 可視化ラベルの色 (レジスタンス)
input color  InpVisSupportColor        = clrLightSeaGreen; // 可視化ラベルの色 (サポート)
input int    InpVisFontSize            = 8;              // 可視化ラベルのフォントサイズ
input int    InpSignalWidth            = 2;              // シグナルの太さ
input int    InpSignalFontSize         = 10;             // シグナルの大きさ
input double InpSignalOffsetPips       = 2.0;            // シグナルの描画オフセット (Pips)
input int    InpDivSymbolCode          = 159;            // ダイバージェンスサインのシンボルコード (159 = ●)
input int    InpDivSymbolSize          = 8;              // ダイバージェンスサインの大きさ
input double InpDivSymbolOffsetPips    = 15.0;           // ダイバージェンスサインの描画オフセット (Pips)
input string InpLinePrefix_Pivot       = "Pivot_";       // ピボットラインプレフィックス
input string InpDotPrefix              = "Dot_";         // ドットプレフィックス
input string InpArrowPrefix            = "Trigger_";     // 矢印プレフィックス
input string InpDivSignalPrefix        = "DivSignal_";   // ダイバージェンスサインのプレフィックス
input int    InpTouchBreakUpCode       = 221;            // タッチブレイク買いのシンボルコード
input int    InpTouchBreakDownCode     = 222;            // タッチブレイク売りのシンボルコード
input int    InpTouchReboundUpCode     = 233;            // タッチひげ反発買いのシンボルコード
input int    InpTouchReboundDownCode   = 234;            // タッチひげ反発売りのシンボルコード
input int    InpFalseBreakBuyCode      = 117;            // フォールスブレイク (買い) のシンボルコード
input int    InpFalseBreakSellCode     = 117;            // フォールスブレイク (売り) のシンボルコード
input int    InpRetestBuyCode          = 110;            // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode         = 111;            // ブレイク＆リテスト (売り) のシンボルコード
input int    InpZoneBounceBuyCode      = 241;            // ゾーンバウンス(買い)のシンボル
input int    InpZoneBounceSellCode     = 242;            // ゾーンバウンス(売り)のシンボル

input group "--- 手動ライン外観 ---";
input color           p_ManualSupport_Color = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color  = clrTomato;     // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style    = STYLE_DOT;     // 手動ラインのスタイル
input int             p_ManualLine_Width    = 2;             // 手動ラインの太さ

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                     グローバル変数                               |
//+------------------------------------------------------------------+
// --- インジケーターハンドル ---
int h_macd_exec, h_macd_mid, h_macd_long;
int h_main_stoch, h_sub_stoch; // ? 従来の h_stoch をこの2つに置き換え
int h_atr_sl, zigzagHandle;
int h_atr_slope; 
int h_turning_point = INVALID_HANDLE;
int h_rsi; // ← この行を追加
int h_zigzag_swing[ENUM_TIMEFRAMES_COUNT]; // スイング分析用ZigZagハンドル
int h_atr_swing[ENUM_TIMEFRAMES_COUNT];    // スイング分析用ATRハンドル

// MTF対応のインジケーターハンドル配列
int h_gc_ma_short_mtf[ENUM_TIMEFRAMES_COUNT];
int h_gc_ma_middle_mtf[ENUM_TIMEFRAMES_COUNT];
int h_gc_ma_long_mtf[ENUM_TIMEFRAMES_COUNT];
int h_atr_slope_mtf[ENUM_TIMEFRAMES_COUNT]; // 各時間足用の傾き正規化ATRハンドル

// --- 状態管理 ---
EnvironmentState g_env_state;
LineState        g_lineStates[];
Line             allLines[];
SwingPoint g_prev_swing_start[ENUM_TIMEFRAMES_COUNT];  // 前のスイングの始点
SwingPoint g_prev_swing_end[ENUM_TIMEFRAMES_COUNT];    // 前のスイングの終点
SwingPoint g_curr_swing_start[ENUM_TIMEFRAMES_COUNT];  // 現在のスイングの始点（＝前のスイングの終点）
PositionInfo     g_managedPositions[];
PositionGroup    buyGroup;
PositionGroup    sellGroup;

// --- その他のグローバル変数 ---
double   g_pip;
datetime g_lastBarTime = 0;
datetime lastArrowTime = 0;
datetime lastTradeTime = 0;
datetime g_lastPivotDrawTime = 0;
double   s1, r1, s2, r2, s3, r3, pivot;
double   zonalFinalTPLine_Buy, zonalFinalTPLine_Sell;
double   g_slLinePrice_Buy = 0;
double   g_slLinePrice_Sell = 0;
bool     g_isDrawingMode = false;
bool     isBuyTPManuallyMoved = false, isSellTPManuallyMoved = false;
bool     isBuySLManuallyMoved = false, isSellSLManuallyMoved = false;
bool     g_ignoreNextChartClick = false;
bool     g_isZoneVisualizationEnabled;
string   g_buttonName           = "DrawManualLineButton";
string   g_clearButtonName      = "ClearSignalsButton";
string   g_clearLinesButtonName = "ClearLinesButton";
string   g_panelPrefix          = "InfoPanel_";
string   g_manualLineNames[]; // EAが管理する手動ラインのオブジェクト名を保持する配列
// --- スイング分析キャッシュ用 ---
string   g_swing_info_cache[ENUM_TIMEFRAMES_COUNT];
color    g_swing_color_cache[ENUM_TIMEFRAMES_COUNT];
datetime g_swing_cache_bartime[ENUM_TIMEFRAMES_COUNT];

ENUM_TP_MODE    prev_tp_mode      = WRONG_VALUE;
ENUM_TIMEFRAMES prev_tp_timeframe = WRONG_VALUE;

// in グローバル変数セクション

bool     g_buyGroupJustClosed = false;   // 買いグループが決済されたことを示すフラグ
bool     g_sellGroupJustClosed = false;  // 売りグループが決済されたことを示すフラグ

//+------------------------------------------------------------------+
//|                   関数のプロトタイプ宣言                         |
//+------------------------------------------------------------------+
// --- 主要イベントハンドラ ---
int OnInit();
void OnDeinit(const int reason);
void OnTick();
void OnTimer();
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);

// --- 分析エンジン & ロジック関数 ---
void UpdateEnvironmentAnalysis();
void CheckPriceActionSignal(); // ? この行を追加
void CheckStateBasedExits();
void CheckEntry();
void PlaceOrder(bool isBuy, double price, int score);
void CalculateOverallBiasAndScore(); // 【新規】この行を追加
bool IsInValidZone(datetime signal_time, bool is_buy_signal); // ? この行を追加

// --- 分析ヘルパー関数 ---
bool InitSlopeAtr();
ENUM_SLOPE_STATE GetSlopeState(int ma_handle, int lookback);
ENUM_MASTER_STATE GetMasterState(int primary_stage, int prev_primary_stage, ENUM_SLOPE_STATE slope_long, ENUM_SLOPE_STATE slope_short, const DaijunkanMACDValues &macd_values);
DaijunkanMACDValues CalculateDaijunkanMACD();
void CheckActiveEntrySignals(bool &buy_trigger, bool &sell_trigger, string &buy_signal_name, string &sell_signal_name); // ← この行を確認
int GetPrimaryStage(int shift);
string MasterStateToString(ENUM_MASTER_STATE state, color &out_color);
string SlopeStateToString(ENUM_SLOPE_STATE state);

// --- ポジション管理 & Zephyr関連 ---
void InitGroup(PositionGroup &group, bool isBuy);
void ManagePositionGroups();
void UpdateGroupSL(PositionGroup &group);
void UpdateGroupSplitLines(PositionGroup &group);
void CheckExitForGroup(PositionGroup &group);
bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose);
void ManageTrailingSL(PositionGroup &group);
void ModifyPositionSL(ulong ticket, double sl_price);
void SetBreakEvenForGroup(PositionGroup &group);
bool SetBreakEven(ulong ticket, double entryPrice);
void ClosePosition(ulong ticket);
void CloseAllPositionsInGroup(PositionGroup &group);
void SyncManagedPositions();

// --- シグナル生成 & ライン管理 ---
void ProcessLineSignals();
void CheckLineSignals(Line &line);
void CheckStochasticSignal();
void CheckZoneMacdCross();
bool CheckMACDDivergence(bool is_buy_signal, int macd_handle);
void UpdateLines();
int GetLineState(string lineName);
void ManageManualLines();

// --- 描画 & UI関連 ---
void ManagePivotLines();
void CalculatePivot();
void DrawManualTrendLine(double price, datetime time);
void ManageSlLines();
void UpdateZones();
void ManageZoneVisuals();
void UpdateAllVisuals();
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string msg);
void DrawDivergenceSignal(datetime time, double price, color clr);
void UpdateInfoPanel_NewBar(); // ManageInfoPanelから変更
void UpdateInfoPanel_Timer();  // ManageInfoPanelから変更
void DrawPanelLine(int line_index, string text, string icon, color text_color, color icon_color, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor, int font_size, bool is_lower);
void UpdateButtonState();
void UpdateZoneButtonState();
bool CreateApexButton(string name, int x, int y, int width, int height, string text, color clr);
void CreateManualLineButton();
void CreateClearButton();
void CreateClearLinesButton();
void ClearSignalObjects();
void ClearManualLines();
void DeleteAllEaObjects();
void DeleteGroupSplitLines(PositionGroup &group);
string GetSwingRatioInfo(int tf_index, color &out_color);


// --- その他ヘルパー ---
void CleanupExpiredSignalObjects(); // ▼▼▼【この行を追加】▼▼▼
bool IsNewBar();
double CalculateRiskBasedLotSize(int score);
double GetConversionRate(string from_currency, string to_currency);

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                 主要なイベントハンドラ関数                     |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| エキスパート初期化関数 (ZigZagハンドル統一版)
//+------------------------------------------------------------------+
int OnInit()
{
    g_pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pow(10, _Digits % 2);
    g_lastBarTime = 0;
    lastTradeTime = 0;
    g_lastPivotDrawTime = 0;

    if(InpUseExternalIndicator)
    {
        h_turning_point = iCustom(
            _Symbol, _Period, "HT_Turning_Point_V1.030",
            19, 0, 16748574, 255, 0, 1000, 3.0, 2000, "", 1, 158, 158, "", 
            true, true, 1, 217, 218, 119, 119, true, 1, "ファイル名.wav", "", 
            false, 6, "ファイル名.wav", false
        );
        if(h_turning_point == INVALID_HANDLE)
        {
            Print("外部インジケーター[HT_Turning_Point_V1.030]のハンドル作成に失敗しました。");
            return(INIT_FAILED);
        }
    }

    ENUM_TIMEFRAMES mtf_periods[ENUM_TIMEFRAMES_COUNT];
    mtf_periods[TF_CURRENT_INDEX]      = _Period;
    mtf_periods[TF_INTERMEDIATE_INDEX] = InpIntermediateTimeframe;
    mtf_periods[TF_HIGHER_INDEX]       = InpHigherTimeframe;

    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++)
    {
        h_gc_ma_short_mtf[i] = iMA(_Symbol, mtf_periods[i], InpGCMAShortPeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
        h_gc_ma_middle_mtf[i] = iMA(_Symbol, mtf_periods[i], InpGCMAMiddlePeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
        h_gc_ma_long_mtf[i] = iMA(_Symbol, mtf_periods[i], InpGCMALongPeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
        h_atr_slope_mtf[i] = iATR(_Symbol, mtf_periods[i], InpSlopeAtrPeriod);
        
        // ▼▼▼ ここを修正 ▼▼▼
        // TP計算用と同じパラメータ(InpZigzag...)でハンドルを作成する
        h_zigzag_swing[i] = iCustom(_Symbol, mtf_periods[i], "ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);
        // ▲▲▲ ここまで修正 ▲▲▲
        
        h_atr_swing[i]    = iATR(_Symbol, mtf_periods[i], InpSlopeAtrPeriod);
        
        if(h_gc_ma_short_mtf[i] == INVALID_HANDLE || h_gc_ma_middle_mtf[i] == INVALID_HANDLE || 
           h_gc_ma_long_mtf[i] == INVALID_HANDLE || h_atr_slope_mtf[i] == INVALID_HANDLE ||
           h_zigzag_swing[i] == INVALID_HANDLE || h_atr_swing[i] == INVALID_HANDLE)
        {
            PrintFormat("MTFインジケータハンドル (%s) の作成に失敗しました。", EnumToString(mtf_periods[i]));
            return(INIT_FAILED);
        }
    }

    if(InpStoch_UseDaiJunkan)
    {
        h_main_stoch = iStochastic(_Symbol, _Period, InpMainStoch_K_Period, InpMainStoch_D_Period, InpMainStoch_Slowing, MODE_SMA, STO_LOWHIGH);
        h_sub_stoch  = iStochastic(_Symbol, _Period, InpSubStoch_K_Period, InpSubStoch_D_Period, InpSubStoch_Slowing, MODE_SMA, STO_LOWHIGH);
    }
    h_atr_sl = iATR(_Symbol, InpAtrSlTimeframe, 14);
    
    // TP計算用のZigZagは元の "ZigZag" のまま
    zigzagHandle = iCustom(_Symbol, InpTP_Timeframe, "ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);

    h_macd_exec = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    h_macd_mid  = iMACD(_Symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
    h_macd_long = iMACD(_Symbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE);
    h_rsi = iRSI(_Symbol, _Period, Inp_RSI_Period, PRICE_CLOSE);
    if(h_rsi == INVALID_HANDLE)
    {
        Print("RSIインジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }
    
    if((InpStoch_UseDaiJunkan && (h_main_stoch == INVALID_HANDLE || h_sub_stoch == INVALID_HANDLE)) || h_atr_sl == INVALID_HANDLE || zigzagHandle == INVALID_HANDLE || h_macd_exec == INVALID_HANDLE || h_macd_mid == INVALID_HANDLE || h_macd_long == INVALID_HANDLE)
    {
        Print("一部のインジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }
    
    InitGroup(buyGroup, true);
    InitGroup(sellGroup, false);
    isBuyTPManuallyMoved = false;
    isSellTPManuallyMoved = false;
    g_isZoneVisualizationEnabled = InpVisualizeZones;
    
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);
    prev_tp_mode = InpTPLineMode;
    prev_tp_timeframe = InpTP_Timeframe;
    if(InpShowInfoPanel) CreateInfoPanel();

    Print("ApexFlowEA (市場サイクルモデル) 初期化完了");
    if(InpShowInfoPanel) UpdateInfoPanel_NewBar(); // ← この行を追加
    EventSetTimer(1);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    DeleteAllEaObjects();
    
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++)
    {
        IndicatorRelease(h_gc_ma_short_mtf[i]);
        IndicatorRelease(h_gc_ma_middle_mtf[i]);
        IndicatorRelease(h_gc_ma_long_mtf[i]);
        IndicatorRelease(h_atr_slope_mtf[i]);
    }

    if(InpStoch_UseDaiJunkan)
    {
        IndicatorRelease(h_main_stoch);
        IndicatorRelease(h_sub_stoch);
    }
    IndicatorRelease(h_atr_sl);
    IndicatorRelease(zigzagHandle);
    IndicatorRelease(h_macd_exec);
    IndicatorRelease(h_macd_mid);
    IndicatorRelease(h_macd_long);
    
    if(h_turning_point != INVALID_HANDLE)
    {
        IndicatorRelease(h_turning_point);
    }

    ChartRedraw();
    PrintFormat("ApexFlowEA 終了: 理由=%d。", reason);
}

//+------------------------------------------------------------------+
//| エキスパートティック関数 (データ処理に専念)
//+------------------------------------------------------------------+
void OnTick()
{
    // 毎ティック必ず分析と決済チェックを行う
    UpdateEnvironmentAnalysis();
    CheckStateBasedExits();
    CheckExitForGroup(buyGroup);
    CheckExitForGroup(sellGroup);
    ManageTrailingSL(buyGroup);
    ManageTrailingSL(sellGroup);

    // 新しい足ができたタイミングでのみ実行する処理
    if(IsNewBar())
    {
        if(InpShowInfoPanel) UpdateInfoPanel_NewBar(); // ← この行を追加
        ArrayFree(allLines);
        CleanupExpiredSignalObjects();
        ManageManualLines();
        if (InpUsePivotLines) CalculatePivot();
        if(InpUseExternalIndicator) UpdateTurningPointLines();
        UpdateLines();
        ProcessLineSignals();
        CheckStochasticSignal();
        CheckPriceActionSignal();
        CheckRsiMaSignal();        
        CheckEntry();
        SyncManagedPositions();
        ManagePositionGroups();
    }
}

//+------------------------------------------------------------------+
//| タイマー処理関数 (オブジェクト操作安全版)
//+------------------------------------------------------------------+
void OnTimer()
{
    // ▼▼▼【ここから追加】決済後のオブジェクト削除処理 ▼▼▼
    if(g_buyGroupJustClosed)
    {
        DeleteGroupSplitLines(buyGroup);
        g_buyGroupJustClosed = false; // フラグをリセット
    }
    if(g_sellGroupJustClosed)
    {
        DeleteGroupSplitLines(sellGroup);
        g_sellGroupJustClosed = false; // フラグをリセット
    }
    // ▲▲▲【追加ここまで】▲▲▲

    // 全てのUIコントロールを監視・管理
    ManageUIControls();

    // 情報パネルを更新
    if(InpShowInfoPanel) UpdateInfoPanel_Timer();

    // 新しい足ができたタイミングでのみ、重い描画処理を実行
    static datetime last_bar_time_for_timer = 0;
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    if(last_bar_time_for_timer < current_bar_time)
    {
       last_bar_time_for_timer = current_bar_time;
       
       // 全ての描画関連関数をここで呼び出す
       ManagePivotLines();
       VisualizeExternalLines();
       UpdateZones();
       ManageSlLines();
       UpdateGroupSplitLines(buyGroup);
       UpdateGroupSplitLines(sellGroup);
       ManageZoneVisuals();
       ManageSwingVisuals(); // スイング描画を追加

    }
    
    // 最後に一度だけチャートを再描画
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == g_buttonName) { g_isDrawingMode = !g_isDrawingMode; if(g_isDrawingMode) g_ignoreNextChartClick = true; UpdateButtonState(); return; }
        if(sparam == g_clearButtonName) { ClearSignalObjects(); ChartRedraw(); return; }
        if(sparam == g_clearLinesButtonName) { ClearManualLines(); ChartRedraw(); return; }
        
        if(sparam == BUTTON_BUY_CLOSE_ALL)  { Print("ログ: 手動決済 'BUY 全決済'"); CloseAllPositionsInGroup(buyGroup); return; }
        if(sparam == BUTTON_SELL_CLOSE_ALL) { Print("ログ: 手動決済 'SELL 全決済'"); CloseAllPositionsInGroup(sellGroup); return; }
        if(sparam == BUTTON_ALL_CLOSE)      { Print("ログ: 手動決済 '全決済'"); CloseAllPositionsInGroup(buyGroup); CloseAllPositionsInGroup(sellGroup); return; }

        if(sparam == BUTTON_RESET_BUY_TP) { isBuyTPManuallyMoved = false; if(ObjectFind(0, "TPLine_Buy") >= 0) ObjectSetInteger(0, "TPLine_Buy", OBJPROP_STYLE, STYLE_DOT); UpdateAllVisuals(); return; }
        if(sparam == BUTTON_RESET_SELL_TP){ isSellTPManuallyMoved = false; if(ObjectFind(0, "TPLine_Sell") >= 0) ObjectSetInteger(0, "TPLine_Sell", OBJPROP_STYLE, STYLE_DOT); UpdateAllVisuals(); return; }

        if(sparam == BUTTON_RESET_BUY_SL)  { isBuySLManuallyMoved = false; g_slLinePrice_Buy = 0; ManageSlLines(); if(buyGroup.isActive){ UpdateGroupSL(buyGroup); UpdateGroupSplitLines(buyGroup); } ChartRedraw(); return; }
        if(sparam == BUTTON_RESET_SELL_SL) { isSellSLManuallyMoved = false; g_slLinePrice_Sell = 0; ManageSlLines(); if(sellGroup.isActive){ UpdateGroupSL(sellGroup); UpdateGroupSplitLines(sellGroup); } ChartRedraw(); return; }
        
        if(sparam == BUTTON_TOGGLE_ZONES) { g_isZoneVisualizationEnabled = !g_isZoneVisualizationEnabled; UpdateZoneButtonState(); UpdateLines(); ManageZoneVisuals(); ChartRedraw(); return; }
    }

    if(id == CHARTEVENT_CLICK)
    {
        if(g_ignoreNextChartClick) { g_ignoreNextChartClick = false; return; }
        if(g_isDrawingMode)
        {
            datetime clicked_time; double clicked_price; int subwindow;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subwindow, clicked_time, clicked_price))
            {
                DrawManualTrendLine(clicked_price, clicked_time);
            }
            g_isDrawingMode = false;
            UpdateButtonState();
        }
        return;
    }
    
    if(id == CHARTEVENT_OBJECT_DRAG)
    {
        if(sparam == "TPLine_Buy")  { isBuyTPManuallyMoved = true; ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID); }
        if(sparam == "TPLine_Sell") { isSellTPManuallyMoved = true; ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID); }
        if(sparam == "SLLine_Buy")  isBuySLManuallyMoved = true;
        if(sparam == "SLLine_Sell") isSellSLManuallyMoved = true;
        return;
    }

    if(id == CHARTEVENT_OBJECT_ENDEDIT)
    {
        if(StringFind(sparam, "TPLine_") == 0 || StringFind(sparam, "SLLine_") == 0)
        {
            ChartRedraw();
        }
        return;
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                    分析エンジン & ロジック関数                     |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 【FSM修正版】環境分析を実行し、結果をg_env_stateに格納する (MTF対応版)
//+------------------------------------------------------------------+
void UpdateEnvironmentAnalysis()
{
    // --- 1. 毎ティック最新のデータを計算 ---
    ZeroMemory(g_env_state); // グローバル環境状態をリセット

    // 使用する時間足の期間を設定
    ENUM_TIMEFRAMES mtf_periods[ENUM_TIMEFRAMES_COUNT];
    mtf_periods[TF_CURRENT_INDEX]      = _Period; // 執行足
    mtf_periods[TF_INTERMEDIATE_INDEX] = InpIntermediateTimeframe; // 中間時間足
    mtf_periods[TF_HIGHER_INDEX]       = InpHigherTimeframe; // 上位時間足

    // 各時間足の分析データを収集
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++)
    {
        ENUM_TIMEFRAMES current_tf = mtf_periods[i];
        
        // ---【変更点】ここからサブステート判定ロジック ---
        // (1) 伝統的なステージを現在足と1本前で取得
        int current_primary_stage = GetPrimaryStage(0, current_tf, h_gc_ma_short_mtf[i], h_gc_ma_middle_mtf[i], h_gc_ma_long_mtf[i]);
        int prev_primary_stage    = GetPrimaryStage(1, current_tf, h_gc_ma_short_mtf[i], h_gc_ma_middle_mtf[i], h_gc_ma_long_mtf[i]);
        
        // (2) 各時間足の傾きと大循環MACDを計算
        g_env_state.mtf_slope_short[i]  = GetSlopeState(h_gc_ma_short_mtf[i], InpSlopeLookback, current_tf);
        g_env_state.mtf_slope_middle[i] = GetSlopeState(h_gc_ma_middle_mtf[i], InpSlopeLookback, current_tf);
        g_env_state.mtf_slope_long[i]   = GetSlopeState(h_gc_ma_long_mtf[i], InpSlopeLookback, current_tf);
        g_env_state.mtf_macd_values[i] = CalculateDaijunkanMACD(current_tf, h_gc_ma_short_mtf[i], h_gc_ma_middle_mtf[i], h_gc_ma_long_mtf[i]);
        
        // (3) 新しいGetMasterState関数を呼び出して、正しいサブステートを格納
        g_env_state.mtf_master_state[i] = GetMasterState(
            current_primary_stage,
            prev_primary_stage,
            g_env_state.mtf_slope_long[i],
            g_env_state.mtf_slope_short[i],
            g_env_state.mtf_macd_values[i]
        );
        // ---【変更点】ここまで ---
    }

    // --- 2. 執行足の情報をg_env_stateの単一変数にもコピー（パネル表示などの互換性のため） ---
    g_env_state.master_state = g_env_state.mtf_master_state[TF_CURRENT_INDEX];
    g_env_state.primary_stage = GetPrimaryStage(0, _Period, h_gc_ma_short_mtf[TF_CURRENT_INDEX], h_gc_ma_middle_mtf[TF_CURRENT_INDEX], h_gc_ma_long_mtf[TF_CURRENT_INDEX]);
    g_env_state.prev_primary_stage = GetPrimaryStage(1, _Period, h_gc_ma_short_mtf[TF_CURRENT_INDEX], h_gc_ma_middle_mtf[TF_CURRENT_INDEX], h_gc_ma_long_mtf[TF_CURRENT_INDEX]);
    g_env_state.slope_short  = g_env_state.mtf_slope_short[TF_CURRENT_INDEX];
    g_env_state.slope_middle = g_env_state.mtf_slope_middle[TF_CURRENT_INDEX];
    g_env_state.slope_long   = g_env_state.mtf_slope_long[TF_CURRENT_INDEX];
    g_env_state.macd_values  = g_env_state.mtf_macd_values[TF_CURRENT_INDEX];

    // --- 3. 総合スコアと取引バイアスを決定する新しい関数を呼び出す ---
    CalculateOverallBiasAndScore();
    
    // UpdateScoresBasedOnState(); // この行は古いロジックのため不要
}

//+------------------------------------------------------------------+
//| 【市場サイクルモデル版】総合優位性スコアと取引バイアスを計算する
//+------------------------------------------------------------------+
void CalculateOverallBiasAndScore()
{
    // --- スコアリング ---
    g_env_state.total_buy_score = 0;
    g_env_state.total_sell_score = 0;
    int weights[ENUM_TIMEFRAMES_COUNT];
    weights[TF_CURRENT_INDEX]      = InpWeightCurrentTF;
    weights[TF_INTERMEDIATE_INDEX] = InpWeightIntermediateTF;
    weights[TF_HIGHER_INDEX]       = InpWeightHigherTF;
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++)
    {
        ENUM_MASTER_STATE master_state = g_env_state.mtf_master_state[i];
        ENUM_SLOPE_STATE long_slope = g_env_state.mtf_slope_long[i];
        ENUM_SLOPE_STATE short_slope = g_env_state.mtf_slope_short[i];
        DaijunkanMACDValues macd = g_env_state.mtf_macd_values[i];
        int weight = weights[i];
        switch(master_state)
        {
            case STATE_1B_CONFIRMED: g_env_state.total_buy_score += (InpScore_State_Confirmed * weight / 10); break;
            case STATE_3_REJECTION:  g_env_state.total_buy_score += (InpScore_State_Rejection * weight / 10); break;
            case STATE_1A_NASCENT:   g_env_state.total_buy_score += (InpScore_State_Nascent * weight / 10); break;
            case STATE_2_PULLBACK:   g_env_state.total_buy_score += (InpScore_State_Pullback * weight / 10);  break;
            case STATE_6_TRANSITION_UP: g_env_state.total_buy_score += (InpScore_State_Transition * weight / 10); break;
            case STATE_1C_MATURE:    g_env_state.total_buy_score += (InpScore_State_Mature * weight / 10); break;
            case STATE_4B_CONFIRMED: g_env_state.total_sell_score += (InpScore_State_Confirmed * weight / 10); break;
            case STATE_6_REJECTION:  g_env_state.total_sell_score += (InpScore_State_Rejection * weight / 10); break;
            case STATE_4A_NASCENT:   g_env_state.total_sell_score += (InpScore_State_Nascent * weight / 10); break;
            case STATE_5_RALLY:      g_env_state.total_sell_score += (InpScore_State_Pullback * weight / 10);  break;
            case STATE_3_TRANSITION_DOWN: g_env_state.total_sell_score += (InpScore_State_Transition * weight / 10); break;
            case STATE_4C_MATURE:    g_env_state.total_sell_score += (InpScore_State_Mature * weight / 10); break;
        }
        if (long_slope == SLOPE_UP_STRONG) g_env_state.total_buy_score += (InpScore_Slope_Long_Strong * weight / 10);
        if (long_slope == SLOPE_UP_WEAK)   g_env_state.total_buy_score += (InpScore_Slope_Long_Weak * weight / 10);
        if (long_slope == SLOPE_DOWN_STRONG) g_env_state.total_sell_score += (InpScore_Slope_Long_Strong * weight / 10);
        if (long_slope == SLOPE_DOWN_WEAK)   g_env_state.total_sell_score += (InpScore_Slope_Long_Weak * weight / 10);
        if (i == TF_CURRENT_INDEX)
        {
            if (short_slope == SLOPE_UP_STRONG) g_env_state.total_buy_score += (InpScore_Slope_Short * weight / 10);
            if (short_slope == SLOPE_DOWN_STRONG) g_env_state.total_sell_score += (InpScore_Slope_Short * weight / 10);
        }
        if (macd.is_obi_gc) g_env_state.total_buy_score += (InpScore_MACD_Cross * weight / 10);
        if (macd.is_obi_dc) g_env_state.total_sell_score += (InpScore_MACD_Cross * weight / 10);
        if (macd.obi_macd > 0 && macd.obi_macd_slope > 0) g_env_state.total_buy_score += (InpScore_MACD_Momentum * weight / 10);
        if (macd.obi_macd < 0 && macd.obi_macd_slope < 0) g_env_state.total_sell_score += (InpScore_MACD_Momentum * weight / 10);
    }

    // --- 新しいバイアス判定ロジック ---
    g_env_state.current_trade_bias = BIAS_UNCLEAR; // デフォルトは「不明確」
    g_env_state.current_bias_phase = PHASE_NONE;   // フェーズもリセット

    ENUM_MASTER_STATE h_tf = g_env_state.mtf_master_state[TF_HIGHER_INDEX];
    ENUM_MASTER_STATE m_tf = g_env_state.mtf_master_state[TF_INTERMEDIATE_INDEX];
    ENUM_MASTER_STATE c_tf = g_env_state.mtf_master_state[TF_CURRENT_INDEX];

    // --- 🚀 完全順行 (買い) ---
    if (h_tf == STATE_1B_CONFIRMED && m_tf == STATE_1B_CONFIRMED && c_tf == STATE_1B_CONFIRMED) {
        g_env_state.current_trade_bias = BIAS_DOMINANT_CORE_TREND_BUY;
    } else if (h_tf == STATE_1B_CONFIRMED && m_tf == STATE_1B_CONFIRMED && c_tf == STATE_2_PULLBACK) {
        g_env_state.current_trade_bias = BIAS_DOMINANT_PULLBACK_BUY;
    }
    // --- 🚀 完全順行 (売り) ---
    else if (h_tf == STATE_4B_CONFIRMED && m_tf == STATE_4B_CONFIRMED && c_tf == STATE_4B_CONFIRMED) {
        g_env_state.current_trade_bias = BIAS_DOMINANT_CORE_TREND_SELL;
    } else if (h_tf == STATE_4B_CONFIRMED && m_tf == STATE_4B_CONFIRMED && c_tf == STATE_5_RALLY) {
        g_env_state.current_trade_bias = BIAS_DOMINANT_PULLBACK_SELL;
    }
    // --- 📈 順張り局面 (買い) ---
    else if ((h_tf == STATE_6_TRANSITION_UP || h_tf == STATE_1A_NASCENT) && (m_tf == STATE_1A_NASCENT || m_tf == STATE_1B_CONFIRMED)) {
        g_env_state.current_trade_bias = BIAS_ALIGNED_EARLY_ENTRY_BUY;
    } else if (h_tf == STATE_1B_CONFIRMED && m_tf == STATE_1B_CONFIRMED) {
         g_env_state.current_trade_bias = BIAS_ALIGNED_CORE_TREND_BUY;
    }
    // --- 📈 順張り局面 (売り) ---
    else if ((h_tf == STATE_3_TRANSITION_DOWN || h_tf == STATE_4A_NASCENT) && (m_tf == STATE_4A_NASCENT || m_tf == STATE_4B_CONFIRMED)) {
        g_env_state.current_trade_bias = BIAS_ALIGNED_EARLY_ENTRY_SELL;
    } else if (h_tf == STATE_4B_CONFIRMED && m_tf == STATE_4B_CONFIRMED) {
         g_env_state.current_trade_bias = BIAS_ALIGNED_CORE_TREND_SELL;
    }
    // --- ✨ 特殊局面 (シェイクアウト) ---
    else if (c_tf == STATE_3_REJECTION && (h_tf == STATE_1B_CONFIRMED || h_tf == STATE_2_PULLBACK)) {
        g_env_state.current_trade_bias = BIAS_SHAKEOUT_BUY;
    } else if (c_tf == STATE_6_REJECTION && (h_tf == STATE_4B_CONFIRMED || h_tf == STATE_5_RALLY)) {
        g_env_state.current_trade_bias = BIAS_SHAKEOUT_SELL;
    }
    // --- ⚠️ 逆行警戒 ---
    else if (h_tf == STATE_1B_CONFIRMED && (m_tf == STATE_4A_NASCENT || m_tf == STATE_4B_CONFIRMED || m_tf == STATE_5_RALLY)) {
        g_env_state.current_trade_bias = BIAS_CONFLICTING_PULLBACK_BUY;
    } else if (h_tf == STATE_4B_CONFIRMED && (m_tf == STATE_1A_NASCENT || m_tf == STATE_1B_CONFIRMED || m_tf == STATE_2_PULLBACK)) {
        g_env_state.current_trade_bias = BIAS_CONFLICTING_PULLBACK_SELL;
    }
    // --- 🏁 決済重視 (トレンド枯渇) ---
    else if (h_tf == STATE_1C_MATURE || m_tf == STATE_1C_MATURE) {
        g_env_state.current_trade_bias = BIAS_TREND_EXHAUSTION_BUY;
    } else if (h_tf == STATE_4C_MATURE || m_tf == STATE_4C_MATURE) {
        g_env_state.current_trade_bias = BIAS_TREND_EXHAUSTION_SELL;
    }
    // --- 🧘 レンジ相場 ---
    else {
        g_env_state.current_trade_bias = BIAS_RANGE_BOUND; // どの強いパターンにも当てはまらない場合はレンジと見なす
    }
}

//+------------------------------------------------------------------+
//| 状態に基づいて決済を判断する統合関数 (市場サイクルモデル版)
//+------------------------------------------------------------------+
void CheckStateBasedExits()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        if (PositionSelectByTicket(ticket))
        {
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool should_close = false;
            string reason = "";

            if (pos_type == POSITION_TYPE_BUY)
            {
                if(InpExit_OnTrendEnd && !should_close)
                {
                    if (g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_1C_MATURE || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_2_REVERSAL_WARN || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_4B_CONFIRMED || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_6_REJECTION)
                    {
                        should_close = true;
                        reason = "トレンド終焉/転換警告";
                    }
                }
                if(InpExit_OnCounterBias && !should_close)
                {
                    // --- ▼▼▼ ここを修正 ▼▼▼ ---
                    bool is_sell_bias = (g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_SELL ||
                                         g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_SELL ||
                                         g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_SELL ||
                                         g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_SELL);
                    if(is_sell_bias)
                    {
                        should_close = true;
                        reason = "反対バイアス発生";
                    }
                    // --- ▲▲▲ ここまで修正 ▲▲▲ ---
                }
                if(InpExit_OnRange && !should_close)
                {
                    // --- ▼▼▼ ここを修正 ▼▼▼ ---
                    if(g_env_state.current_trade_bias == BIAS_RANGE_BOUND)
                    {
                        should_close = true;
                        reason = "レンジ相場突入";
                    }
                    // --- ▲▲▲ ここまで修正 ▲▲▲ ---
                }
            }
            else // SELL
            {
                if(InpExit_OnTrendEnd && !should_close)
                {
                    if(g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_4C_MATURE || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_5_REVERSAL_WARN || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_1B_CONFIRMED || g_env_state.mtf_master_state[TF_CURRENT_INDEX] == STATE_3_REJECTION)
                    {
                        should_close = true;
                        reason = "トレンド終焉/転換警告";
                    }
                }
                if(InpExit_OnCounterBias && !should_close)
                {
                    // --- ▼▼▼ ここを修正 ▼▼▼ ---
                     bool is_buy_bias = (g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_BUY ||
                                         g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_BUY ||
                                         g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_BUY ||
                                         g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_BUY);
                    if(is_buy_bias)
                    {
                        should_close = true;
                        reason = "反対バイアス発生";
                    }
                    // --- ▲▲▲ ここまで修正 ▲▲▲ ---
                }
                if(InpExit_OnRange && !should_close)
                {
                    // --- ▼▼▼ ここを修正 ▼▼▼ ---
                    if(g_env_state.current_trade_bias == BIAS_RANGE_BOUND)
                    {
                        should_close = true;
                        reason = "レンジ相場突入";
                    }
                    // --- ▲▲▲ ここまで修正 ▲▲▲ ---
                }
            }

            if (!should_close && InpEnableTimeExit)
            {
                datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                int bars_held = iBarShift(_Symbol, _Period, open_time, false);
                if (bars_held > InpExitAfterBars && (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)) < InpExitMinProfit)
                {
                    if (InpTimeExitAction == TIME_EXIT_CLOSE)
                    {
                        should_close = true;
                        reason = "時間経過による決済";
                    }
                    else // TIME_EXIT_RESET_TP
                    {
                        if(pos_type == POSITION_TYPE_BUY)
                        {
                             if (!buyGroup.timeExitResetDone)
                            {
                                PrintFormat("ログ: 時間経過によりBUYポジションのTPをリセットします (トリガーポジション: #%d)", ticket);
                                isBuyTPManuallyMoved = false;
                                buyGroup.timeExitResetDone = true;
                                UpdateAllVisuals();
                            }
                        }
                        else
                        {
                             if (!sellGroup.timeExitResetDone)
                            {
                                PrintFormat("ログ: 時間経過によりSELLポジションのTPをリセットします (トリガーポジション: #%d)", ticket);
                                isSellTPManuallyMoved = false;
                                sellGroup.timeExitResetDone = true;
                                UpdateAllVisuals();
                            }
                        }
                    }
                }
            }

            if (!should_close && InpEnableCounterSignalExit)
            {
                if(pos_type == POSITION_TYPE_BUY && g_env_state.total_sell_score >= InpCounterSignalScore)
                {
                    should_close = true;
                    reason = "反対スコア到達 (" + (string)g_env_state.total_sell_score + ")";
                }
                if(pos_type == POSITION_TYPE_SELL && g_env_state.total_buy_score >= InpCounterSignalScore)
                {
                    should_close = true;
                    reason = "反対スコア到達 (" + (string)g_env_state.total_buy_score + ")";
                }
            }

            if (should_close)
            {
                PrintFormat("決済実行 (%s): ポジション #%d を決済します。", reason, ticket);
                ClosePosition(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 新規エントリーを探す (スコア差オーバーライド機能付き)
//+------------------------------------------------------------------+
void CheckEntry()
{
    bool buy_trigger = false;
    bool sell_trigger = false;
    string found_buy_signal = "";
    string found_sell_signal = "";
    CheckActiveEntrySignals(buy_trigger, sell_trigger, found_buy_signal, found_sell_signal);

    if (!buy_trigger && !sell_trigger) return;

    Print("-------------------- [エントリー診断] --------------------");
    if(buy_trigger) PrintFormat("診断: BUYシグナル『%s』を検知しました。", found_buy_signal);
    if(sell_trigger) PrintFormat("診断: SELLシグナル『%s』を検知しました。", found_sell_signal);

    if (TimeCurrent() <= lastTradeTime + 5)
    {
        Print("診断結果: エントリー見送り (理由: 前回のトレードから5秒以内)");
        Print("----------------------------------------------------------");
        return;
    }

    if(buy_trigger)
    {
        PrintFormat("診断 (BUY): 現在の買いスコア = %d, 必要スコア = %d", g_env_state.total_buy_score, InpEntryScore);
        if (g_env_state.total_buy_score < InpEntryScore)
        {
            Print("診断結果 (BUY): エントリー見送り (理由: スコア不足)");
        }
        else
        {
            Print("診断 (BUY): スコア条件クリア");
            bool is_buy_bias = (g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_BUY ||
                                g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_BUY ||
                                g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_BUY ||
                                g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_BUY ||
                                g_env_state.current_trade_bias == BIAS_SHAKEOUT_BUY);
            bool range_entry_ok = (InpAllowRangeEntry && g_env_state.current_trade_bias == BIAS_RANGE_BOUND);
            
            // ★★★ 新しいロジック: スコア差によるバイアス条件のオーバーライド ★★★
            bool score_diff_override = InpAllowEntryOnScoreDiff && (g_env_state.total_buy_score - g_env_state.total_sell_score >= InpMinScoreDiffForEntry);

            string bias_jp_text = ""; string temp_icon; color temp_color;
            TradeBiasToString(g_env_state.current_trade_bias, bias_jp_text, temp_icon, temp_color);
            PrintFormat("診断 (BUY): 現在の取引バイアス = %s", bias_jp_text);

            if (!(is_buy_bias || range_entry_ok || score_diff_override))
            {
                Print("診断結果 (BUY): エントリー見送り (理由: 取引バイアス不一致、かつスコア差も不足)");
            }
            else
            {
                if(score_diff_override && !(is_buy_bias || range_entry_ok))
                {
                   PrintFormat("診断 (BUY): バイアスは不一致ですが、スコア差(%d)が閾値(%d)を超えたためエントリー条件をオーバーライドします。", g_env_state.total_buy_score - g_env_state.total_sell_score, InpMinScoreDiffForEntry);
                }
                else
                {
                   Print("診断 (BUY): バイアス条件クリア");
                }
                
                // ▼▼▼ ここからRRRフィルター ▼▼▼
                MqlTick tick;
                if(!SymbolInfoTick(_Symbol, tick)) return;
                
                double entry_price = tick.ask;
                double sl_price = CalculateEntryStopLoss(true);
                double tp_price = zonalFinalTPLine_Buy;
                if(sl_price <= 0 || tp_price <= 0) {
                    Print("診断結果 (BUY): エントリー見送り (理由: RRR計算用のSL/TP価格が無効です)");
                } else {
                    double risk_distance = MathAbs(entry_price - sl_price);
                    double reward_distance = MathAbs(tp_price - entry_price);

                    if(risk_distance < _Point) {
                        Print("診断結果 (BUY): エントリー見送り (理由: リスク値が0のためRRR計算不能)");
                    } else {
                        double rrr = reward_distance / risk_distance;
                        PrintFormat("診断 (BUY): RRR = %.2f (リワード:%.5f / リスク:%.5f), 最低RRR = %.2f", rrr, reward_distance, risk_distance, InpEntry_MinRewardRiskRatio);
                        if(rrr < InpEntry_MinRewardRiskRatio) {
                            Print("診断結果 (BUY): エントリー見送り (理由: リスクリワード比が不足)");
                        } else {
                            Print("診断 (BUY): RRR条件クリア");
                            // ▲▲▲ RRRフィルターここまで ▲▲▲

                            if (buyGroup.positionCount >= InpMaxPositions)
                            {
                                PrintFormat("診断結果 (BUY): エントリー見送り (理由: 最大ポジション数到達 %d/%d)", buyGroup.positionCount, InpMaxPositions);
                            }
                            else
                            {
                                Print("診断 (BUY): 最大ポジション数クリア");
                                Print("診断結果 (BUY): 全ての条件をクリア。エントリーを実行します。");
                                PlaceOrder(true, entry_price, g_env_state.total_buy_score);
                            }
                        }
                    }
                }
            }
        }
    }

    if(sell_trigger)
    {
        PrintFormat("診断 (SELL): 現在の売りスコア = %d, 必要スコア = %d", g_env_state.total_sell_score, InpEntryScore);
        if (g_env_state.total_sell_score < InpEntryScore)
        {
            Print("診断結果 (SELL): エントリー見送り (理由: スコア不足)");
        }
        else
        {
            Print("診断 (SELL): スコア条件クリア");
            bool is_sell_bias = (g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_SELL ||
                                 g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_SELL ||
                                 g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_SELL ||
                                 g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_SELL ||
                                 g_env_state.current_trade_bias == BIAS_SHAKEOUT_SELL);
            bool range_entry_ok = (InpAllowRangeEntry && g_env_state.current_trade_bias == BIAS_RANGE_BOUND);

            // ★★★ 新しいロジック: スコア差によるバイアス条件のオーバーライド ★★★
            bool score_diff_override = InpAllowEntryOnScoreDiff && (g_env_state.total_sell_score - g_env_state.total_buy_score >= InpMinScoreDiffForEntry);

            string bias_jp_text = ""; string temp_icon; color temp_color;
            TradeBiasToString(g_env_state.current_trade_bias, bias_jp_text, temp_icon, temp_color);
            PrintFormat("診断 (SELL): 現在の取引バイアス = %s", bias_jp_text);
            
            if (!(is_sell_bias || range_entry_ok || score_diff_override))
            {
                Print("診断結果 (SELL): エントリー見送り (理由: 取引バイアス不一致、かつスコア差も不足)");
            }
            else
            {
                 if(score_diff_override && !(is_sell_bias || range_entry_ok))
                {
                   PrintFormat("診断 (SELL): バイアスは不一致ですが、スコア差(%d)が閾値(%d)を超えたためエントリー条件をオーバーライドします。", g_env_state.total_sell_score - g_env_state.total_buy_score, InpMinScoreDiffForEntry);
                }
                else
                {
                   Print("診断 (SELL): バイアス条件クリア");
                }
                
                // ▼▼▼ ここからRRRフィルター ▼▼▼
                MqlTick tick;
                if(!SymbolInfoTick(_Symbol, tick)) return;

                double entry_price = tick.bid;
                double sl_price = CalculateEntryStopLoss(false);
                double tp_price = zonalFinalTPLine_Sell;
                if(sl_price <= 0 || tp_price <= 0) {
                    Print("診断結果 (SELL): エントリー見送り (理由: RRR計算用のSL/TP価格が無効です)");
                } else {
                    double risk_distance = MathAbs(entry_price - sl_price);
                    double reward_distance = MathAbs(tp_price - entry_price);

                    if(risk_distance < _Point) {
                        Print("診断結果 (SELL): エントリー見送り (理由: リスク値が0のためRRR計算不能)");
                    } else {
                        double rrr = reward_distance / risk_distance;
                        PrintFormat("診断 (SELL): RRR = %.2f (リワード:%.5f / リスク:%.5f), 最低RRR = %.2f", rrr, reward_distance, risk_distance, InpEntry_MinRewardRiskRatio);
                        if(rrr < InpEntry_MinRewardRiskRatio) {
                            Print("診断結果 (SELL): エントリー見送り (理由: リスクリワード比が不足)");
                        } else {
                            Print("診断 (SELL): RRR条件クリア");
                            // ▲▲▲ RRRフィルターここまで ▲▲▲

                            if (sellGroup.positionCount >= InpMaxPositions)
                            {
                                PrintFormat("診断結果 (SELL): エントリー見送り (理由: 最大ポジション数到達 %d/%d)", sellGroup.positionCount, InpMaxPositions);
                            }
                            else
                            {
                                Print("診断 (SELL): 最大ポジション数クリア");
                                Print("診断結果 (SELL): 全ての条件をクリア。エントリーを実行します。");
                                PlaceOrder(false, entry_price, g_env_state.total_sell_score);
                            }
                        }
                    }
                }
            }
        }
    }
    Print("----------------------------------------------------------");
}

//+------------------------------------------------------------------+
//| 【フィルター用】エントリー前のSL価格を計算する
//+------------------------------------------------------------------+
double CalculateEntryStopLoss(bool isBuy)
{
    // このフィルターでは、ユーザーの指示通り「反対TPライン」のみをSLの基準とし、ATRバッファは考慮しない
    if(isBuy)
    {
        // 買いエントリーの場合、SLの基準は「売りの最終TPライン」
        if(zonalFinalTPLine_Sell > 0) return(zonalFinalTPLine_Sell);
    }
    else
    {
        // 売りエントリーの場合、SLの基準は「買いの最終TPライン」
        if(zonalFinalTPLine_Buy > 0) return(zonalFinalTPLine_Buy);
    }
    
    // 反対TPラインが存在しない場合は0を返す
    return(0.0);
}

//+------------------------------------------------------------------+
//| 注文を発注する (ATRバッファー付きSLロジック版)
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, int score)
{
    double lot_size = InpEnableRiskBasedLot ? CalculateRiskBasedLotSize(score) : InpLotSize;
    if (lot_size <= 0) { PrintFormat("ロットサイズの計算結果が0以下のため、エントリーを中止しました。"); return; }

    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    
    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = lot_size;
    req.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price = NormalizeDouble(price, _Digits);
    req.magic = InpMagicNumber;
    string bias_text = EnumToString(g_env_state.current_trade_bias) + " [" + EnumToString(g_env_state.current_bias_phase) + "]";
    req.comment = StringFormat("%s (Score:%d, Bias:%s)", (string)(isBuy ? "Buy" : "Sell"), score, bias_text);
    req.type_filling = ORDER_FILLING_FOK;

    if(!OrderSend(req, res))
    {
        PrintFormat("OrderSend error: %d - %s", GetLastError(), res.comment);
    }
    else
    {
        PrintFormat("エントリー実行: %s, Price: %.5f, Lots: %.2f", req.comment, price, lot_size);
        lastTradeTime = TimeCurrent();

        if(res.deal > 0 && HistoryDealSelect(res.deal))
        {
            long ticket = HistoryDealGetInteger(res.deal, DEAL_POSITION_ID);
            if(PositionSelectByTicket(ticket))
            {
                PositionInfo newPos;
                newPos.ticket = ticket;
                newPos.score = score;
                int size = ArraySize(g_managedPositions);
                ArrayResize(g_managedPositions, size + 1);
                g_managedPositions[size] = newPos;

                double sl_base_price = 0;
                if(InpSlMode == SL_MODE_OPPOSITE_TP) sl_base_price = isBuy ? zonalFinalTPLine_Sell : zonalFinalTPLine_Buy;
                else if(InpSlMode == SL_MODE_MANUAL) sl_base_price = isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell;

                if(sl_base_price > 0)
                {
                    double atr_buffer[1];
                    double atr_value = 0;
                    if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
                    {
                        atr_value = atr_buffer[0];
                    }
                    double sl_buffer = atr_value * InpAtrBufferMultiplier;
                    double final_sl_price = isBuy ? (sl_base_price - sl_buffer) : (sl_base_price + sl_buffer);
                    ModifyPositionSL(ticket, final_sl_price);
                }

                ManagePositionGroups();
                ChartRedraw();
            }
        }
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|              分析およびシグナル生成のヘルパー関数                |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 傾き正規化用のATRハンドルを初期化する
//+------------------------------------------------------------------+
bool InitSlopeAtr()
{
    h_atr_slope = iATR(_Symbol, _Period, InpSlopeAtrPeriod);
    if(h_atr_slope == INVALID_HANDLE)
    {
        Print("傾き正規化用ATRハンドルの作成に失敗しました。");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| 移動平均線の傾斜状態を取得する (MTF対応版)
//+------------------------------------------------------------------+
ENUM_SLOPE_STATE GetSlopeState(int ma_handle, int lookback, ENUM_TIMEFRAMES tf_period)
{
    double ma_buffer[];
    if(CopyBuffer(ma_handle, 0, 0, lookback + 1, ma_buffer) < lookback + 1)
    {
        PrintFormat("GetSlopeState: MAデータ(%s)の取得に失敗。", EnumToString(tf_period));
        return SLOPE_FLAT;
    }

    double atr_buffer[];
    int atr_handle_index = -1; 
    if (tf_period == _Period) atr_handle_index = TF_CURRENT_INDEX;
    else if (tf_period == InpIntermediateTimeframe) atr_handle_index = TF_INTERMEDIATE_INDEX;
    else if (tf_period == InpHigherTimeframe) atr_handle_index = TF_HIGHER_INDEX;

    if (atr_handle_index == -1 || CopyBuffer(h_atr_slope_mtf[atr_handle_index], 0, 0, 1, atr_buffer) < 1) 
    {
        // PrintFormat("GetSlopeState: ATRデータ(%s)の取得に失敗。", EnumToString(tf_period)); // デバッグ用
        return SLOPE_FLAT;
    }

    double current_ma = ma_buffer[0];
    double past_ma = ma_buffer[lookback];
    double atr_value = atr_buffer[0];

    if (atr_value < _Point) return SLOPE_FLAT; // ATRが極めて小さい場合は横ばいと見なす

    double normalized_slope = (current_ma - past_ma) / atr_value;

    if (normalized_slope > InpSlopeUpStrong)    return SLOPE_UP_STRONG;
    if (normalized_slope > InpSlopeUpWeak)      return SLOPE_UP_WEAK;
    if (normalized_slope < InpSlopeDownStrong)  return SLOPE_DOWN_STRONG;
    if (normalized_slope < InpSlopeDownWeak)    return SLOPE_DOWN_WEAK;

    return SLOPE_FLAT;
}

//+------------------------------------------------------------------+
//| 【新規】仕様書に基づき、詳細なマスター状態（サブステート）を判定する
//+------------------------------------------------------------------+
ENUM_MASTER_STATE GetMasterState(
    int primary_stage, 
    int prev_primary_stage, 
    ENUM_SLOPE_STATE slope_long, 
    ENUM_SLOPE_STATE slope_short, 
    const DaijunkanMACDValues &macd_values
)
{
    // 仕様書(3.1, 3.3)に基づき、トレンドの成熟度を判定
    if (primary_stage == 1 && slope_short <= SLOPE_FLAT) return STATE_1C_MATURE;
    if (primary_stage == 4 && slope_short >= SLOPE_FLAT) return STATE_4C_MATURE;

    // 仕様書(4.2, 4.3)に基づき、ステージ移行の成否を判定
    switch(primary_stage)
    {
        // --- ステージ 1, 4 (パーフェクトオーダー) ---
        case 1:
            // 仕様書(3.1): 長期MAの傾きで「本物」か「予兆」かを判断
            if (slope_long >= SLOPE_UP_WEAK) return STATE_1B_CONFIRMED;   // 本物
            else return STATE_1A_NASCENT;                                // 予兆
            
        case 4:
            // 仕様書(3.3): 長期MAの傾きで「本物」か「予兆」かを判断
            if (slope_long <= SLOPE_DOWN_WEAK) return STATE_4B_CONFIRMED; // 本物
            else return STATE_4A_NASCENT;                                // 予兆

        // --- ステージ 2, 5 (調整局面) ---
        case 2:
            // 仕様書(3.2): 長期MAの傾きが強ければ「押し目」、弱まっていれば「転換警告」
            if (slope_long >= SLOPE_UP_STRONG) return STATE_2_PULLBACK;      // シナリオA: 押し目買い
            else return STATE_2_REVERSAL_WARN;                               // シナリオB: トレンド転換警告
            
        case 5:
            // 仕様書(3.4): 長期MAの傾きが強ければ「戻り」、弱まっていれば「転換警告」
            if (slope_long <= SLOPE_DOWN_STRONG) return STATE_5_RALLY;       // シナリオA: 戻り売り
            else return STATE_5_REVERSAL_WARN;                               // シナリオB: トレンド転換警告

        // --- ステージ 3, 6 (反転開始) ---
        case 3:
            // 仕様書(4.3): 前ステージが2で、長期MAがまだ上向きなら「下降失敗」
            if (prev_primary_stage == 2 && slope_long >= SLOPE_FLAT) return STATE_3_REJECTION; // 低確率シナリオ(逆行): シェイクアウト
            else return STATE_3_TRANSITION_DOWN;                                              // 高確率シナリオ(順行): 下降へ移行

        case 6:
            // 仕様書(4.2): 前ステージが5で、長期MAがまだ下向きなら「上昇失敗」
            if (prev_primary_stage == 5 && slope_long <= SLOPE_FLAT) return STATE_6_REJECTION; // 低確率シナリオ(逆行): 上昇拒否
            else return STATE_6_TRANSITION_UP;                                                // 高確率シナリオ(順行): 上昇へ移行
    }

    return STATE_UNKNOWN; // 不明な状態
}

//+------------------------------------------------------------------+
//| 大循環MACDの値を計算する (MTF対応版)
//+------------------------------------------------------------------+
DaijunkanMACDValues CalculateDaijunkanMACD(ENUM_TIMEFRAMES tf_period, int short_ma_handle, int middle_ma_handle, int long_ma_handle)
{
    DaijunkanMACDValues result;
    ZeroMemory(result);

    int buffer_size = 15; // 計算に必要なバッファサイズ
    double short_ma[], middle_ma[], long_ma[];
    if(CopyBuffer(short_ma_handle, 0, 0, buffer_size, short_ma) < buffer_size ||
       CopyBuffer(middle_ma_handle, 0, 0, buffer_size, middle_ma) < buffer_size ||
       CopyBuffer(long_ma_handle, 0, 0, buffer_size, long_ma) < buffer_size)
    {
        PrintFormat("CalculateDaijunkanMACD: データ(%s)の取得に失敗。", EnumToString(tf_period));
        return result;
    }

    // 現在のMACD値
    result.macd1 = short_ma[0] - middle_ma[0];
    result.macd2 = short_ma[0] - long_ma[0];
    result.obi_macd = middle_ma[0] - long_ma[0];

    // 帯MACDのヒストリカルデータを作成し、シグナルラインを計算
    double obi_macd_history[];
    ArrayResize(obi_macd_history, buffer_size);
    for(int i = 0; i < buffer_size; i++)
    {
        obi_macd_history[i] = middle_ma[i] - long_ma[i];
    }

    int signal_period = 9; // 大循環MACDのシグナル期間
    if(buffer_size >= signal_period)
    {
        double signal_sum = 0;
        for(int i = 0; i < signal_period; i++) signal_sum += obi_macd_history[i];
        result.signal = signal_sum / signal_period;
    }

    // 帯MACDとシグナルラインのクロス判定
    if(buffer_size >= signal_period + 1) // 1本前のデータも必要
    {
        double prev_obi_macd = obi_macd_history[1]; // 1本前の帯MACD
        double prev_signal_sum = 0;
        for(int i = 1; i < signal_period + 1; i++) prev_signal_sum += obi_macd_history[i];
        double prev_signal = prev_signal_sum / signal_period;

        // ゴールデンクロス (GC)
        if(prev_obi_macd <= prev_signal && result.obi_macd > result.signal) result.is_obi_gc = true;
        // デッドクロス (DC)
        if(prev_obi_macd >= prev_signal && result.obi_macd < result.signal) result.is_obi_dc = true;
    }

    // 帯MACDの傾きを計算
    if (buffer_size >= 2) // 1本前の帯MACDが必要
    {
         double prev_obi_macd_for_slope = obi_macd_history[1];
         result.obi_macd_slope = result.obi_macd - prev_obi_macd_for_slope;
    }


    return result;
}

//+------------------------------------------------------------------+
//| 伝統的な大循環分析のステージ番号を取得する (MTF対応版)
//+------------------------------------------------------------------+
int GetPrimaryStage(int shift, ENUM_TIMEFRAMES tf_period, int short_ma_handle, int middle_ma_handle, int long_ma_handle)
{
    double s[], m[], l[];
    if(CopyBuffer(short_ma_handle, 0, shift, 1, s) < 1 ||
       CopyBuffer(middle_ma_handle, 0, shift, 1, m) < 1 ||
       CopyBuffer(long_ma_handle, 0, shift, 1, l) < 1)
    {
        PrintFormat("GetPrimaryStage: データ(%s)の取得に失敗。", EnumToString(tf_period));
        return 0;
    }

    if (s[0] > m[0] && m[0] > l[0]) return 1;
    if (m[0] > s[0] && s[0] > l[0]) return 2;
    if (m[0] > l[0] && l[0] > s[0]) return 3;
    if (l[0] > m[0] && m[0] > s[0]) return 4;
    if (l[0] > s[0] && s[0] > m[0]) return 5;
    if (s[0] > l[0] && l[0] > m[0]) return 6;

    return 0; // どのステージにも当てはまらない場合
}

//+------------------------------------------------------------------+
//| 全てのラインをチェックしてシグナルを生成する
//+------------------------------------------------------------------+
void ProcessLineSignals()
{
    for (int i = 0; i < ArraySize(allLines); i++)
    {
        CheckLineSignals(allLines[i]);
    }
}

//+------------------------------------------------------------------+
//| ラインに対するシグナルを検出する (ゾーンモード拡張版)
//+------------------------------------------------------------------+
void CheckLineSignals(Line &line)
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 5, rates) < 5) return;
    ArraySetAsSeries(rates, true);

    int stateIndex = GetLineState(line.name);
    if((g_lineStates[stateIndex].isBrokeUp || g_lineStates[stateIndex].isBrokeDown) && !InpAllowSignalAfterBreak) return;

    datetime prevBarTime = rates[1].time;
    double offset = InpSignalOffsetPips * g_pip;
    double prev_open = rates[1].open;
    double prev_high = rates[1].high;
    double prev_low = rates[1].low;
    double prev_close = rates[1].close;

    // ▼▼▼【ここを修正】▼▼▼
    // ゾーンモード選択時にも、タッチモードのロジックが実行されるように条件を変更
    if(InpEntryMode == TOUCH_MODE || InpEntryMode == ZONE_MODE)
    // ▲▲▲【ここまで修正】▲▲▲
    {
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(prev_open <= line.price && prev_high >= line.price && prev_close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Sell_" + line.name, prevBarTime, line.price + offset, line.signalColor, InpTouchReboundDownCode, "");
            }
            if(InpBreakMode && !g_lineStates[stateIndex].isBrokeUp && prev_open < line.price && prev_close >= line.price)
            {
                CreateSignalObject(InpArrowPrefix + "TouchBreak_Buy_" + line.name, prevBarTime, prev_low - offset, line.signalColor, InpTouchBreakUpCode, "");
                g_lineStates[stateIndex].isBrokeUp = true;
            }
        }
        else // LINE_TYPE_SUPPORT
        {
            if(prev_open >= line.price && prev_low <= line.price && prev_close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Buy_" + line.name, prevBarTime, line.price - offset, line.signalColor, InpTouchReboundUpCode, "");
            }
            if(InpBreakMode && !g_lineStates[stateIndex].isBrokeDown && prev_open > line.price && prev_close <= line.price)
            {
                CreateSignalObject(InpArrowPrefix + "TouchBreak_Sell_" + line.name, prevBarTime, prev_high + offset, line.signalColor, InpTouchBreakDownCode, "");
                g_lineStates[stateIndex].isBrokeDown = true;
            }
        }
    }
    
    // InpEntryModeがZONE_MODEの時だけ、このブロックが動作する
    if(InpEntryMode == ZONE_MODE)
    {
        if (g_lineStates[stateIndex].waitForRetestUp || g_lineStates[stateIndex].waitForRetestDown)
        {
            int barsSinceBreak = iBarShift(_Symbol, _Period, g_lineStates[stateIndex].breakTime);
            if (barsSinceBreak > InpRetestExpiryBars && InpRetestExpiryBars > 0)
            {
                g_lineStates[stateIndex].waitForRetestUp = false;
                g_lineStates[stateIndex].waitForRetestDown = false;
            }
        }

        double zone_width = InpZonePips * g_pip;

        // --- ゾーンバウンス・ロジック ---
        if(line.type == LINE_TYPE_SUPPORT)
        {
            double zone_top = line.price;
            double zone_bottom = line.price - zone_width;
            if(rates[1].close > zone_top && rates[2].close < zone_top)
            {
                bool no_break = (rates[1].low > zone_bottom && rates[2].low > zone_bottom && rates[3].low > zone_bottom);
                if(no_break)
                {
                    CreateSignalObject(InpArrowPrefix + "ZoneBounce_Buy_" + line.name, prevBarTime, prev_low - offset, clrDeepSkyBlue, InpZoneBounceBuyCode, "");
                }
            }
        }
        else 
        {
            double zone_top = line.price + zone_width;
            double zone_bottom = line.price;
            if(rates[1].close < zone_bottom && rates[2].close > zone_bottom)
            {
                bool no_break = (rates[1].high < zone_top && rates[2].high < zone_top && rates[3].high < zone_top);
                if(no_break)
                {
                    CreateSignalObject(InpArrowPrefix + "ZoneBounce_Sell_" + line.name, prevBarTime, prev_high + offset, clrHotPink, InpZoneBounceSellCode, "");
                }
            }
        }

        // --- フォールスブレイクとブレイク＆リテスト ---
        if (line.type == LINE_TYPE_RESISTANCE)
        {
            if (prev_high > line.price + zone_width && prev_close < line.price)
            {
                CreateSignalObject(InpDotPrefix + "FalseBreak_Sell_" + line.name, prevBarTime, prev_high + offset, clrHotPink, InpFalseBreakSellCode, "");
                g_lineStates[stateIndex].breakTime = prevBarTime;
            }
            else if (g_lineStates[stateIndex].waitForRetestUp)
            {
                if (prev_low <= line.price && prev_close > line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Buy_" + line.name, prevBarTime, prev_low - offset, clrDeepSkyBlue, InpRetestBuyCode, "");
                    g_lineStates[stateIndex].waitForRetestUp = false;
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
            else if (!g_lineStates[stateIndex].isBrokeUp)
            {
                if (prev_open < line.price && prev_close > line.price)
                {
                    g_lineStates[stateIndex].isBrokeUp = true;
                    g_lineStates[stateIndex].waitForRetestUp = true; 
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
        }
        else // LINE_TYPE_SUPPORT
        {
            if (prev_low < line.price - zone_width && prev_close > line.price)
            {
                CreateSignalObject(InpDotPrefix + "FalseBreak_Buy_" + line.name, prevBarTime, prev_low - offset, clrDeepSkyBlue, InpFalseBreakBuyCode, "");
                g_lineStates[stateIndex].breakTime = prevBarTime;
            }
            else if (g_lineStates[stateIndex].waitForRetestDown)
            {
                if (prev_high >= line.price && prev_close < line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Sell_" + line.name, prevBarTime, prev_high + offset, clrHotPink, InpRetestSellCode, "");
                    g_lineStates[stateIndex].waitForRetestDown = false;
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
            else if (!g_lineStates[stateIndex].isBrokeDown)
            {
                if (prev_open > line.price && prev_close < line.price)
                {
                    g_lineStates[stateIndex].isBrokeDown = true;
                    g_lineStates[stateIndex].waitForRetestDown = true;
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 【大循環ストキャス版】新しいロジックでシグナルをチェックする (モード選択機能付き)
//+------------------------------------------------------------------+
void CheckStochasticSignal()
{
    if(!InpStoch_UseDaiJunkan) return;

    // --- 1. データをバッファにコピー ---
    double main_k_buffer[3], main_d_buffer[3];
    if(CopyBuffer(h_main_stoch, 0, 0, 3, main_k_buffer) < 3 || CopyBuffer(h_main_stoch, 1, 0, 3, main_d_buffer) < 3) return;
    double sub_d_buffer[2];
    if(InpStoch_UseFilters){ if(CopyBuffer(h_sub_stoch, 1, 0, 2, sub_d_buffer) < 2) return; }
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 1, 1, rates) < 1) return;
    datetime bar_time = rates[0].time;

    // --- 2. 基本エントリーシグナルのチェック ---
    bool isBuySignal = (main_d_buffer[1] >= InpMainStoch_Lower_Level && main_d_buffer[2] < InpMainStoch_Lower_Level);
    bool isSellSignal = (main_d_buffer[1] <= InpMainStoch_Upper_Level && main_d_buffer[2] > InpMainStoch_Upper_Level);
    if(!isBuySignal && !isSellSignal) return; // シグナルがなければここで終了

    // --- 3. シグナル発生場所の妥当性チェック ---
    bool is_valid_location = false;
    if(InpStoch_SignalMode == MODE_EVERYWHERE)
    {
        is_valid_location = true; // どこでもOK
    }
    else // MODE_ZONE_ONLY
    {
        MqlTick tick;
        if(SymbolInfoTick(_Symbol, tick))
        {
            double zoneWidth = InpZonePips * g_pip;
            for (int i = 0; i < ArraySize(allLines); i++)
            {
                Line line = allLines[i];
                double upper_zone = line.price + zoneWidth;
                double lower_zone = line.price - zoneWidth;
                // 買いシグナルはサポートゾーン内かチェック
                if (isBuySignal && line.type == LINE_TYPE_SUPPORT && tick.ask > lower_zone && tick.ask < upper_zone)
                {
                    is_valid_location = true;
                    break;
                }
                // 売りシグナルはレジスタンスゾーン内かチェック
                if (isSellSignal && line.type == LINE_TYPE_RESISTANCE && tick.bid > lower_zone && tick.bid < upper_zone)
                {
                    is_valid_location = true;
                    break;
                }
            }
        }
    }
    
    // 場所が不適切ならここで終了
    if(!is_valid_location) return;

    // --- 4. フィルター機能の適用 ---
    bool passes_filter = !InpStoch_UseFilters; // フィルターOFFなら常にtrue
    if(InpStoch_UseFilters)
    {
        bool sub_stoch_ok = (sub_d_buffer[1] <= InpMainStoch_Lower_Level || sub_d_buffer[1] >= InpMainStoch_Upper_Level);
        if(isBuySignal && sub_stoch_ok && (main_k_buffer[1] > main_k_buffer[2])) passes_filter = true;
        if(isSellSignal && sub_stoch_ok && (main_k_buffer[1] < main_k_buffer[2])) passes_filter = true;
    }
    
    // --- 5. シグナル描画 ---
    if(passes_filter)
    {
        double offset = InpSignalOffsetPips * g_pip;
        if(isBuySignal) CreateSignalObject(InpArrowPrefix + "Stoch_Buy_" + TimeToString(bar_time), bar_time, rates[0].low - offset, clrDeepSkyBlue, 233, "");
        if(isSellSignal) CreateSignalObject(InpArrowPrefix + "Stoch_Sell_" + TimeToString(bar_time), bar_time, rates[0].high + offset, clrHotPink, 234, "");
    }
}

//+------------------------------------------------------------------+
//| ゾーン内でのMACDクロスエントリーをチェックする (警告修正版)
//+------------------------------------------------------------------+
void CheckZoneMacdCross()
{
    if (!InpEnableZoneMacdCross || (InpEntryMode != ZONE_MODE)) return;
    static datetime lastZoneCrossEntryTime = 0;
    if (TimeCurrent() < lastZoneCrossEntryTime + PeriodSeconds()) return;

    double exec_main[3], exec_signal[3];
    // ---【修正点】以下の行を削除 ---
    // ArraySetAsSeries(exec_main, true); ArraySetAsSeries(exec_signal, true); // 不要なため削除
    
    if (CopyBuffer(h_macd_exec, 0, 0, 3, exec_main) < 3 || CopyBuffer(h_macd_exec, 1, 0, 3, exec_signal) < 3) return;

    // このロジックは「2本前の足と1本前の足の間でクロスが完了したか」をチェックしています
    bool isBuyCross = (exec_main[2] < exec_signal[2] && exec_main[1] > exec_signal[1]);
    bool isSellCross = (exec_main[2] > exec_signal[2] && exec_main[1] < exec_signal[1]);
    if (!isBuyCross && !isSellCross) return;

    MqlTick tick;
    if (!SymbolInfoTick(_Symbol, tick)) return;
    double zoneWidth = InpZonePips * g_pip;

    for (int i = 0; i < ArraySize(allLines); i++)
    {
        Line line = allLines[i];
        double upper_zone = line.price + zoneWidth;
        double lower_zone = line.price - zoneWidth;

        if (isBuyCross && line.type == LINE_TYPE_SUPPORT && tick.ask > lower_zone && tick.ask < upper_zone)
        {
            // エントリー判断はMTF総合スコアを利用するよう修正
            if (g_env_state.total_buy_score >= InpEntryScore)
            {
                PlaceOrder(true, tick.ask, g_env_state.total_buy_score);
                lastZoneCrossEntryTime = TimeCurrent();
                return;
            }
        }
        if (isSellCross && line.type == LINE_TYPE_RESISTANCE && tick.bid > lower_zone && tick.bid < upper_zone)
        {
            // エントリー判断はMTF総合スコアを利用するよう修正
            if (g_env_state.total_sell_score >= InpEntryScore)
            {
                PlaceOrder(false, tick.bid, g_env_state.total_sell_score);
                lastZoneCrossEntryTime = TimeCurrent();
                return;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| MACDのダイバージェンスを検出
//+------------------------------------------------------------------+
bool CheckMACDDivergence(bool is_buy_signal, int macd_handle)
{
    MqlRates rates[];
    double macd_main[];
    int check_bars = 30;

    if(ArrayResize(rates, check_bars) < 0 || ArrayResize(macd_main, check_bars) < 0) return false;
    
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(macd_main, true);

    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, check_bars, rates) < check_bars) return false;
    if(CopyBuffer(macd_handle, 0, 0, check_bars, macd_main) < check_bars) return false;
    
    int p1_idx = -1, p2_idx = -1;
    if(is_buy_signal)
    {
        for(int i = 1; i < check_bars - 1; i++)
        {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
            {
                if(p1_idx == -1) p1_idx = i;
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].low < rates[p2_idx].low && macd_main[p1_idx] > macd_main[p2_idx])
            {
                DrawDivergenceSignal(rates[p1_idx].time, rates[p1_idx].low - InpDivSymbolOffsetPips * g_pip, InpBullishDivColor);
                return true;
            }
        }
    }
    else
    {
        for(int i = 1; i < check_bars - 1; i++)
        {
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
            {
                if(p1_idx == -1) p1_idx = i;
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].high > rates[p2_idx].high && macd_main[p1_idx] < macd_main[p2_idx])
            {
                DrawDivergenceSignal(rates[p1_idx].time, rates[p1_idx].high + InpDivSymbolOffsetPips * g_pip, InpBearishDivColor);
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|              ポジションおよび取引関連のヘルパー関数              |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ポジショングループを初期化する
//+------------------------------------------------------------------+
void InitGroup(PositionGroup &group, bool isBuy)
{
    group.isBuy = isBuy;
    group.isActive = false;
    group.averageEntryPrice = 0;
    group.totalLotSize = 0;
    group.initialTotalLotSize = 0;
    group.previousTotalLotSize = 0;
    group.splitsDone = 0;
    group.lockedInSplitCount = 0;
    group.openTime = 0;
    group.stampedFinalTP = 0;
    group.averageScore = 0;
    group.highestScore = 0;
    group.positionCount = 0;
    group.timeExitResetDone = false;
    ArrayFree(group.positionTickets);
    ArrayFree(group.splitPrices);
    ArrayFree(group.splitLineNames);
    ArrayFree(group.splitLineTimes);
}

//+------------------------------------------------------------------+
//| ポジショングループの状態を更新する (最終修正版)
//+------------------------------------------------------------------+
void ManagePositionGroups()
{
    PositionGroup oldBuyGroup = buyGroup;
    PositionGroup oldSellGroup = sellGroup;
    buyGroup.previousTotalLotSize = oldBuyGroup.totalLotSize;
    sellGroup.previousTotalLotSize = oldSellGroup.totalLotSize;
    buyGroup.totalLotSize = 0;
    sellGroup.totalLotSize = 0;
    buyGroup.highestScore = 0;
    sellGroup.highestScore = 0;
    ArrayFree(buyGroup.positionTickets);
    ArrayFree(sellGroup.positionTickets);
    buyGroup.isActive = false;
    sellGroup.isActive = false;
    double buyWeightedSum = 0, sellWeightedSum = 0;
    double buyTotalScoreLot = 0, sellTotalScoreLot = 0;
    datetime buyEarliestTime = 0, sellEarliestTime = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double volume = PositionGetDouble(POSITION_VOLUME);
            datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
            int score = 0;
            for(int j = 0; j < ArraySize(g_managedPositions); j++)
            {
                if(g_managedPositions[j].ticket == ticket) { score = g_managedPositions[j].score; break; }
            }
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                buyGroup.isActive = true;
                buyGroup.totalLotSize += volume;
                buyWeightedSum += price * volume;
                int size = ArraySize(buyGroup.positionTickets);
                ArrayResize(buyGroup.positionTickets, size + 1);
                buyGroup.positionTickets[size] = ticket;
                buyTotalScoreLot += score * volume;
                if(score > buyGroup.highestScore) buyGroup.highestScore = score;
                if(buyEarliestTime == 0 || posOpenTime < buyEarliestTime) buyEarliestTime = posOpenTime;
            }
            else
            {
                sellGroup.isActive = true;
                sellGroup.totalLotSize += volume;
                sellWeightedSum += price * volume;
                int size = ArraySize(sellGroup.positionTickets);
                ArrayResize(sellGroup.positionTickets, size + 1);
                sellGroup.positionTickets[size] = ticket;
                sellTotalScoreLot += score * volume;
                if(score > sellGroup.highestScore) sellGroup.highestScore = score;
                if(sellEarliestTime == 0 || posOpenTime < sellEarliestTime) sellEarliestTime = posOpenTime;
            }
        }
    }

    if(buyGroup.isActive)
    {
        if(buyGroup.totalLotSize > 0)
        {
            buyGroup.averageEntryPrice = buyWeightedSum / buyGroup.totalLotSize;
            buyGroup.averageScore = buyTotalScoreLot / buyGroup.totalLotSize;
        }
        buyGroup.positionCount = ArraySize(buyGroup.positionTickets);
        if(!oldBuyGroup.isActive)
        {
            buyGroup.initialTotalLotSize = buyGroup.totalLotSize;
            buyGroup.splitsDone = 0;
            buyGroup.lockedInSplitCount = InpSplitCount;
            buyGroup.timeExitResetDone = false;
            if(!isBuyTPManuallyMoved)
            {
                double sl_price = 0;
                if(buyGroup.positionCount > 0 && PositionSelectByTicket(buyGroup.positionTickets[0])) sl_price = PositionGetDouble(POSITION_SL);
                if(sl_price > 0)
                {
                    double sl_distance = MathAbs(buyGroup.averageEntryPrice - sl_price);
                    double final_tp = buyGroup.averageEntryPrice + (sl_distance * InpFinalTpRR_Ratio);
                    if (buyGroup.highestScore >= InpHighScoreThreshold) final_tp = buyGroup.averageEntryPrice + (sl_distance * InpFinalTpRR_Ratio * InpHighSchoreTpRratio);
                    buyGroup.stampedFinalTP = final_tp;
                } else {
                    UpdateZones();
                    buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
                }
            }
            buyGroup.openTime = buyEarliestTime;
        }
        else
        {
            buyGroup.initialTotalLotSize = oldBuyGroup.initialTotalLotSize;
            buyGroup.splitsDone = oldBuyGroup.splitsDone;
            buyGroup.lockedInSplitCount = oldBuyGroup.lockedInSplitCount;
            buyGroup.openTime = oldBuyGroup.openTime;
            buyGroup.timeExitResetDone = oldBuyGroup.timeExitResetDone;
            if (!isBuyTPManuallyMoved) { buyGroup.stampedFinalTP = zonalFinalTPLine_Buy; }
            else { buyGroup.stampedFinalTP = oldBuyGroup.stampedFinalTP; }
        }
        
        // ▼▼▼【ここを修正】古いパラメータ参照を削除 ▼▼▼
        if(oldBuyGroup.positionCount != buyGroup.positionCount) UpdateGroupSL(buyGroup);
    }
    else if(oldBuyGroup.isActive)
    {
        g_buyGroupJustClosed = true;
        isBuyTPManuallyMoved = false;
        InitGroup(buyGroup, true);
    }
    
    if(sellGroup.isActive)
    {
        if(sellGroup.totalLotSize > 0)
        {
            sellGroup.averageEntryPrice = sellWeightedSum / sellGroup.totalLotSize;
            sellGroup.averageScore = sellTotalScoreLot / sellGroup.totalLotSize;
        }
        sellGroup.positionCount = ArraySize(sellGroup.positionTickets);
        if(!oldSellGroup.isActive)
        {
            sellGroup.initialTotalLotSize = sellGroup.totalLotSize;
            sellGroup.splitsDone = 0;
            sellGroup.lockedInSplitCount = InpSplitCount;
            sellGroup.timeExitResetDone = false;
            if(!isSellTPManuallyMoved)
            {
                double sl_price = 0;
                if(sellGroup.positionCount > 0 && PositionSelectByTicket(sellGroup.positionTickets[0])) sl_price = PositionGetDouble(POSITION_SL);
                if(sl_price > 0)
                {
                    double sl_distance = MathAbs(sellGroup.averageEntryPrice - sl_price);
                    double final_tp = sellGroup.averageEntryPrice - (sl_distance * InpFinalTpRR_Ratio);
                    if (sellGroup.highestScore >= InpHighScoreThreshold) final_tp = sellGroup.averageEntryPrice - (sl_distance * InpFinalTpRR_Ratio * InpHighSchoreTpRratio);
                    sellGroup.stampedFinalTP = final_tp;
                } else {
                    UpdateZones();
                    sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
                }
            }
            sellGroup.openTime = sellEarliestTime;
        }
        else
        {
            sellGroup.initialTotalLotSize = oldSellGroup.initialTotalLotSize;
            sellGroup.splitsDone = oldSellGroup.splitsDone;
            sellGroup.lockedInSplitCount = oldSellGroup.lockedInSplitCount;
            sellGroup.openTime = oldSellGroup.openTime;
            sellGroup.timeExitResetDone = oldSellGroup.timeExitResetDone;
            if (!isSellTPManuallyMoved) { sellGroup.stampedFinalTP = zonalFinalTPLine_Sell; }
            else { sellGroup.stampedFinalTP = oldSellGroup.stampedFinalTP; }
        }
        
        // ▼▼▼【ここを修正】古いパラメータ参照を削除 ▼▼▼
        if(oldSellGroup.positionCount != sellGroup.positionCount) UpdateGroupSL(sellGroup);
    }
    else if(oldSellGroup.isActive)
    {
        g_sellGroupJustClosed = true;
        isSellTPManuallyMoved = false;
        InitGroup(sellGroup, false);
    }
}

//+------------------------------------------------------------------+
//| グループの分割決済を実行する
//+------------------------------------------------------------------+
bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose)
{
    int ticketCount = ArraySize(group.positionTickets);
    if (ticketCount == 0) return false;
    
    SortablePosition positionsToSort[];
    ArrayResize(positionsToSort, ticketCount);
    for (int i = 0; i < ticketCount; i++)
    {
        if (PositionSelectByTicket(group.positionTickets[i]))
        {
            positionsToSort[i].ticket = group.positionTickets[i];
            positionsToSort[i].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        }
    }

    if (InpExitLogic != EXIT_FIFO)
    {
        for (int i = 0; i < ticketCount - 1; i++)
        {
            for (int j = 0; j < ticketCount - i - 1; j++)
            {
                bool shouldSwap = false;
                if (InpExitLogic == EXIT_UNFAVORABLE)
                {
                    if ((group.isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice) || (!group.isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice)) shouldSwap = true;
                }
                else
                {
                    if ((group.isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice) || (!group.isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice)) shouldSwap = true;
                }
                if (shouldSwap)
                {
                    SortablePosition temp = positionsToSort[j];
                    positionsToSort[j] = positionsToSort[j+1];
                    positionsToSort[j+1] = temp;
                }
            }
        }
    }

    double remainingLotToClose = lotToClose;
    bool result = false;
    for (int i = 0; i < ticketCount; i++)
    {
        ulong ticket = (InpExitLogic == EXIT_FIFO) ? group.positionTickets[i] : positionsToSort[i].ticket;
        if (!PositionSelectByTicket(ticket)) continue;
        
        double posVolume = PositionGetDouble(POSITION_VOLUME);
        if(posVolume <= 0) continue;
        
        MqlTradeRequest request;
        MqlTradeResult tradeResult;
        ZeroMemory(request);
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.type_filling = ORDER_FILLING_IOC;
        
        if (remainingLotToClose >= posVolume)
        {
            request.volume = posVolume;
            if(OrderSend(request, tradeResult))
            {
                remainingLotToClose -= posVolume;
                result = true;
            }
        }
        else
        {
            if (remainingLotToClose > 0)
            {
                request.volume = remainingLotToClose;
                if(OrderSend(request, tradeResult))
                {
                    remainingLotToClose = 0;
                    result = true;
                }
            }
        }
        if (remainingLotToClose < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) break;
    }
    return result;
}

//+------------------------------------------------------------------+
//| グループ内の全ポジションを決済する
//+------------------------------------------------------------------+
void CloseAllPositionsInGroup(PositionGroup &group)
{
    for(int i = ArraySize(group.positionTickets) - 1; i >= 0; i--)
    {
        ClosePosition(group.positionTickets[i]);
    }
}

//+------------------------------------------------------------------+
//| 指定されたチケットのポジションを決済する
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);

    if(!PositionSelectByTicket(ticket))
    {
        PrintFormat("決済エラー: ポジション #%d が見つかりませんでした。", ticket);
        return;
    }

    request.action       = TRADE_ACTION_DEAL;
    request.position     = ticket;
    request.symbol       = PositionGetString(POSITION_SYMBOL);
    request.volume       = PositionGetDouble(POSITION_VOLUME);
    request.deviation    = 100;
    request.type_filling = ORDER_FILLING_IOC;
    request.magic        = InpMagicNumber;
    request.comment      = "ApexFlowEA Close";
    request.type         = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price        = 0;

    if(!OrderSend(request, result))
    {
        PrintFormat("ポジション #%d の決済に失敗しました。エラーコード: %d, サーバー応答: %s", ticket, result.retcode, result.comment);
    }
    else
    {
        PrintFormat("ポジション #%d の決済リクエストを正常に送信しました。", ticket);
    }
}


//+------------------------------------------------------------------+
//| グループ全体のSLを建値（または微益）に設定する
//+------------------------------------------------------------------+
void SetBreakEvenForGroup(PositionGroup &group)
{
    for(int i = 0; i < ArraySize(group.positionTickets); i++)
    {
        SetBreakEven(group.positionTickets[i], group.averageEntryPrice);
    }
}

//+------------------------------------------------------------------+
//| 指定されたポジションのSLを設定する（ブレークイーブン）
//+------------------------------------------------------------------+
bool SetBreakEven(ulong ticket, double entryPrice)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    if(PositionSelectByTicket(ticket))
    {
        double newSL = entryPrice;
        if(InpEnableProfitBE)
        {
            double profit_in_points = InpProfitBE_Pips * g_pip;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) newSL = entryPrice + profit_in_points;
            else newSL = entryPrice - profit_in_points;
        }

        double currentSL = PositionGetDouble(POSITION_SL);
        if(MathAbs(currentSL - newSL) < g_pip) return true;

        req.action = TRADE_ACTION_SLTP;
        req.position = ticket;
        req.symbol = _Symbol;
        req.sl = NormalizeDouble(newSL, _Digits);
        req.tp = PositionGetDouble(POSITION_TP);
        
        double stops_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_pip;
        double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(pos_type == POSITION_TYPE_BUY && req.sl >= current_bid - stops_level) return false;
        if(pos_type == POSITION_TYPE_SELL && req.sl <= current_ask + stops_level) return false;

        if(!OrderSend(req, res))
        {
            PrintFormat("SetBreakEven OrderSend Error: %d", GetLastError());
            return false;
        }
        
        PrintFormat("ポジション #%d のSLを %f に設定しました (利益確保BE)。", ticket, newSL);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 指定したポジションのSL (ストップロス) を変更する
//+------------------------------------------------------------------+
void ModifyPositionSL(ulong ticket, double sl_price)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);

    if (!PositionSelectByTicket(ticket)) return;

    double current_sl = PositionGetDouble(POSITION_SL);
    if (MathAbs(current_sl - sl_price) < g_pip) return;
    // 不利な方向へのSL更新は行わない（BEやトレーリングSLを保護）
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_sl > 0 && sl_price < current_sl) return;
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_sl > 0 && sl_price > current_sl) return;

    request.action   = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol   = _Symbol;
    request.sl       = NormalizeDouble(sl_price, _Digits);
    request.tp       = PositionGetDouble(POSITION_TP);

    // ▼▼▼【ここを修正】▼▼▼
    if (!OrderSend(request, result))
    {
        PrintFormat("ログ: SL変更失敗 (Ticket: #%d) - エラー: %d", ticket, GetLastError());
    }
    else
    {
        PrintFormat("ログ: SL変更成功 (Ticket: #%d) - 新SL: %.5f", ticket, request.sl);
    }
    // ▲▲▲【ここまで修正】▲▲▲
}

//+------------------------------------------------------------------+
//| グループ全体のストップロスを更新する (ATRバッファー付きSLロジック版)
//+------------------------------------------------------------------+
void UpdateGroupSL(PositionGroup &group)
{
    if (!group.isActive) return;
    
    double sl_base_price = 0;
    if(InpSlMode == SL_MODE_OPPOSITE_TP) { sl_base_price = group.isBuy ? zonalFinalTPLine_Sell : zonalFinalTPLine_Buy; }
    else if(InpSlMode == SL_MODE_MANUAL) { sl_base_price = group.isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell; }

    if(sl_base_price > 0)
    {
        double atr_buffer[1];
        double atr_value = 0;
        if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
        {
            atr_value = atr_buffer[0];
        }
        double sl_buffer = atr_value * InpAtrBufferMultiplier;
        double final_sl_price = group.isBuy ? (sl_base_price - sl_buffer) : (sl_base_price + sl_buffer);
        
        for (int i = 0; i < group.positionCount; i++)
        {
            ModifyPositionSL(group.positionTickets[i], final_sl_price);
        }
    }
}

//+------------------------------------------------------------------+
//| グループのトレーリングストップを管理する
//+------------------------------------------------------------------+
void ManageTrailingSL(PositionGroup &group)
{
    if (!InpEnableTrailingSL || !group.isActive || group.splitsDone < InpBreakEvenAfterSplits || InpBreakEvenAfterSplits == 0) return;

    double atr_buffer[1];
    if (CopyBuffer(h_atr_sl, 0, 1, 1, atr_buffer) <= 0) return;
    
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;
    
    double new_sl_price = 0;
    if (group.isBuy) new_sl_price = rates[1].close - (atr_buffer[0] * InpTrailingAtrMultiplier);
    else new_sl_price = rates[1].close + (atr_buffer[0] * InpTrailingAtrMultiplier);

    for (int i = 0; i < group.positionCount; i++)
    {
        ModifyPositionSL(group.positionTickets[i], new_sl_price);
    }
}

//+------------------------------------------------------------------+
//| リスクベースのロットサイズを計算する
//+------------------------------------------------------------------+
double CalculateRiskBasedLotSize(int total_score)
{
    double sl_distance_price = 0;
    double atr_buffer[1];
    if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
    {
        sl_distance_price = atr_buffer[0] * InpAtrBufferMultiplier;
    }
    if (sl_distance_price <= 0)
    {
        Print("ロット計算エラー: SL距離が算出できませんでした。");
        return 0.0;
    }

    double risk_percent_to_use = InpRiskPercent;
    if (InpEnableHighScoreRisk && total_score >= InpHighScoreThreshold)
    {
        risk_percent_to_use = InpHighScoreRiskPercent;
    }

    double risk_amount_account_ccy = AccountInfoDouble(ACCOUNT_BALANCE) * (risk_percent_to_use / 100.0);
    double loss_per_lot_quote_ccy = sl_distance_price * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double conversion_rate = GetConversionRate(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT), AccountInfoString(ACCOUNT_CURRENCY));
    if (conversion_rate <= 0)
    {
        Print("ロット計算エラー: 為替レートが取得できませんでした。");
        return 0.0;
    }

    double loss_per_lot_account_ccy = loss_per_lot_quote_ccy * conversion_rate;
    if(loss_per_lot_account_ccy <= 0) return 0.0;
    
    double desired_lot = risk_amount_account_ccy / loss_per_lot_account_ccy;
    double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double vol_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    double normalized_lot = floor(desired_lot / vol_step) * vol_step;
    if (normalized_lot < vol_min) normalized_lot = vol_min;
    if (normalized_lot > vol_max) normalized_lot = vol_max;

    return normalized_lot;
}

//+------------------------------------------------------------------+
//| 2つの通貨間の為替レートを取得する
//+------------------------------------------------------------------+
double GetConversionRate(string from_currency, string to_currency)
{
    if (from_currency == to_currency) return 1.0;

    string pair_direct = from_currency + to_currency;
    if (SymbolSelect(pair_direct, true)) return SymbolInfoDouble(pair_direct, SYMBOL_ASK);

    string pair_inverse = to_currency + from_currency;
    if (SymbolSelect(pair_inverse, true))
    {
        double inverse_rate = SymbolInfoDouble(pair_inverse, SYMBOL_BID);
        if (inverse_rate > 0) return 1.0 / inverse_rate;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                 描画およびUI関連のヘルパー関数                   |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| パネルの1行を描画するヘルパー関数 (Y座標直接指定版)
//+------------------------------------------------------------------+
void DrawPanelLine(int line_index, int y_pos, string text, string icon, color text_color, color icon_color, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor, int font_size)
{
    string text_obj_name = g_panelPrefix + "Text_" + (string)line_index;
    string icon_obj_name = g_panelPrefix + "Icon_" + (string)line_index;

    int x_pos = p_panel_x_offset;
    int icon_text_gap_left = 210;

    ObjectSetInteger(0, text_obj_name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, text_obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, text_obj_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, text_obj_name, OBJPROP_YDISTANCE, y_pos); // 計算済みのY座標を直接設定
    ObjectSetInteger(0, icon_obj_name, OBJPROP_YDISTANCE, y_pos); // 計算済みのY座標を直接設定
    ObjectSetString(0, text_obj_name, OBJPROP_TEXT, text);
    ObjectSetString(0, icon_obj_name, OBJPROP_TEXT, icon);
    ObjectSetInteger(0, text_obj_name, OBJPROP_COLOR, text_color);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_COLOR, icon_color);

    if(anchor == ANCHOR_RIGHT)
    {
        ObjectSetInteger(0, icon_obj_name, OBJPROP_XDISTANCE, x_pos);
        ObjectSetInteger(0, text_obj_name, OBJPROP_XDISTANCE, x_pos + InpPanelIconGapRight);
    }
    else // ANCHOR_LEFT
    {
        ObjectSetInteger(0, text_obj_name, OBJPROP_XDISTANCE, x_pos);
        ObjectSetInteger(0, icon_obj_name, OBJPROP_XDISTANCE, x_pos + icon_text_gap_left);
    }
}

//+------------------------------------------------------------------+
//| 手動ライン描画ボタンの状態を更新する
//+------------------------------------------------------------------+
void UpdateButtonState()
{
    if(g_isDrawingMode)
    {
        ObjectSetString(0, g_buttonName, OBJPROP_TEXT, "クリックして描画");
        ObjectSetInteger(0, g_buttonName, OBJPROP_BGCOLOR, clrLightGreen);
    }
    else
    {
        ObjectSetString(0, g_buttonName, OBJPROP_TEXT, "手動ライン描画 OFF");
        ObjectSetInteger(0, g_buttonName, OBJPROP_BGCOLOR, C'220,220,220');
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| ゾーン可視化ボタンの状態を更新する
//+------------------------------------------------------------------+
void UpdateZoneButtonState()
{
    string name = BUTTON_TOGGLE_ZONES;
    if(ObjectFind(0, name) < 0) return;

    if(g_isZoneVisualizationEnabled)
    {
        ObjectSetString(0, name, OBJPROP_TEXT, "ゾーン表示: ON");
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrSeaGreen);
    }
    else
    {
        ObjectSetString(0, name, OBJPROP_TEXT, "ゾーン表示: OFF");
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'80,80,80');
    }
}

//+------------------------------------------------------------------+
//| 汎用的なボタンを作成する (OBJ_LABELによる擬似ボタン版)
//+------------------------------------------------------------------+
bool CreateApexButton(string name, int x, int y, int width, int height, string text, color clr)
{
    // ▼▼▼【ここから修正】▼▼▼
    // OBJ_BUTTONの代わりにOBJ_LABELを使用してボタンを作成
    if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
    {
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
        ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_RAISED); // 枠線を追加してボタンらしく見せる
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); // CORNERを明示的に指定
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); // 選択不可にする
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 10); // パネルより手前に表示
        return true;
    }
    return false;
    // ▲▲▲【ここまで修正】▲▲▲
}

//+------------------------------------------------------------------+
//| 手動ライン描画ボタンを作成する
//+------------------------------------------------------------------+
void CreateManualLineButton() 
{
    CreateApexButton(g_buttonName, 10, 50, 120, 20, "手動ライン描画 OFF", C'220,220,220');
}

//+------------------------------------------------------------------+
//| シグナル消去ボタンを作成する
//+------------------------------------------------------------------+
void CreateClearButton() 
{
    CreateApexButton(g_clearButtonName, 10, 75, 120, 20, "シグナル消去", C'255,228,225');
}

//+------------------------------------------------------------------+
//| 手動ライン消去ボタンを作成する
//+------------------------------------------------------------------+
void CreateClearLinesButton() 
{
    CreateApexButton(g_clearLinesButtonName, 10, 100, 120, 20, "手動ライン消去", C'225,240,255');
}

//+------------------------------------------------------------------+
//| 描画されたエントリーシグナルをすべて削除する
//+------------------------------------------------------------------+
void ClearSignalObjects()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, -1);
        if(StringFind(name, InpDotPrefix) == 0 || StringFind(name, InpArrowPrefix) == 0) ObjectDelete(0, name);
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 手動で描画したラインをすべて削除する (管理リスト対応版)
//+------------------------------------------------------------------+
void ClearManualLines()
{
    // ▼▼▼【修正】管理リストにあるオブジェクトのみを削除する ▼▼▼
    for(int i = ArraySize(g_manualLineNames) - 1; i >= 0; i--)
    {
        ObjectDelete(0, g_manualLineNames[i]);
    }
    // 管理リスト自体をクリア
    ArrayFree(g_manualLineNames);
    // ▲▲▲【ここまで修正】▲▲▲

    UpdateLines();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| EAが作成した全てのチャートオブジェクトを削除する (手動ラインは維持する修正版)
//+------------------------------------------------------------------+
void DeleteAllEaObjects()
{
    // ---【修正点】手動ラインの削除コマンドをコメントアウト ---
    // ObjectsDeleteAll(0, "ManualSupport_");
    // ObjectsDeleteAll(0, "ManualResistance_");

    // --- パネルとタイマー ---
    ObjectsDeleteAll(0, g_panelPrefix);
    ObjectsDeleteAll(0, "ApexFlow_TimerLabel");
    // --- 自動描画ライン ---
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);
    ObjectsDeleteAll(0, "TPLine_");
    ObjectsDeleteAll(0, "SLLine_");
    ObjectsDeleteAll(0, "SplitLine_");
    ObjectsDeleteAll(0, "ZoneRect_");
    // --- シグナル ---
    ObjectsDeleteAll(0, InpDotPrefix);
    ObjectsDeleteAll(0, InpArrowPrefix);
    ObjectsDeleteAll(0, InpDivSignalPrefix);
    // --- UIボタン ---
    ObjectsDeleteAll(0, g_buttonName);
    ObjectsDeleteAll(0, g_clearButtonName);
    ObjectsDeleteAll(0, g_clearLinesButtonName);
    ObjectsDeleteAll(0, BUTTON_BUY_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_SELL_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_ALL_CLOSE);
    ObjectsDeleteAll(0, BUTTON_RESET_BUY_TP);
    ObjectsDeleteAll(0, BUTTON_RESET_SELL_TP);
    ObjectsDeleteAll(0, BUTTON_RESET_BUY_SL);
    ObjectsDeleteAll(0, BUTTON_RESET_SELL_SL);
    ObjectsDeleteAll(0, BUTTON_TOGGLE_ZONES);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 分割決済ラインをすべて削除する
//+------------------------------------------------------------------+
void DeleteGroupSplitLines(PositionGroup &group)
{
    string prefix = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_";
    ObjectsDeleteAll(0, prefix);
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                      その他のヘルパー関数                        |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 新しい足ができたかチェックする
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if(g_lastBarTime < currentTime)
    {
        g_lastBarTime = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 管理ポジションリストと実際のポジションを同期する
//+------------------------------------------------------------------+
void SyncManagedPositions()
{
    for(int i = ArraySize(g_managedPositions) - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(g_managedPositions[i].ticket))
        {
            ArrayRemove(g_managedPositions, i, 1);
        }
    }
}

//+------------------------------------------------------------------+
//| マスター状態をパネル表示用の文字列と色に変換する
//+------------------------------------------------------------------+
string MasterStateToString(ENUM_MASTER_STATE state, color &out_color)
{
    string text = "不明";
    out_color = clrGray;

    switch(state)
    {
        case STATE_1A_NASCENT:      text = "[買] 1-A (上昇予兆)";       out_color = clrLimeGreen; break;
        case STATE_1B_CONFIRMED:    text = "[買] 1-B (上昇本物)";       out_color = clrLawnGreen; break;
        case STATE_1C_MATURE:       text = "[待] 1-C (上昇成熟)";       out_color = clrKhaki; break;
        case STATE_2_PULLBACK:      text = "[買] 2 (押し目好機)";      out_color = clrPaleGreen; break;
        case STATE_2_REVERSAL_WARN: text = "[売] 2 (転換警告)";       out_color = clrOrangeRed; break;
        case STATE_3_TRANSITION_DOWN: text = "[売] 3 (下降へ移行)";   out_color = clrSalmon; break;
        case STATE_4A_NASCENT:      text = "[売] 4-A (下降予兆)";       out_color = clrTomato; break;
        case STATE_4B_CONFIRMED:    text = "[売] 4-B (下降本物)";       out_color = clrRed; break;
        case STATE_4C_MATURE:       text = "[待] 4-C (下降成熟)";       out_color = clrDarkSalmon; break;
        case STATE_5_RALLY:         text = "[売] 5 (戻り売り好機)";    out_color = clrMistyRose; break;
        case STATE_5_REVERSAL_WARN: text = "[買] 5 (転換警告)";       out_color = clrLightGreen; break;
        case STATE_6_TRANSITION_UP: text = "[買] 6 (上昇へ移行)";   out_color = clrPaleGreen; break;
        case STATE_6_REJECTION:     text = "[売] 6 (上昇失敗)";       out_color = clrIndianRed; break;
        case STATE_3_REJECTION:     text = "[買] 3 (下降失敗)";       out_color = clrSpringGreen; break;
        default: break;
    }
    return text;
}

//+------------------------------------------------------------------+
//| 傾斜状態をパネル表示用の文字列に変換する
//+------------------------------------------------------------------+
string SlopeStateToString(ENUM_SLOPE_STATE state)
{
    switch(state)
    {
        case SLOPE_UP_STRONG:    return "強い上昇";
        case SLOPE_UP_WEAK:      return "弱い上昇";
        case SLOPE_FLAT:         return "横ばい";
        case SLOPE_DOWN_WEAK:    return "弱い下降";
        case SLOPE_DOWN_STRONG:  return "強い下降";
    }
    return "---";
}

//+------------------------------------------------------------------+
//| 分割決済ラインを更新する
//+------------------------------------------------------------------+
void UpdateGroupSplitLines(PositionGroup &group)
{
    DeleteGroupSplitLines(group);
    if(!group.isActive || group.lockedInSplitCount <= 0) return;

    double finalTpPrice = group.stampedFinalTP;
    if(finalTpPrice <= 0 || finalTpPrice == DBL_MAX) return;

    ArrayResize(group.splitPrices, group.lockedInSplitCount);
    ArrayResize(group.splitLineNames, group.lockedInSplitCount);
    ArrayResize(group.splitLineTimes, group.lockedInSplitCount);

    if(InpSlMode == SL_MODE_MANUAL)
    {
        double slPrice = group.isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell;
        if(slPrice <= 0 || (group.isBuy && slPrice >= group.averageEntryPrice) || (!group.isBuy && slPrice <= group.averageEntryPrice)) return;
        
        double riskDistance = MathAbs(group.averageEntryPrice - slPrice);
        if(riskDistance <= 0) return;

        double tp1Price = group.averageEntryPrice + (group.isBuy ? riskDistance : -riskDistance);
        group.splitPrices[0] = tp1Price;

        int remainingSplits = group.lockedInSplitCount - 1;
        if(remainingSplits > 0)
        {
            if((group.isBuy && tp1Price >= finalTpPrice) || (!group.isBuy && tp1Price <= finalTpPrice))
            {
                for(int i = 1; i < group.lockedInSplitCount; i++) group.splitPrices[i] = finalTpPrice;
            }
            else
            {
                double remainingDistance = MathAbs(finalTpPrice - tp1Price);
                double step = remainingDistance / remainingSplits;
                for(int i = 1; i < group.lockedInSplitCount; i++)
                {
                    group.splitPrices[i] = group.splitPrices[i-1] + (group.isBuy ? step : -step);
                }
            }
        }
    }
    else
    {
        double step = MathAbs(finalTpPrice - group.averageEntryPrice) / group.lockedInSplitCount;
        for(int i = 0; i < group.lockedInSplitCount; i++)
        {
            group.splitPrices[i] = group.averageEntryPrice + (group.isBuy ? 1 : -1) * step * (i + 1);
        }
    }

    color pendingColor = group.isBuy ? clrGoldenrod : clrPurple;
    color settledColor = group.isBuy ? clrLimeGreen : clrHotPink;
    for(int i = 0; i < group.lockedInSplitCount; i++)
    {
        group.splitLineNames[i] = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_" + (string)i;
        if(i < group.splitsDone)
        {
            datetime settlementTime = group.splitLineTimes[i];
            if (settlementTime == 0) settlementTime = TimeCurrent(); 
            if(group.openTime > 0)
            {
                ObjectCreate(0, group.splitLineNames[i], OBJ_TREND, 0, group.openTime, group.splitPrices[i], settlementTime, group.splitPrices[i]);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_COLOR, settledColor);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_ZORDER, 5);
            }
        }
        else
        {
            ObjectCreate(0, group.splitLineNames[i], OBJ_HLINE, 0, 0, group.splitPrices[i]);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_COLOR, pendingColor);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_ZORDER, 5);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_SELECTABLE, false);
        }
    }
}

//+------------------------------------------------------------------+
//| グループの決済条件をチェックする
//+------------------------------------------------------------------+
void CheckExitForGroup(PositionGroup &group)
{
    if (!group.isActive) return;
    if (ArraySize(group.splitPrices) == 0) return;
    int effectiveSplitCount = group.lockedInSplitCount;
    if (group.splitsDone >= effectiveSplitCount || effectiveSplitCount <= 0) return;
    if (group.splitsDone >= ArraySize(group.splitPrices)) return;
    double price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double nextSplitPrice = group.splitPrices[group.splitsDone];
    if(nextSplitPrice == 0) return;
    double buffer = InpExitBufferPips * g_pip;
    bool reached = (group.isBuy && price >= nextSplitPrice - buffer) ||
                   (!group.isBuy && price <= nextSplitPrice + buffer);

    if(reached)
    {
        double lotToClose = 0.0;
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        if (group.splitsDone == effectiveSplitCount - 1)
        {
            lotToClose = group.totalLotSize;
        }
        else
        {
            double baseLot = floor(group.initialTotalLotSize / effectiveSplitCount / volStep) * volStep;
            double remainderLot = NormalizeDouble(group.initialTotalLotSize - (baseLot * effectiveSplitCount), 2);
            int upgradeCount = (int)round(remainderLot / volStep);
            lotToClose = baseLot;
            if(group.splitsDone < upgradeCount)
            {
                lotToClose += volStep;
            }
        }

        lotToClose = NormalizeDouble(lotToClose, 2);
        if (lotToClose > 0 && lotToClose < minLot) lotToClose = minLot;

        if (lotToClose > 0 && lotToClose >= minLot)
        {
            // ▼▼▼【ここに追加】▼▼▼
            PrintFormat("ログ: 分割決済トリガー (Group: %s, Split #%d) - 理由: 価格 %.5f が TP @%.5f に到達",
                        (group.isBuy ? "BUY" : "SELL"),
                        group.splitsDone + 1,
                        price,
                        nextSplitPrice);
            // ▲▲▲【ここまで追加】▲▲▲

            if(ExecuteGroupSplitExit(group, lotToClose))
            {
                if(group.splitsDone < ArraySize(group.splitLineTimes))
                {
                    group.splitLineTimes[group.splitsDone] = TimeCurrent();
                }
                group.splitsDone++;
                UpdateGroupSplitLines(group);
                ChartRedraw();
                if(InpBreakEvenAfterSplits > 0 && group.splitsDone >= InpBreakEvenAfterSplits)
                {
                    SetBreakEvenForGroup(group);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 内部のライン「データ」を更新する (管理リスト対応版)
//+------------------------------------------------------------------+
void UpdateLines()
{
    //ArrayFree(allLines);
    if(InpUsePivotLines)
    {
        CalculatePivot();
        double p_prices[] = {s1, r1, s2, r2, s3, r3};
        ENUM_LINE_TYPE p_types[] = {LINE_TYPE_SUPPORT, LINE_TYPE_RESISTANCE, LINE_TYPE_SUPPORT, LINE_TYPE_RESISTANCE, LINE_TYPE_SUPPORT, LINE_TYPE_RESISTANCE};
        color p_colors[] = {(color)CLR_S1, (color)CLR_R1, (color)CLR_S2, (color)CLR_R2, (color)CLR_S3, (color)CLR_R3};
        string p_names[] = {"S1", "R1", "S2", "R2", "S3", "R3"};
        datetime pivotStartTime = iTime(_Symbol, InpPivotPeriod, 0);

        for(int i = 0; i < 6; i++)
        {
            if(i >= 2 && !InpShowS2R2) continue;
            if(i >= 4 && !InpShowS3R3) continue;
            if(p_prices[i] <= 0) continue;

            Line line;
            line.name = p_names[i];
            line.price = p_prices[i];
            line.type = p_types[i];
            line.signalColor = p_colors[i];
            line.startTime = pivotStartTime;
            int stateIndex = GetLineState(line.name);
            line.isBrokeUp = g_lineStates[stateIndex].isBrokeUp;
            line.isBrokeDown = g_lineStates[stateIndex].isBrokeDown;
            line.breakTime = g_lineStates[stateIndex].breakTime;
            int size = ArraySize(allLines);
            ArrayResize(allLines, size + 1);
            allLines[size] = line;
        }
    }
    
    // ▼▼▼【ここから修正】▼▼▼
    // チャート上の全オブジェクトではなく、EAが管理するリストをループする
    int totalManualLines = ArraySize(g_manualLineNames);
    for(int i = 0; i < totalManualLines; i++)
    {
        string objName = g_manualLineNames[i];
        // オブジェクトが（手動などで）削除されていないか確認
        if(ObjectFind(0, objName) < 0) continue; 
        
        bool isManualSupport = StringFind(objName, "ManualSupport_") == 0;

        Line m_line;
        m_line.name = objName;
        m_line.price = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
        m_line.signalColor = (color)ObjectGetInteger(0, objName, OBJPROP_COLOR);
        m_line.type = isManualSupport ? LINE_TYPE_SUPPORT : LINE_TYPE_RESISTANCE;
        m_line.startTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
        int stateIndex = GetLineState(m_line.name);
        m_line.isBrokeUp = g_lineStates[stateIndex].isBrokeUp;
        m_line.isBrokeDown = g_lineStates[stateIndex].isBrokeDown;
        m_line.breakTime = g_lineStates[stateIndex].breakTime;
        
        int size = ArraySize(allLines);
        ArrayResize(allLines, size + 1);
        allLines[size] = m_line;
    }
    // ▲▲▲【ここまで修正】▲▲▲
}

//+------------------------------------------------------------------+
//| ピボット値を計算する
//+------------------------------------------------------------------+
void CalculatePivot()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, InpPivotPeriod, 1, 1, rates) < 1) return;
    double h = rates[0].high;
    double l = rates[0].low;
    double c = rates[0].close;
    pivot = (h + l + c) / 3.0;
    s1 = 2.0 * pivot - h;
    r1 = 2.0 * pivot - l;
    if(InpShowS2R2)
    {
        s2 = s1 - (r1 - s1);
        r2 = r1 + (r1 - s1);
    }
    if(InpShowS3R3)
    {
        s3 = s2 - (r2 - s2);
        r3 = r2 + (r2 - s2);
    }
}

//+------------------------------------------------------------------+
//| ライン名から永続的な状態オブジェクトの番号を取得・作成する
//+------------------------------------------------------------------+
int GetLineState(string lineName)
{
    for(int i = 0; i < ArraySize(g_lineStates); i++)
    {
        if(g_lineStates[i].name == lineName) return i;
    }

    // 見つからない場合は新規作成
    int size = ArraySize(g_lineStates);
    ArrayResize(g_lineStates, size + 1);
    g_lineStates[size].name = lineName;
    g_lineStates[size].isBrokeUp = false;
    g_lineStates[size].isBrokeDown = false;
    g_lineStates[size].waitForRetestUp = false;
    g_lineStates[size].waitForRetestDown = false;
    g_lineStates[size].breakTime = 0;
    
    return size;
}

//+------------------------------------------------------------------+
//| 手動ラインの状態を監視し、ブレイクを検出する
//+------------------------------------------------------------------+
void ManageManualLines()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;

    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, "ManualSupport_") != 0 && StringFind(name, "ManualResistance_") != 0) continue;

        string text = ObjectGetString(0, name, OBJPROP_TEXT);
        if(StringFind(text, "-Broken") >= 0) continue;
        
        double price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
        
        bool is_broken = (StringFind(text, "Resistance") >= 0 && rates[1].close > price) || (StringFind(text, "Support") >= 0 && rates[1].close < price);
                
        if(is_broken)
        {
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, rates[1].time);
            ObjectSetString(0, name, OBJPROP_TEXT, text + "-Broken");
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);

            if (InpEntryMode != ZONE_MODE)
            {
                int stateIndex = GetLineState(name);
                if(stateIndex >= 0)
                {
                    g_lineStates[stateIndex].breakTime = rates[1].time;
                    if(StringFind(text, "Resistance") >= 0) g_lineStates[stateIndex].isBrokeUp = true;
                    else g_lineStates[stateIndex].isBrokeDown = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ピボットラインを管理する
//+------------------------------------------------------------------+
void ManagePivotLines()
{
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);
    if (!InpUsePivotLines) return;

    long periodSeconds = PeriodSeconds(InpPivotPeriod);
    for(int i = InpPivotHistoryCount; i >= 0; i--)
    {
        MqlRates rates[];
        if(CopyRates(_Symbol, InpPivotPeriod, i + 1, 1, rates) < 1) continue;

        double h = rates[0].high;
        double l = rates[0].low;
        double c = rates[0].close;
        
        double p_val = (h + l + c) / 3.0;
        double s1_val = 2.0 * p_val - h;
        double r1_val = 2.0 * p_val - l;
        double s2_val = p_val - (h - l);
        double r2_val = p_val + (h - l);
        double s3_val = l - 2.0 * (h - p_val);
        double r3_val = h + 2.0 * (p_val - l);
        
        if(i == 0)
        {
            pivot = p_val;
            s1 = s1_val; r1 = r1_val;
            s2 = s2_val; r2 = r2_val;
            s3 = s3_val; r3 = r3_val;
        }

        datetime lineTime = iTime(_Symbol, InpPivotPeriod, i);
        ENUM_LINE_STYLE style = (i == 0) ? STYLE_SOLID : STYLE_DOT;
        bool rayRight = (i == 0);

        double p_prices[] = {s1_val, r1_val, s2_val, r2_val, s3_val, r3_val};
        color p_colors[] = {(color)CLR_S1, (color)CLR_R1, (color)CLR_S2, (color)CLR_R2, (color)CLR_S3, (color)CLR_R3};
        string p_names[] = {"S1", "R1", "S2", "R2", "S3", "R3"};

        for(int j = 0; j < 6; j++)
        {
            if (j >= 2 && !InpShowS2R2) continue;
            if (j >= 4 && !InpShowS3R3) continue;
            if (p_prices[j] <= 0) continue;

            string name = InpLinePrefix_Pivot + p_names[j] + "_" + IntegerToString(lineTime);
            datetime startTime = lineTime;
            datetime endTime = rayRight ? startTime + (datetime)periodSeconds : startTime + (datetime)periodSeconds - 1;

            if (ObjectCreate(0, name, OBJ_TREND, 0, startTime, p_prices[j], endTime, p_prices[j]))
            {
                ObjectSetInteger(0, name, OBJPROP_COLOR, p_colors[j]);
                ObjectSetInteger(0, name, OBJPROP_STYLE, style);
                ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, name, OBJPROP_BACK, true);
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| クリックした位置に手動ラインを描画する (管理リスト対応版)
//+------------------------------------------------------------------+
void DrawManualTrendLine(double price, datetime time)
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;

    bool isSupport = (price < tick.ask);
    color line_color = isSupport ? p_ManualSupport_Color : p_ManualResist_Color;
    string role_text = isSupport ? "Support" : "Resistance";
    string name = isSupport ? "ManualSupport_" : "ManualResistance_";
    name += (string)TimeCurrent() + "_" + IntegerToString(rand());

    if(ObjectCreate(0, name, OBJ_TREND, 0, time, price, time + PeriodSeconds(_Period), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
        ObjectSetString(0, name, OBJPROP_TEXT, role_text);
        ObjectSetInteger(0, name, OBJPROP_STYLE, p_ManualLine_Style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, p_ManualLine_Width);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
        
        // ▼▼▼【ここから追加】▼▼▼
        // 作成したライン名を管理リストに追加
        int size = ArraySize(g_manualLineNames);
        ArrayResize(g_manualLineNames, size + 1);
        g_manualLineNames[size] = name;
        // ▲▲▲【ここまで追加】▲▲▲

        UpdateLines();
        ChartRedraw();
    }
}

//+------------------------------------------------------------------+
//| 手動SLラインを描画・管理する
//+------------------------------------------------------------------+
void ManageSlLines()
{
    if(InpSlMode != SL_MODE_MANUAL)
    {
        ObjectDelete(0, "SLLine_Buy");
        ObjectDelete(0, "SLLine_Sell");
        return;
    }

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    
    if(!isBuySLManuallyMoved && g_slLinePrice_Buy == 0)
    {
        double atr_buffer[1];
        if(CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
        {
            g_slLinePrice_Buy = tick.ask - (atr_buffer[0] * InpAtrBufferMultiplier);
        }
    }
    
    if(g_slLinePrice_Buy > 0)
    {
        string name = "SLLine_Buy";
        if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
        ObjectMove(0, name, 0, 0, g_slLinePrice_Buy);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
    }

    if(!isSellSLManuallyMoved && g_slLinePrice_Sell == 0)
    {
        double atr_buffer[1];
        if(CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
        {
            g_slLinePrice_Sell = tick.bid + (atr_buffer[0] * InpAtrBufferMultiplier);
        }
    }
    
    if(g_slLinePrice_Sell > 0)
    {
        string name = "SLLine_Sell";
        if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
        ObjectMove(0, name, 0, 0, g_slLinePrice_Sell);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
    }
}

//+------------------------------------------------------------------+
//| TPゾーン（ライン）を更新する
//+------------------------------------------------------------------+
void UpdateZones()
{
    // --- BUY TP LOGIC ---
    string buy_tp_line_name = "TPLine_Buy";
    bool is_buy_line_manually_moved = false;

    if(ObjectFind(0, buy_tp_line_name) >= 0)
    {
        if(ObjectGetInteger(0, buy_tp_line_name, OBJPROP_STYLE) == STYLE_SOLID)
        {
            is_buy_line_manually_moved = true;
        }
    }

    if (!is_buy_line_manually_moved)
    {
        double new_buy_tp = 0;
        switch(InpTPLineMode)
        {
            case MODE_ZIGZAG:
            {
                double zigzag[]; 
                ArraySetAsSeries(zigzag, true);
                if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) > 0)
                {
                    double levelHigh = 0;
                    for(int i = 0; i < 100; i++)
                    {
                        if(zigzag[i] > 0)
                        {
                            if(zigzag[i] > levelHigh) levelHigh = zigzag[i];
                        }
                    }
                    new_buy_tp = levelHigh;
                }
                break;
            }
            case MODE_PIVOT:
            {
                MqlRates rates[];
                if(CopyRates(_Symbol, InpTP_Timeframe, 1, 1, rates) > 0)
                {
                    double h_tp = rates[0].high, l_tp = rates[0].low, c_tp = rates[0].close;
                    double p_tp = (h_tp + l_tp + c_tp) / 3.0;
                    double r1_tp = 2.0 * p_tp - l_tp, r2_tp = p_tp + (h_tp - l_tp), r3_tp = h_tp + 2.0 * (p_tp - l_tp);
                    double buy_ref_price = buyGroup.isActive ? buyGroup.averageEntryPrice : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double resistances[] = {r1_tp, r2_tp, r3_tp};
                    double closest_r = 0;
                    for(int i=0; i<ArraySize(resistances); i++)
                    {
                        if(resistances[i] > buy_ref_price)
                        {
                            if(closest_r == 0 || resistances[i] < closest_r){ closest_r = resistances[i]; }
                        }
                    }
                    new_buy_tp = closest_r;
                }
                break;
            }
        }
        if (new_buy_tp > 0)
        {
            double final_buy_tp = new_buy_tp;
            if (buyGroup.isActive && buyGroup.highestScore >= InpHighScoreThreshold)
            { 
                double originalDiff = final_buy_tp - buyGroup.averageEntryPrice; 
                if (originalDiff > 0) final_buy_tp = buyGroup.averageEntryPrice + (originalDiff * InpHighSchoreTpRratio); 
            }
            zonalFinalTPLine_Buy = final_buy_tp;
        }
    }
    else
    {
        zonalFinalTPLine_Buy = ObjectGetDouble(0, buy_tp_line_name, OBJPROP_PRICE, 0);
    }

    if (zonalFinalTPLine_Buy > 0)
    {
        if(ObjectFind(0, buy_tp_line_name) < 0) ObjectCreate(0, buy_tp_line_name, OBJ_HLINE, 0, 0, 0);
        ObjectMove(0, buy_tp_line_name, 0, 0, zonalFinalTPLine_Buy);
        ObjectSetInteger(0, buy_tp_line_name, OBJPROP_COLOR, clrGold);
        ObjectSetInteger(0, buy_tp_line_name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, buy_tp_line_name, OBJPROP_STYLE, is_buy_line_manually_moved ? STYLE_SOLID : STYLE_DOT);
        ObjectSetInteger(0, buy_tp_line_name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, buy_tp_line_name, OBJPROP_ZORDER, 10);
    }

    // --- SELL TP LOGIC ---
    string sell_tp_line_name = "TPLine_Sell";
    bool is_sell_line_manually_moved = false;

    if(ObjectFind(0, sell_tp_line_name) >= 0)
    {
        if(ObjectGetInteger(0, sell_tp_line_name, OBJPROP_STYLE) == STYLE_SOLID)
        {
            is_sell_line_manually_moved = true;
        }
    }

    if (!is_sell_line_manually_moved)
    {
        double new_sell_tp = 0;
        switch(InpTPLineMode)
        {
            case MODE_ZIGZAG:
            {
                double zigzag[]; 
                ArraySetAsSeries(zigzag, true);
                if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) > 0)
                {
                    double levelLow = DBL_MAX;
                    for(int i = 0; i < 100; i++)
                    {
                        if(zigzag[i] > 0)
                        {
                            if(zigzag[i] < levelLow) levelLow = zigzag[i];
                        }
                    }
                    new_sell_tp = (levelLow < DBL_MAX) ? levelLow : 0;
                }
                break;
            }
            case MODE_PIVOT:
            {
                MqlRates rates[];
                if(CopyRates(_Symbol, InpTP_Timeframe, 1, 1, rates) > 0)
                {
                    double h_tp = rates[0].high, l_tp = rates[0].low, c_tp = rates[0].close;
                    double p_tp = (h_tp + l_tp + c_tp) / 3.0;
                    double s1_tp = 2.0 * p_tp - h_tp, s2_tp = p_tp - (h_tp - l_tp), s3_tp = l_tp - 2.0 * (h_tp - p_tp);
                    double sell_ref_price = sellGroup.isActive ? sellGroup.averageEntryPrice : SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    double supports[] = {s1_tp, s2_tp, s3_tp};
                    double closest_s = 0;
                    for(int i=0; i<ArraySize(supports); i++)
                    {
                        if(supports[i] < sell_ref_price && supports[i] > 0)
                        {
                            if(closest_s == 0 || supports[i] > closest_s){ closest_s = supports[i]; }
                        }
                    }
                    new_sell_tp = closest_s;
                }
                break;
            }
        }
        if(new_sell_tp > 0)
        {
            double final_sell_tp = new_sell_tp;
            if (sellGroup.isActive && sellGroup.highestScore >= InpHighScoreThreshold) 
            {
                double originalDiff = sellGroup.averageEntryPrice - final_sell_tp; 
                if (originalDiff > 0) final_sell_tp = sellGroup.averageEntryPrice - (originalDiff * InpHighSchoreTpRratio); 
            }
            zonalFinalTPLine_Sell = final_sell_tp;
        }
    }
    else
    {
        zonalFinalTPLine_Sell = ObjectGetDouble(0, sell_tp_line_name, OBJPROP_PRICE, 0);
    }

    if (zonalFinalTPLine_Sell > 0)
    {
        if(ObjectFind(0, sell_tp_line_name) < 0) ObjectCreate(0, sell_tp_line_name, OBJ_HLINE, 0, 0, 0);
        ObjectMove(0, sell_tp_line_name, 0, 0, zonalFinalTPLine_Sell);
        ObjectSetInteger(0, sell_tp_line_name, OBJPROP_COLOR, clrMediumPurple);
        ObjectSetInteger(0, sell_tp_line_name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, sell_tp_line_name, OBJPROP_STYLE, is_sell_line_manually_moved ? STYLE_SOLID : STYLE_DOT);
        ObjectSetInteger(0, sell_tp_line_name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, sell_tp_line_name, OBJPROP_ZORDER, 10);
    }
}

//+------------------------------------------------------------------+
//| ゾーンを長方形オブジェクトで可視化する (描画負荷軽減版)
//+------------------------------------------------------------------+
void ManageZoneVisuals()
{
    ObjectsDeleteAll(0, "ZoneRect_");
    if (!g_isZoneVisualizationEnabled || (InpEntryMode != ZONE_MODE)) return;

    double zoneWidth = InpZonePips * g_pip;
    for (int i = 0; i < ArraySize(allLines); i++)
    {
        Line line = allLines[i];
        if (line.price <= 0 || line.startTime == 0) continue;

        string name = "ZoneRect_" + line.name;
        double upper_zone = line.price + zoneWidth;
        double lower_zone = line.price - zoneWidth;
        color zone_color = (line.type == LINE_TYPE_SUPPORT) ? C'30,70,120' : C'120,70,30';

        if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, line.startTime, upper_zone))
        {
            // --- 【修正】ここから ---
            datetime endTime;
            // ラインがすでにブレイクされている場合は、ブレイク時間までを描画
            if(line.breakTime > 0)
            {
                endTime = line.breakTime;
            }
            // まだアクティブなラインの場合は、未来に伸ばしすぎないように範囲を限定する
            else
            {
                // 現在のバーの時刻から、50本先の未来までを描画範囲とする
                endTime = iTime(_Symbol, _Period, 0) + (PeriodSeconds() * 50);
            }
            // --- 【修正】ここまで ---

            ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
            ObjectSetDouble(0, name, OBJPROP_PRICE, 1, lower_zone);
            ObjectSetInteger(0, name, OBJPROP_COLOR, zone_color);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
    }
}

//+------------------------------------------------------------------+
//| 全ての視覚的要素（ライン、パネル等）を更新する
//+------------------------------------------------------------------+
void UpdateAllVisuals()
{
    // 1. サポート・レジスタンスライン（ピボット等）を更新・再描画
    UpdateLines();
    
    // 2. TPラインを更新・再描画
    UpdateZones();
    
    // 3. ポジショングループを管理し、分割決済ラインを更新・再描画
    ManagePositionGroups();

    // 4. 情報パネルを更新・再描画
    UpdateInfoPanel_NewBar(); // ← こちらに修正
    
    // 5. チャートを強制的に再描画して、すべての変更を即時反映
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| シグナルオブジェクトをチャートに描画する (ログ出力強化版)
//+------------------------------------------------------------------+
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string msg)
{
    // --- 統一ゾーン・フィルター ---
    if(InpUseUniversalZoneFilter)
    {
        bool is_buy = (StringFind(name, "_Buy") > 0);
        bool is_sell = (StringFind(name, "_Sell") > 0);
        if(is_buy || is_sell)
        {
            // ゾーン内でなければシグナルを棄却し、理由をログに出力
            if(!IsInValidZone(dt, is_buy))
            {
                PrintFormat("ログ: シグナル棄却 (%s) - 理由: 有効なゾーン外です。", name);
                return;
            }
        }
    }

    // ▼▼▼【ここから修正】▼▼▼
    // 渡されたnameに含まれる可能性のある不適切な文字（スペース、コロン）をアンダースコアに置換します。
    string safe_base_name = name;
    StringReplace(safe_base_name, " ", "_");
    StringReplace(safe_base_name, ":", "_");

    // datetime値を直接文字列にキャストして、安全で一意なオブジェクト名を生成します。
    // これにより、コロンや追加のスペースが含まれるのを防ぎます。
    string uname = safe_base_name + "_" + (string)dt;
    // ▲▲▲【ここまで修正】▲▲▲
    
    if(ObjectFind(0, uname) < 0 && (TimeCurrent() - lastArrowTime) > 5)
    {
        if(ObjectCreate(0, uname, OBJ_ARROW, 0, dt, price))
        {
            ObjectSetInteger(0, uname, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, uname, OBJPROP_ARROWCODE, code);
            ObjectSetInteger(0, uname, OBJPROP_WIDTH, InpSignalWidth);
            ObjectSetString(0, uname, OBJPROP_FONT, "Wingdings");
            ObjectSetInteger(0, uname, OBJPROP_FONTSIZE, InpSignalFontSize);
            lastArrowTime = TimeCurrent();
            // シグナルが正常に生成されたことをログに出力
            PrintFormat("ログ: シグナル生成 (%s) - 価格: %.5f", uname, price); // デバッグ用にユニーク名を出力
            if(StringLen(msg) > 0) Print(msg);
        }
    }
}

//+------------------------------------------------------------------+
//| 帯MACDの状態をパネル表示用の文字列に変換する
//+------------------------------------------------------------------+
string ObiMacdToString(const DaijunkanMACDValues &macd)
{
    if (macd.is_obi_gc) return "GC↑";
    if (macd.is_obi_dc) return "DC↓";
    if (macd.obi_macd > 0 && macd.obi_macd_slope > 0) return "GC準備↑";
    if (macd.obi_macd < 0 && macd.obi_macd_slope < 0) return "DC準備↓";
    if (macd.obi_macd > 0) return "0ライン上";
    if (macd.obi_macd < 0) return "0ライン下";
    return "---";
}

//+------------------------------------------------------------------+
//| チャート上の有効なエントリーシグナルの有無と名前をチェックする (分離版)
//+------------------------------------------------------------------+
void CheckActiveEntrySignals(bool &buy_trigger, bool &sell_trigger, string &buy_signal_name, string &sell_signal_name)
{
    buy_trigger = false;
    sell_trigger = false;
    buy_signal_name = "";
    sell_signal_name = "";
    
    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_ARROW);
        if(StringFind(name, InpArrowPrefix) != 0 && StringFind(name, InpDotPrefix) != 0) continue;
        
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
        int bars_since_signal = iBarShift(_Symbol, _Period, objTime, false);

        // ▼▼▼ ここを修正 ▼▼▼
        // エントリーの有効期限だけをチェックする
        if(bars_since_signal > InpSignalEntryExpiryBars) continue;
        // ▲▲▲ ここまで修正 ▲▲▲
        
        if(!buy_trigger && StringFind(name, "_Buy") > 0)
        {
            buy_trigger = true;
            buy_signal_name = name;
        }
        if(!sell_trigger && StringFind(name, "_Sell") > 0)
        {
            sell_trigger = true;
            sell_signal_name = name;
        }
        
        if(buy_trigger && sell_trigger) break;
    }
}

//+------------------------------------------------------------------+
//| 【新規】プライスアクション・シグナルを検知する
//+------------------------------------------------------------------+
void CheckPriceActionSignal()
{
    if(!InpUsePriceActionSignal) return;
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 1, 1, rates) < 1) return;
    datetime signal_time = rates[0].time;
    double open = rates[0].open, high = rates[0].high, low = rates[0].low, close = rates[0].close;

    bool is_bullish_pinbar = false, is_bearish_pinbar = false;
    double body_size = MathAbs(open - close);
    double candle_range = high - low;

    if (candle_range > 0 && body_size / candle_range < InpPinbarBodyRatio)
    {
        double upper_wick = high - MathMax(open, close);
        double lower_wick = MathMin(open, close) - low;
        if(lower_wick > body_size * InpPinbarWickRatio && upper_wick < body_size) is_bullish_pinbar = true;
        if(upper_wick > body_size * InpPinbarWickRatio && lower_wick < body_size) is_bearish_pinbar = true;
    }

    if(is_bullish_pinbar)
    {
        double offset = InpSignalOffsetPips * g_pip;
        CreateSignalObject(InpArrowPrefix + "PA_Buy_" + TimeToString(signal_time), signal_time, low - offset, clrDeepSkyBlue, 233, "PA Buy Signal");
    }
    if(is_bearish_pinbar)
    {
        double offset = InpSignalOffsetPips * g_pip;
        CreateSignalObject(InpArrowPrefix + "PA_Sell_" + TimeToString(signal_time), signal_time, high + offset, clrHotPink, 234, "PA Sell Signal");
    }
}

//+------------------------------------------------------------------+
//| 【新規】シグナルが有効なゾーン内にあるかを判定する共通関数
//+------------------------------------------------------------------+
bool IsInValidZone(datetime signal_time, bool is_buy_signal)
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, signal_time, 1, rates) < 1) return false;
    double high = rates[0].high, low = rates[0].low;
    
    if(InpZoneFilter_UseStatic)
    {
        double zoneWidth = InpZonePips * g_pip;
        for (int i = 0; i < ArraySize(allLines); i++)
        {
            Line line = allLines[i];
            double upper_zone = line.price + zoneWidth;
            double lower_zone = line.price - zoneWidth;
            if (is_buy_signal && line.type == LINE_TYPE_SUPPORT && high > lower_zone && low < upper_zone) return true;
            if (!is_buy_signal && line.type == LINE_TYPE_RESISTANCE && high > lower_zone && low < upper_zone) return true;
        }
    }

    if(InpZoneFilter_UseMA)
    {
        double middle_ma_buf[], long_ma_buf[];
        if(CopyBuffer(h_gc_ma_middle_mtf[TF_CURRENT_INDEX], 0, signal_time, 1, middle_ma_buf) > 0 && 
           CopyBuffer(h_gc_ma_long_mtf[TF_CURRENT_INDEX], 0, signal_time, 1, long_ma_buf) > 0)
        {
            double upper_ma_zone = MathMax(middle_ma_buf[0], long_ma_buf[0]);
            double lower_ma_zone = MathMin(middle_ma_buf[0], long_ma_buf[0]);
            ENUM_MASTER_STATE state = g_env_state.master_state;
            if(is_buy_signal && (state == STATE_1B_CONFIRMED || state == STATE_2_PULLBACK || state == STATE_6_TRANSITION_UP) && low <= upper_ma_zone) return true;
            if(!is_buy_signal && (state == STATE_4B_CONFIRMED || state == STATE_5_RALLY || state == STATE_3_TRANSITION_DOWN) && high >= lower_ma_zone) return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| 【新規】情報パネルのオブジェクトを初回に一度だけ作成する
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    // 既存のパネルオブジェクトがあれば一度すべて削除
    ObjectsDeleteAll(0, g_panelPrefix);

    int max_expected_lines = 50; // パネルの最大行数
    string font = "Arial";

    for(int i = 0; i < max_expected_lines; i++)
    {
        string text_obj_name = g_panelPrefix + "Text_" + (string)i;
        string icon_obj_name = g_panelPrefix + "Icon_" + (string)i;

        // テキスト用ラベルオブジェクトを作成
        ObjectCreate(0, text_obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, text_obj_name, OBJPROP_FONT, font);
        ObjectSetInteger(0, text_obj_name, OBJPROP_ZORDER, 0);
        ObjectSetString(0, text_obj_name, OBJPROP_TEXT, ""); // 初期状態は空にする

        // アイコン用ラベルオブジェクトを作成
        ObjectCreate(0, icon_obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, icon_obj_name, OBJPROP_FONT, font);
        ObjectSetInteger(0, icon_obj_name, OBJPROP_ZORDER, 0);
        ObjectSetString(0, icon_obj_name, OBJPROP_TEXT, ""); // 初期状態は空にする
    }
}

//+------------------------------------------------------------------+
//| 有効期限切れのシグナルオブジェクトを自動で削除する (分離版)
//+------------------------------------------------------------------+
void CleanupExpiredSignalObjects()
{
    // チャート上のすべての矢印オブジェクトをチェック
    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_ARROW);
        if(StringFind(name, InpArrowPrefix) == 0 || StringFind(name, InpDotPrefix) == 0)
        {
            datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
            int bars_since_signal = iBarShift(_Symbol, _Period, objTime, false);
            
            // ▼▼▼ ここを修正 ▼▼▼
            // 表示の有効期限だけをチェックする (0の場合は削除しない)
            if(InpSignalVisualExpiryBars > 0 && bars_since_signal >= InpSignalVisualExpiryBars)
            {
                ObjectDelete(0, name);
            }
            // ▲▲▲ ここまで修正 ▲▲▲
        }
    }
}

//+------------------------------------------------------------------+
//| HT_Turning_Pointからラインデータを読み込み、始点を特定してリストに追加する
//+------------------------------------------------------------------+
void UpdateTurningPointLines()
{
    if(!InpUseExternalIndicator || h_turning_point == INVALID_HANDLE) return;

    double line_buffer[1];
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    for(int buffer_index = 0; buffer_index <= 67; buffer_index++)
    {
        if(CopyBuffer(h_turning_point, buffer_index, 1, 1, line_buffer) > 0)
        {
            double line_price = line_buffer[0];
            if(line_price > 0 && line_price != EMPTY_VALUE)
            {
                Line external_line;
                external_line.name = "TP_Line_B" + (string)buffer_index;
                external_line.price = line_price;
                
                // ▼▼▼【ここが変更点】▼▼▼
                // 新しい関数を呼び出して、ラインの本当の始点を特定する
                external_line.startTime = FindLineOriginTime(line_price, buffer_index);
                // ▲▲▲【ここまで変更点】▲▲▲

                if(line_price < current_price) {
                    external_line.type = LINE_TYPE_SUPPORT;
                    external_line.signalColor = clrIndianRed;
                } else {
                    external_line.type = LINE_TYPE_RESISTANCE;
                    external_line.signalColor = clrLimeGreen;
                }
                
                int size = ArraySize(allLines);
                ArrayResize(allLines, size + 1);
                allLines[size] = external_line;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 【新規】読み込んだ外部ラインをチャート上に可視化する
//+------------------------------------------------------------------+
void VisualizeExternalLines()
{
    // 1. 過去に描画した可視化ラベルをすべて削除
    ObjectsDeleteAll(0, "Vis_Line_");

    // 2. 設定がOFFならここで処理を終了
    if(!InpVisualizeExternalLines) return;

    // 3. EAが管理しているすべてのラインをループ
    for(int i = 0; i < ArraySize(allLines); i++)
    {
        Line line = allLines[i];
        
        // 4. 外部インジケーターから読み込んだライン（"TP_Line_B"で始まる名前）のみを対象とする
        if(StringFind(line.name, "TP_Line_B") == 0)
        {
            string obj_name = "Vis_Line_" + line.name;
            
            // 5. 価格ラベル(OBJ_TEXT)をラインの価格位置に作成
            if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, iTime(_Symbol, _Period, 0), line.price))
            {
                ObjectSetString(0, obj_name, OBJPROP_TEXT, StringFormat("%.5f", line.price));
                ObjectSetInteger(0, obj_name, OBJPROP_COLOR, (line.type == LINE_TYPE_SUPPORT ? InpVisSupportColor : InpVisResistColor));
                ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, InpVisFontSize);
                ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_RIGHT); // チャートの右端に表示
                ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
            }
        }
    }
}



//+------------------------------------------------------------------+
//| 【新規追加】全UIコントロールの存在を監視し、なければ再作成する
//+------------------------------------------------------------------+
void ManageUIControls()
{
    if(!InpEnableButtons) return;

    // --- ここでEAの全ボタンの存在をチェックし、なければ作成する ---

    // 手動ライン描画ボタン
    if(ObjectFind(0, g_buttonName) < 0) {
        CreateApexButton(g_buttonName, 10, 50, 120, 20, "手動ライン描画 OFF", C'220,220,220');
        UpdateButtonState(); // 作成直後に状態を更新
    }
    // シグナル消去ボタン
    if(ObjectFind(0, g_clearButtonName) < 0) {
        CreateApexButton(g_clearButtonName, 10, 75, 120, 20, "シグナル消去", C'255,228,225');
    }
    // 手動ライン消去ボタン
    if(ObjectFind(0, g_clearLinesButtonName) < 0) {
        CreateApexButton(g_clearLinesButtonName, 10, 100, 120, 20, "手動ライン消去", C'225,240,255');
    }

    // 決済・リセットボタン群
    if(ObjectFind(0, BUTTON_BUY_CLOSE_ALL) < 0)  CreateApexButton(BUTTON_BUY_CLOSE_ALL,  150, 50,  80, 20, "BUY全決済",     C'80,0,0');
    if(ObjectFind(0, BUTTON_SELL_CLOSE_ALL) < 0) CreateApexButton(BUTTON_SELL_CLOSE_ALL, 150, 75,  80, 20, "SELL全決済",    C'0,0,80');
    if(ObjectFind(0, BUTTON_ALL_CLOSE) < 0)      CreateApexButton(BUTTON_ALL_CLOSE,      150, 100, 80, 20, "全決済",        C'80,80,80');
    if(ObjectFind(0, BUTTON_RESET_BUY_TP) < 0)   CreateApexButton(BUTTON_RESET_BUY_TP,   240, 50,  100, 20, "TPリセット(買)", C'139,69,19');
    if(ObjectFind(0, BUTTON_RESET_SELL_TP) < 0)  CreateApexButton(BUTTON_RESET_SELL_TP,  240, 75,  100, 20, "TPリセット(売)", C'72,61,139');
    if(ObjectFind(0, BUTTON_RESET_BUY_SL) < 0)   CreateApexButton(BUTTON_RESET_BUY_SL,   350, 50,  100, 20, "SLリセット(買)", C'139,19,69');
    if(ObjectFind(0, BUTTON_RESET_SELL_SL) < 0)  CreateApexButton(BUTTON_RESET_SELL_SL,  350, 75,  100, 20, "SLリセット(売)", C'61,139,72');
    if(ObjectFind(0, BUTTON_TOGGLE_ZONES) < 0) {
        CreateApexButton(BUTTON_TOGGLE_ZONES,   240, 100, 100, 20, "ゾーン表示: ON", clrSeaGreen);
        UpdateZoneButtonState(); // 作成直後に状態を更新
    }
}

//+------------------------------------------------------------------+
//| 【最終版】ラインの始点を過去に遡って特定する
//+------------------------------------------------------------------+
datetime FindLineOriginTime(double current_line_price, int buffer_index)
{
    datetime origin_time = iTime(_Symbol, _Period, 1); // デフォルト値（見つからなかった場合）
    int lookback_limit = 2000; // 最大2000本前まで遡る

    double historical_line_buffer[1];
    
    // 過去の足を1本ずつ遡ってスキャン
    for(int shift = 1; shift < lookback_limit; shift++)
    {
        if(CopyBuffer(h_turning_point, buffer_index, shift, 1, historical_line_buffer) > 0)
        {
            double historical_line_price = historical_line_buffer[0];

            // ラインがその過去の時点でも有効か（ほぼ同じ価格か）チェック
            if(MathAbs(historical_line_price - current_line_price) < g_pip)
            {
                // 価格が同じであれば、ここを始点候補として更新し続ける
                origin_time = iTime(_Symbol, _Period, shift);
            }
            else
            {
                // ラインの価格が変わった＝それより過去にはこのラインは存在しない、と判断して調査を終了
                break;
            }
        }
        else
        {
            // データが取得できなくなったら調査終了
            break;
        }
    }
    
    return origin_time;
}

//+------------------------------------------------------------------+
//| RSIとMAのクロスをチェックしてエントリーを試みる (ロジック修正版)
//+------------------------------------------------------------------+
void CheckRsiMaSignal()
{
    // ロジックが無効なら何もしない
    if(!Inp_RSI_EnableLogic) return;

    // --- 1. 必要なデータを準備 ---
    // ▼▼▼ ロジック修正 ▼▼▼：2本前の足のデータも必要になるため、取得サイズを増やす
    int data_size = Inp_RSI_MAPeriod + 3; 
    double rsi_buffer[];
    if(ArrayResize(rsi_buffer, data_size) < 0) return;
    if(CopyBuffer(h_rsi, 0, 0, data_size, rsi_buffer) < data_size)
    {
        Print("RSIデータのコピーに失敗しました。");
        return;
    }
    ArraySetAsSeries(rsi_buffer, true);

    // --- 2. RSIの移動平均を計算 ---
    // ▼▼▼ ロジック修正 ▼▼▼：判定の主体である「1本前の足」を基準にMAを計算
    double rsi_ma_previous = 0;
    for(int i = 1; i < Inp_RSI_MAPeriod + 1; i++)
    {
        rsi_ma_previous += rsi_buffer[i];
    }
    rsi_ma_previous /= Inp_RSI_MAPeriod;

    // --- 3. エントリーシグナルをチェック ---
    bool buy_signal = false;
    bool sell_signal = false;

    // ▼▼▼ ロジック修正 ▼▼▼：判定を[2]本前と[1]本前の足で行う
    // BUYシグナル条件
    if(rsi_ma_previous >= Inp_RSI_UpperLevel &&      // 1. 1本前のMAが上限レベル以上
       rsi_buffer[2] >= Inp_RSI_UpperLevel &&      // 2. 2本前のRSIが上限レベル以上
       rsi_buffer[1] < Inp_RSI_UpperLevel)         // 3. 1本前のRSIが上限レベルを下に抜けた
    {
        buy_signal = true;
    }

    // SELLシグナル条件
    if(rsi_ma_previous <= Inp_RSI_LowerLevel &&      // 1. 1本前のMAが下限レベル以下
       rsi_buffer[2] <= Inp_RSI_LowerLevel &&      // 2. 2本前のRSIが下限レベル以下
       rsi_buffer[1] > Inp_RSI_LowerLevel)         // 3. 1本前のRSIが下限レベルを上に抜けた
    {
        sell_signal = true;
    }
    // ▲▲▲ ここまで修正 ▲▲▲

    if(!buy_signal && !sell_signal) return;

    // --- 4. フィルター条件をチェックしてエントリー ---
    string signal_name = "";
    if(buy_signal)
    {
        signal_name = "RsiMa_Buy";
        PrintFormat("ログ: 新規ロジックBUYシグナル検知 (%s)", signal_name);
        
        bool is_valid_bias = (g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_BUY ||
                              g_env_state.current_trade_bias == BIAS_SHAKEOUT_BUY ||
                              g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_BUY ||
                              g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_BUY ||
                              g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_BUY ||
                              g_env_state.current_trade_bias == BIAS_CONFLICTING_PULLBACK_BUY);
                              
        if(!is_valid_bias)
        {
            PrintFormat("ログ: %s 見送り (理由: バイアス不一致)", signal_name);
            return;
        }
        
        // ▼▼▼ ロジック修正 ▼▼▼：シグナルが発生した足（1本前の足）でゾーン判定
        if(Inp_RSI_UseZoneFilter && !IsInValidZone(iTime(_Symbol, _Period, 1), true))
        {
            PrintFormat("ログ: %s 見送り (理由: 有効ゾーン外)", signal_name);
            return;
        }

        if(buyGroup.positionCount < InpMaxPositions)
        {
            MqlTick tick;
            if(SymbolInfoTick(_Symbol, tick)) PlaceOrder(true, tick.ask, g_env_state.total_buy_score);
        }
    }

    if(sell_signal)
    {
        signal_name = "RsiMa_Sell";
        PrintFormat("ログ: 新規ロジックSELLシグナル検知 (%s)", signal_name);

        bool is_valid_bias = (g_env_state.current_trade_bias == BIAS_ALIGNED_EARLY_ENTRY_SELL ||
                              g_env_state.current_trade_bias == BIAS_SHAKEOUT_SELL ||
                              g_env_state.current_trade_bias == BIAS_DOMINANT_CORE_TREND_SELL ||
                              g_env_state.current_trade_bias == BIAS_DOMINANT_PULLBACK_SELL ||
                              g_env_state.current_trade_bias == BIAS_ALIGNED_CORE_TREND_SELL ||
                              g_env_state.current_trade_bias == BIAS_CONFLICTING_PULLBACK_SELL);

        if(!is_valid_bias)
        {
            PrintFormat("ログ: %s 見送り (理由: バイアス不一致)", signal_name);
            return;
        }
        
        // ▼▼▼ ロジック修正 ▼▼▼：シグナルが発生した足（1本前の足）でゾーン判定
        if(Inp_RSI_UseZoneFilter && !IsInValidZone(iTime(_Symbol, _Period, 1), false))
        {
            PrintFormat("ログ: %s 見送り (理由: 有効ゾーン外)", signal_name);
            return;
        }
        
        if(sellGroup.positionCount < InpMaxPositions)
        {
            MqlTick tick;
            if(SymbolInfoTick(_Symbol, tick)) PlaceOrder(false, tick.bid, g_env_state.total_sell_score);
        }
    }
}

//+------------------------------------------------------------------+
//| パネル表示用の新しいヘルパー関数群
//+------------------------------------------------------------------+

// ENUM_TRADE_BIASから「市場サイクル」の文字列を取得する
string GetBiasCategoryToString(ENUM_TRADE_BIAS bias)
{
    switch(bias)
    {
        // 上昇トレンド
        case BIAS_ALIGNED_EARLY_ENTRY_BUY:
        case BIAS_SHAKEOUT_BUY:
            return "📈 上昇トレンド（発生・初期）";
        case BIAS_DOMINANT_CORE_TREND_BUY:
        case BIAS_DOMINANT_PULLBACK_BUY:
        case BIAS_ALIGNED_CORE_TREND_BUY:
            return "🚀 上昇トレンド（本流・最盛期）";
        case BIAS_CONFLICTING_PULLBACK_BUY:
        case BIAS_TREND_EXHAUSTION_BUY:
            return "⚠️ 上昇トレンド（警戒・終焉）";

        // 下降トレンド
        case BIAS_ALIGNED_EARLY_ENTRY_SELL:
        case BIAS_SHAKEOUT_SELL:
            return "📉 下降トレンド（発生・初期）";
        case BIAS_DOMINANT_CORE_TREND_SELL:
        case BIAS_DOMINANT_PULLBACK_SELL:
        case BIAS_ALIGNED_CORE_TREND_SELL:
            return "🚀 下降トレンド（本流・最盛期）";
        case BIAS_CONFLICTING_PULLBACK_SELL:
        case BIAS_TREND_EXHAUSTION_SELL:
            return "⚠️ 下降トレンド（警戒・終焉）";

        // レンジ・転換
        case BIAS_RANGE_BOUND:
        case BIAS_RANGE_SQUEEZE:
        case BIAS_RANGE_BREAKOUT_POTENTIAL_UP:
        case BIAS_RANGE_BREAKOUT_POTENTIAL_DOWN:
            return "🧘 転換・レンジ";

        default:
            return "❔ 分析不能";
    }
}

// ENUM_TRADE_BIASから詳細な日本語名、アイコン、色を取得する
void TradeBiasToString(ENUM_TRADE_BIAS bias, string &bias_text, string &bias_icon, color &bias_color)
{
    bias_icon = "■";
    bias_color = clrGray;

    switch(bias)
    {
        case BIAS_DOMINANT_CORE_TREND_BUY:   bias_text = "完全順行コアトレンド・買";   bias_icon = "🚀"; bias_color = clrLime; break;
        case BIAS_DOMINANT_PULLBACK_BUY:     bias_text = "完全順行プルバック・買";     bias_icon = "🚀"; bias_color = clrLightGreen; break;
        case BIAS_ALIGNED_CORE_TREND_BUY:    bias_text = "順張りコアトレンド・買";     bias_icon = "📈"; bias_color = clrPaleGreen; break;
        case BIAS_ALIGNED_EARLY_ENTRY_BUY:   bias_text = "順張りアーリーエントリー・買"; bias_icon = "📈"; bias_color = clrLightSkyBlue; break;
        case BIAS_SHAKEOUT_BUY:              bias_text = "シェイクアウト・買";         bias_icon = "✨"; bias_color = clrSpringGreen; break;
        case BIAS_CONFLICTING_PULLBACK_BUY:  bias_text = "逆行プルバック・買";         bias_icon = "⚠️"; bias_color = clrKhaki; break;
        case BIAS_TREND_EXHAUSTION_BUY:      bias_text = "トレンド枯渇・買";           bias_icon = "🏁"; bias_color = clrGold; break;

        case BIAS_DOMINANT_CORE_TREND_SELL:  bias_text = "完全順行コアトレンド・売";   bias_icon = "🚀"; bias_color = clrRed; break;
        case BIAS_DOMINANT_PULLBACK_SELL:    bias_text = "完全順行プルバック・売";     bias_icon = "🚀"; bias_color = clrTomato; break;
        case BIAS_ALIGNED_CORE_TREND_SELL:   bias_text = "順張りコアトレンド・売";     bias_icon = "📉"; bias_color = clrSalmon; break;
        case BIAS_ALIGNED_EARLY_ENTRY_SELL:  bias_text = "順張りアーリーエントリー・売"; bias_icon = "📉"; bias_color = clrHotPink; break;
        case BIAS_SHAKEOUT_SELL:             bias_text = "シェイクアウト・売";         bias_icon = "✨"; bias_color = clrIndianRed; break;
        case BIAS_CONFLICTING_PULLBACK_SELL: bias_text = "逆行プルバック・売";         bias_icon = "⚠️"; bias_color = clrDarkSalmon; break;
        case BIAS_TREND_EXHAUSTION_SELL:     bias_text = "トレンド枯渇・売";           bias_icon = "🏁"; bias_color = clrMediumPurple; break;

        case BIAS_RANGE_BOUND:               bias_text = "レンジ・方向感なし";        bias_icon = "🧘"; bias_color = clrGainsboro; break;
        case BIAS_RANGE_SQUEEZE:             bias_text = "レンジ・収縮";              bias_icon = "🧘"; bias_color = clrSlateGray; break;
        case BIAS_RANGE_BREAKOUT_POTENTIAL_UP: bias_text = "ブレイク期待・上";        bias_icon = "🧘"; bias_color = clrLightGreen; break;
        case BIAS_RANGE_BREAKOUT_POTENTIAL_DOWN: bias_text = "ブレイク期待・下";      bias_icon = "🧘"; bias_color = clrLightPink; break;

        default:                             bias_text = "不明確";                   bias_icon = "❔"; bias_color = clrGray; break;
    }
}

//+------------------------------------------------------------------+
//| 現在のスイングの進行状況を分析して文字列を返す (キャッシュ機能付き)
//+------------------------------------------------------------------+
string GetSwingRatioInfo(int tf_index, color &out_color)
{
    // --- キャッシュチェック ---
    ENUM_TIMEFRAMES tf = (tf_index == 0) ? _Period : (tf_index == 1) ? InpIntermediateTimeframe : InpHigherTimeframe;
    datetime current_bar_time = iTime(_Symbol, tf, 0);
    if(g_swing_cache_bartime[tf_index] == current_bar_time)
    {
        // 前回の計算結果がまだ有効なら、キャッシュから返す
        out_color = g_swing_color_cache[tf_index];
        return g_swing_info_cache[tf_index];
    }
    
    // --- 以下、キャッシュがない場合のみ計算処理 ---
    out_color = clrWhite; 
    
    double zigzag_buffer[];
    int data_to_copy = 500; 
    int copied = CopyBuffer(h_zigzag_swing[tf_index], 0, 0, data_to_copy, zigzag_buffer);
    if(copied < 3) return "---";
    ArraySetAsSeries(zigzag_buffer, true);

    double swing_prices[];
    int swing_bars[];
    int swing_count = 0;
    for(int i = 0; i < data_to_copy; i++)
    {
        if(zigzag_buffer[i] > 0)
        {
            ArrayResize(swing_prices, swing_count + 1);
            ArrayResize(swing_bars, swing_count + 1);
            swing_prices[swing_count] = zigzag_buffer[i];
            swing_bars[swing_count] = i;
            swing_count++;
            if(swing_count >= 10) break;
        }
    }

    if(swing_count < 3) return "データ不足";

    double prev_swing_pips = 0;
    int valid_prev_swing_start_index = -1;
    for(int i = 0; i < swing_count - 1; i++)
    {
        double p1 = swing_prices[i];
        double p2 = swing_prices[i+1];
        int bar_p2 = swing_bars[i+1];
        double swing_size = MathAbs(p1 - p2);

        double atr_buffer[];
        if(CopyBuffer(h_atr_swing[tf_index], 0, bar_p2, 1, atr_buffer) > 0)
        {
            if(swing_size > (atr_buffer[0] * InpSwing_MinAtrMultiplier))
            {
                prev_swing_pips = (swing_size / _Point) / 10.0;
                valid_prev_swing_start_index = i + 1;
                break;
            }
        }
    }

    if(prev_swing_pips <= 0) return "有効スイングなし";

    g_prev_swing_start[tf_index].price = swing_prices[valid_prev_swing_start_index];
    g_prev_swing_start[tf_index].time  = iTime(_Symbol, tf, swing_bars[valid_prev_swing_start_index]);
    g_prev_swing_end[tf_index].price = swing_prices[valid_prev_swing_start_index - 1];
    g_prev_swing_end[tf_index].time  = iTime(_Symbol, tf, swing_bars[valid_prev_swing_start_index - 1]);
    g_curr_swing_start[tf_index] = g_prev_swing_end[tf_index];

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return "---";
    double current_price = (tick.ask + tick.bid) / 2.0;
    double latest_swing_price = g_curr_swing_start[tf_index].price;
    double current_swing_pips = (MathAbs(current_price - latest_swing_price) / _Point) / 10.0;
    
    if(prev_swing_pips < 0.1) return "計算不能 (ゼロ除算)";
    double ratio = (current_swing_pips / prev_swing_pips) * 100.0;

    string direction = (current_price > latest_swing_price) ? "▲" : "▼";
    if (ratio > 50.0)
    {
        if (direction == "▲") out_color = clrLime;
        else out_color = clrTomato;
    }
    
    string result = StringFormat("%s %.0f%% (現:%.1f / 前:%.1f pips)", direction, ratio, current_swing_pips, prev_swing_pips);
    
    // --- 計算結果をキャッシュに保存 ---
    g_swing_info_cache[tf_index] = result;
    g_swing_color_cache[tf_index] = out_color;
    g_swing_cache_bartime[tf_index] = current_bar_time;

    return result;
}

//+------------------------------------------------------------------+
//| 参照しているスイングをチャートに描画する
//+------------------------------------------------------------------+
void ManageSwingVisuals()
{
    // --- 過去の描画を一旦すべて削除 ---
    for(int i=0; i<ENUM_TIMEFRAMES_COUNT; i++)
    {
        ObjectDelete(0, "Swing_Prev_TF" + (string)i);
        ObjectDelete(0, "Swing_Curr_TF" + (string)i);
    }

    // --- 設定がOFFならここで終了 ---
    if(!InpSwing_VisualizeSwings) return;

    // --- 現在のチャートの時間足に合致するスイング情報のみ描画 ---
    int tf_index = -1;
    if(_Period == _Period) tf_index = TF_CURRENT_INDEX;
    if(_Period == InpIntermediateTimeframe) tf_index = TF_INTERMEDIATE_INDEX;
    if(_Period == InpHigherTimeframe) tf_index = TF_HIGHER_INDEX;

    if(tf_index != -1 && g_curr_swing_start[tf_index].time > 0)
    {
        // --- 前のスイングを描画 ---
        string prev_name = "Swing_Prev_TF" + (string)tf_index;
        if(ObjectCreate(0, prev_name, OBJ_TREND, 0, g_prev_swing_start[tf_index].time, g_prev_swing_start[tf_index].price, g_prev_swing_end[tf_index].time, g_prev_swing_end[tf_index].price))
        {
            ObjectSetInteger(0, prev_name, OBJPROP_COLOR, clrDodgerBlue);
            ObjectSetInteger(0, prev_name, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, prev_name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, prev_name, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, prev_name, OBJPROP_SELECTABLE, false);
        }

        // --- 現在のスイングを描画 ---
        string curr_name = "Swing_Curr_TF" + (string)tf_index;
        MqlTick tick;
        if(SymbolInfoTick(_Symbol, tick))
        {
            if(ObjectCreate(0, curr_name, OBJ_TREND, 0, g_curr_swing_start[tf_index].time, g_curr_swing_start[tf_index].price, TimeCurrent(), (tick.ask+tick.bid)/2.0))
            {
                ObjectSetInteger(0, curr_name, OBJPROP_COLOR, clrOrangeRed);
                ObjectSetInteger(0, curr_name, OBJPROP_STYLE, STYLE_SOLID);
                ObjectSetInteger(0, curr_name, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, curr_name, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, curr_name, OBJPROP_SELECTABLE, false);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 【パフォーマンス改善版】新しい足ができた時にパネルの静的情報を更新する
//+------------------------------------------------------------------+
void UpdateInfoPanel_NewBar()
{
    if(!InpShowInfoPanel)
    {
        ObjectsDeleteAll(0, g_panelPrefix);
        return;
    }

    ENUM_BASE_CORNER  corner = CORNER_LEFT_UPPER;
    ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT;
    bool is_lower_corner = false;
    switch(InpPanelCorner)
    {
        case PC_LEFT_UPPER:  corner = CORNER_LEFT_UPPER;  anchor = ANCHOR_LEFT;  break;
        case PC_RIGHT_UPPER: corner = CORNER_RIGHT_UPPER; anchor = ANCHOR_RIGHT; break;
        case PC_LEFT_LOWER:  corner = CORNER_LEFT_LOWER;  anchor = ANCHOR_LEFT;  is_lower_corner = true; break;
        case PC_RIGHT_LOWER: corner = CORNER_RIGHT_LOWER; anchor = ANCHOR_RIGHT; is_lower_corner = true; break;
    }

    // --- 事前に全行の高さを計算 ---
    int line_heights[];
    int line_count = 0;
    #define PREP_LINE(fs) ArrayResize(line_heights, line_count + 1); line_heights[line_count] = (int)round(fs * 1.5); line_count++;

    PREP_LINE(InpPanelFontSize); // Title
    PREP_LINE(InpPanelFontSize); // Separator
    PREP_LINE(InpPanelFontSize); // Market Cycle
    PREP_LINE(InpPanelFontSize + 2); // Trade Bias
    PREP_LINE(InpPanelFontSize); // Buy Score
    PREP_LINE(InpPanelFontSize); // Sell Score
    PREP_LINE(InpPanelFontSize); // Entry Status
    PREP_LINE(InpPanelFontSize); // Separator
    PREP_LINE(InpPanelFontSize); // MTF Header
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++) {
        PREP_LINE(InpPanelFontSize); // TF State
        PREP_LINE(InpPanelFontSize); // Long MA
        PREP_LINE(InpPanelFontSize); // Obi MACD
    }
    PREP_LINE(InpPanelFontSize); // Separator
    PREP_LINE(InpPanelFontSize); // Swing Header
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++) {
        PREP_LINE(InpPanelFontSize); // Swing Info
    }
    PREP_LINE(InpPanelFontSize); // Next Bar (ここはタイマーで更新するが、場所確保のために計算)

    // --- Y座標の計算と描画実行 ---
    int line_index = 0;
    int current_y_pos = p_panel_y_offset;
    int y_step = 0;
    if(is_lower_corner)
    {
        int total_height = 0;
        for(int i = 0; i < line_count; i++) total_height += line_heights[i];
        current_y_pos += total_height;
    }

    #define DRAW_LINE_STATIC(fs, txt, icn, tc, ic) \
        y_step = (int)round(fs * 1.5); \
        if(is_lower_corner) current_y_pos -= y_step; \
        DrawPanelLine(line_index, current_y_pos, txt, icn, tc, ic, corner, anchor, fs); \
        if(!is_lower_corner) current_y_pos += y_step; \
        line_index++;

    // --- 描画開始 (静的情報のみ) ---
    DRAW_LINE_STATIC(InpPanelFontSize, "▶ ApexFlowEA v7.2 (市場サイクルモデル)", "", clrWhite, clrNONE);
    DRAW_LINE_STATIC(InpPanelFontSize, "──────────────────", "", clrGainsboro, clrNONE);
    
    string category_text = GetBiasCategoryToString(g_env_state.current_trade_bias);
    DRAW_LINE_STATIC(InpPanelFontSize, "市場サイクル: " + category_text, "", clrWhite, clrNONE);

    string bias_text, bias_icon;
    color bias_color;
    TradeBiasToString(g_env_state.current_trade_bias, bias_text, bias_icon, bias_color);
    DRAW_LINE_STATIC(InpPanelFontSize + 2, "取引バイアス: " + bias_text, bias_icon, clrWhite, bias_color);
    
    string buy_score_bar = "", sell_score_bar = "";
    int buy_bar_length = (InpScorePerSymbol > 0) ? (int)MathRound((double)g_env_state.total_buy_score / InpScorePerSymbol) : 0;
    for(int i = 0; i < buy_bar_length; i++) buy_score_bar += "●";
    int sell_bar_length = (InpScorePerSymbol > 0) ? (int)MathRound((double)g_env_state.total_sell_score / InpScorePerSymbol) : 0;
    for(int i = 0; i < sell_bar_length; i++) sell_score_bar += "●";
    DRAW_LINE_STATIC(InpPanelFontSize, "BUY優位性: " + buy_score_bar + " (" + (string)g_env_state.total_buy_score + ")", "", clrLime, clrNONE);
    DRAW_LINE_STATIC(InpPanelFontSize, "SELL優位性: " + sell_score_bar + " (" + (string)g_env_state.total_sell_score + ")", "", clrTomato, clrNONE);
    
    bool buy_signal_active = false, sell_signal_active = false;
    string buy_signal_name, sell_signal_name;
    CheckActiveEntrySignals(buy_signal_active, sell_signal_active, buy_signal_name, sell_signal_name);
    if(buy_signal_active && g_env_state.total_buy_score >= InpEntryScore) {
        DRAW_LINE_STATIC(InpPanelFontSize, "ENTRY: BUYトリガー", "✔", clrGreen, clrGreen);
    } else if(sell_signal_active && g_env_state.total_sell_score >= InpEntryScore) {
        DRAW_LINE_STATIC(InpPanelFontSize, "ENTRY: SELLトリガー", "✔", clrRed, clrRed);
    } else {
        DRAW_LINE_STATIC(InpPanelFontSize, "ENTRY: 待機中", "", clrGainsboro, clrNONE);
    }
    
    DRAW_LINE_STATIC(InpPanelFontSize, "──────────────────", "", clrGainsboro, clrNONE);
    DRAW_LINE_STATIC(InpPanelFontSize, "■ MTFトレンド概要", "", clrGainsboro, clrNONE);
    
    ENUM_TIMEFRAMES mtf_periods[ENUM_TIMEFRAMES_COUNT];
    mtf_periods[TF_CURRENT_INDEX] = _Period; mtf_periods[TF_INTERMEDIATE_INDEX] = InpIntermediateTimeframe; mtf_periods[TF_HIGHER_INDEX] = InpHigherTimeframe;
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++) {
        string tf_string_full = EnumToString(mtf_periods[i]);
        StringReplace(tf_string_full, "PERIOD_", "");
        string tf_name = (i == TF_CURRENT_INDEX) ? tf_string_full + "(現)" : (i == TF_INTERMEDIATE_INDEX) ? tf_string_full + "(中)" : tf_string_full + "(高)";
        color stage_color; string stage_text = MasterStateToString(g_env_state.mtf_master_state[i], stage_color);
        DRAW_LINE_STATIC(InpPanelFontSize, "  TF(" + tf_name + "): " + stage_text, "", stage_color, clrNONE);
        
        string long_slope_text = SlopeStateToString(g_env_state.mtf_slope_long[i]);
        DRAW_LINE_STATIC(InpPanelFontSize, "    ├ 長期MA: " + long_slope_text, "", clrWhite, clrNONE);
        string obi_macd_status = ObiMacdToString(g_env_state.mtf_macd_values[i]);
        DRAW_LINE_STATIC(InpPanelFontSize, "    └ 帯MACD: " + obi_macd_status, "", clrWhite, clrNONE);
    }

    DRAW_LINE_STATIC(InpPanelFontSize, "──────────────────", "", clrGainsboro, clrNONE);
    DRAW_LINE_STATIC(InpPanelFontSize, "■ 現在のスイング情報", "", clrGainsboro, clrNONE);
    
    for(int i = 0; i < ENUM_TIMEFRAMES_COUNT; i++) {
        ENUM_TIMEFRAMES tf_to_check;
        if(i == TF_CURRENT_INDEX) tf_to_check = _Period;
        else if(i == TF_INTERMEDIATE_INDEX) tf_to_check = InpIntermediateTimeframe;
        else tf_to_check = InpHigherTimeframe;
        string tf_string_full = EnumToString(tf_to_check);
        StringReplace(tf_string_full, "PERIOD_", "");
        string tf_name = (i == TF_CURRENT_INDEX) ? tf_string_full + "(現)" : (i == TF_INTERMEDIATE_INDEX) ? tf_string_full + "(中)" : tf_string_full + "(高)";
        color swing_info_color;
        string swing_info = GetSwingRatioInfo(i, swing_info_color);
        DRAW_LINE_STATIC(InpPanelFontSize, "  TF(" + tf_name + "): " + swing_info, "", swing_info_color, clrNONE);
    }
    
    // 次の足までの時間はタイマーで更新するため、ここではプレースホルダを描画
    DRAW_LINE_STATIC(InpPanelFontSize, "Next Bar: ...", "", clrGainsboro, clrNONE);
    
    // 不要な行をクリア
    for(int i = line_index; i < 50; i++) 
    {
        ObjectSetString(0, g_panelPrefix + "Text_" + (string)i, OBJPROP_TEXT, "");
        ObjectSetString(0, g_panelPrefix + "Icon_" + (string)i, OBJPROP_TEXT, "");
    }
}

//+------------------------------------------------------------------+
//| 【パフォーマンス改善版】タイマーでパネルの動的情報（残り時間）のみを更新する
//+------------------------------------------------------------------+
void UpdateInfoPanel_Timer()
{
    if(!InpShowInfoPanel) return;

    // --- 静的情報が描画される行数を正確に計算 ---
    int next_bar_line_index = 0;
    next_bar_line_index++; // Title
    next_bar_line_index++; // Separator
    next_bar_line_index++; // Market Cycle
    next_bar_line_index++; // Trade Bias
    next_bar_line_index++; // Buy Score
    next_bar_line_index++; // Sell Score
    next_bar_line_index++; // Entry Status
    next_bar_line_index++; // Separator
    next_bar_line_index++; // MTF Header
    next_bar_line_index += (ENUM_TIMEFRAMES_COUNT * 3); // MTF Info
    next_bar_line_index++; // Separator
    next_bar_line_index++; // Swing Header
    next_bar_line_index += ENUM_TIMEFRAMES_COUNT; // Swing Info

    // --- 「次の足まで」の行だけを特定して更新 ---
    long time_remaining = (iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period)) - TimeCurrent();
    if (time_remaining < 0) time_remaining = 0;
    string text = StringFormat("Next Bar: %02d:%02d", time_remaining / 60, time_remaining % 60);

    string text_obj_name = g_panelPrefix + "Text_" + (string)next_bar_line_index;

    // オブジェクトが存在するか確認してから更新
    if(ObjectFind(0, text_obj_name) >= 0)
    {
       ObjectSetString(0, text_obj_name, OBJPROP_TEXT, text);
    }
}