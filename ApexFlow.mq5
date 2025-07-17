//+------------------------------------------------------------------+
//|                 Git ApexFlowEA.mq5 (統合戦略モデル)                |
//|               (傾斜ダイナミクス + 大循環MACD 先行指標)             |
//|                         Version: 6.1 (Full-Commented)            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "6.1"
#property description "Ver6.1: 傾斜ダイナミクスと大循環MACDを統合したFSM分析エンジン。日本語コメントを完全復元。"

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

//+------------------------------------------------------------------+
//|                  すべての enum / struct 定義                     |
//+------------------------------------------------------------------+

// ==================================================================
// --- 状態定義 (enum) ---
// ==================================================================

// 傾斜状態の定義
enum ENUM_SLOPE_STATE
{
    SLOPE_UP_STRONG,    // 強い上昇
    SLOPE_UP_WEAK,      // 弱い上昇
    SLOPE_FLAT,         // 横ばい
    SLOPE_DOWN_WEAK,    // 弱い下降
    SLOPE_DOWN_STRONG   // 強い下降
};

// マスター状態の定義 (EAの統合的な状態)
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

// サポート/レジスタンスの種別
enum ENUM_LINE_TYPE
{
    LINE_TYPE_SUPPORT,
    LINE_TYPE_RESISTANCE
};

// 分割決済の順序ロジック
enum ENUM_EXIT_LOGIC
{
    EXIT_FIFO,          // 先入れ先出し
    EXIT_UNFAVORABLE,   // 不利なポジションから決済
    EXIT_FAVORABLE      // 有利なポジションから決済
};

// TPラインの計算モード
enum ENUM_TP_MODE
{
    MODE_ZIGZAG,
    MODE_PIVOT
};

// パネルの表示コーナー
enum ENUM_PANEL_CORNER
{
    PC_LEFT_UPPER,      // 左上
    PC_RIGHT_UPPER,     // 右上
    PC_LEFT_LOWER,      // 左下
    PC_RIGHT_LOWER      // 右下
};

// ==================================================================
// --- データ保持構造 (struct) ---
// ==================================================================

// 大循環MACDの構成要素
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

// 【新版】環境分析結果を保持する構造体
struct EnvironmentState
{
    ENUM_MASTER_STATE   master_state;
    int                 primary_stage;
    int                 prev_primary_stage;
    ENUM_SLOPE_STATE    slope_short;
    ENUM_SLOPE_STATE    slope_middle;
    ENUM_SLOPE_STATE    slope_long;
    DaijunkanMACDValues macd_values;
    int                 currentBuyScore;
    int                 currentSellScore;
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

// 互換性のために残す古い構造体（最終的に削除予定）
struct ScoreComponentInfo { int total_score; };

//+------------------------------------------------------------------+
//|                     入力パラメータ (input)                         |
//+------------------------------------------------------------------+
input group "=== 大循環分析 設定 ===";
input int               InpGCMAShortPeriod      = 5;          // 短期MAの期間
input int               InpGCMAMiddlePeriod     = 20;         // 中期MAの期間
input int               InpGCMALongPeriod       = 40;         // 長期MAの期間
input ENUM_MA_METHOD    InpGCMAMethod           = MODE_EMA;   // MAの種別
input ENUM_APPLIED_PRICE InpGCMAAppliedPrice    = PRICE_CLOSE;// MAの適用価格

input group "=== 傾斜ダイナミクス設定 ===";
input double InpSlopeUpStrong   = 0.3;   // 「強い上昇」と判断する正規化傾斜の閾値
input double InpSlopeUpWeak     = 0.1;   // 「弱い上昇」と判断する正規化傾斜の閾値
input double InpSlopeDownWeak   = -0.1;  // 「弱い下降」と判断する正規化傾斜の閾値
input double InpSlopeDownStrong = -0.3;  // 「強い下降」と判断する正規化傾斜の閾値
input int    InpSlopeLookback   = 1;     // 傾き計算のルックバック期間(n)
input int    InpSlopeAtrPeriod  = 14;    // 傾き正規化のためのATR期間(p)

input group "=== ストキャス設定 ===";
input int  InpStoch_K_Period    = 26; // %K期間
input int  InpStoch_D_Period    = 3;  // %D期間
input int  InpStoch_Slowing     = 3;  // スローイング
input int  InpStoch_Upper_Level = 80; // 上限レベル（売りシグナル判定用）
input int  InpStoch_Lower_Level = 20; // 下限レベル（買いシグナル判定用）

input group "=== エントリーロジック設定 ===";
input bool            InpUsePivotLines      = true;     // ピボットラインを使用する
input ENUM_TIMEFRAMES InpPivotPeriod        = PERIOD_H1;// ピボット時間足
input bool   InpShowS2R2          = true;       // S2/R2ラインを表示
input bool   InpShowS3R3          = true;       // S3/R3ラインを表示
input int    InpPivotHistoryCount = 1;     // 表示する過去ピボットの数

enum ENTRY_MODE { TOUCH_MODE, ZONE_MODE, HYBRID_MODE };
input ENTRY_MODE      InpEntryMode          = HYBRID_MODE; // エントリーモード
input bool            InpEnableZoneMacdCross= true;     // (ゾーンモード限定) ゾーン内MACDクロスエントリーを有効にする
input bool            InpVisualizeZones     = true;     // (ゾーン/ハイブリッド) ゾーンを可視化する
input bool            InpBreakMode          = true;     // ブレイクモード (タッチモード用)
input bool            InpAllowSignalAfterBreak = true;   // ブレイク後の再シグナルを許可する
input double          InpZonePips           = 50.0;     // ゾーン幅 (pips)
input int             InpEntryScore         = 5;        // エントリーの最低スコア

input group "=== 取引設定 ===";
input double InpLotSize             = 0.1;    // ロットサイズ
input int    InpMaxPositions        = 5;      // 同方向の最大ポジション数
input bool   InpEnableRiskBasedLot  = true;   // リスクベースの自動ロット計算を有効にする
input double InpRiskPercent         = 1.0;    // 1トレードあたりのリスク許容率 (% of balance)
input bool   InpEnableHighScoreRisk = true;   // 高スコア時にリスクを変更する
input double InpHighScoreRiskPercent= 2.0;    // 高スコア時のリスク許容率 (%)
input int    InpHighScoreThreshold  = 8;      // 高スコアと判断する閾値
input bool   InpEnableEntrySpacing  = true;   // ポジション間隔フィルターを有効にする
input double InpEntrySpacingPips    = 10.0;   // 最低限確保するポジション間隔 (pips)
input int    InpMagicNumber         = 123456; // マジックナンバー
input int    InpDotTimeout          = 600;    // ドット/矢印有効期限 (秒)

enum ENUM_SL_MODE { SL_MODE_ATR, SL_MODE_MANUAL, SL_MODE_OPPOSITE_TP };
input group "=== ストップロス設定 ===";
input ENUM_SL_MODE    InpSlMode          = SL_MODE_ATR; // SLモード
input bool            InpEnableAtrSL     = true;        // ATR SLを有効にする
input double          InpAtrSlMultiplier = 2.5;        // ATR SLの倍率
input ENUM_TIMEFRAMES InpAtrSlTimeframe  = PERIOD_H1;   // ATR SLの時間足
input bool            InpEnableTrailingSL      = true;    // トレーリングSLを有効にする
input double          InpTrailingAtrMultiplier = 2.0;    // トレーリングATRの倍率

input group "=== 動的決済ロジック ===";
input bool   InpEnableTimeExit        = true;   // タイム・エグジット（時間経過による決済）を有効にする
input int    InpExitAfterBars         = 48;     // 何本経過したら決済判断を行うか
input double InpExitMinProfit         = 1.0;    // この利益額(口座通貨)に達していない場合、時間で決済される
input bool   InpEnableCounterSignalExit = true;   // カウンターシグナル（反対サイン）による決済を有効にする
input int    InpCounterSignalScore    = 7;      // 決済のトリガーとなる反対シグナルの最低スコア

input group "=== 決済ロジック設定 (Zephyr) ===";
input ENUM_EXIT_LOGIC   InpExitLogic            = EXIT_UNFAVORABLE; // 分割決済のロジック
input int               InpSplitCount           = 3;                // 分割決済の回数
input double            InpFinalTpRR_Ratio      = 2.5;              // (ATRモード用) 最終TPのRR比
input double            InpExitBufferPips       = 1.0;              // 決済バッファ (Pips)
input int               InpBreakEvenAfterSplits = 1;                // N回分割決済後にBE設定
input bool              InpEnableProfitBE       = true;             // 利益確保型BEを有効にする
input double            InpProfitBE_Pips        = 2.0;              // 利益確保BEの幅 (pips)
input double            InpHighSchoreTpRratio   = 1.5;              // 高スコア時のTP倍率
input ENUM_TP_MODE      InpTPLineMode           = MODE_ZIGZAG;      // TPラインのモード
input ENUM_TIMEFRAMES   InpTP_Timeframe         = PERIOD_H4;        // TP計算用の時間足 (ZigZagとPivotで共用)
input int               InpZigzagDepth          = 12;               // ZigZag: Depth
input int               InpZigzagDeviation      = 5;                // ZigZag: Deviation
input int               InpZigzagBackstep       = 3;                // ZigZag: Backstep

input group "--- ダイバージェンスの可視化設定 ---";
input bool   InpShowDivergenceSignals = true;     // ダイバージェンスサインを表示するか
input string InpDivSignalPrefix       = "DivSignal_"; // サインのオブジェクト名プレフィックス
input color  InpBullishDivColor       = clrDeepSkyBlue; // 強気ダイバージェンスの色
input color  InpBearishDivColor       = clrHotPink;   // 弱気ダイバージェンスの色
input int    InpDivSymbolCode         = 159;          // サインのシンボルコード (159 = ●)
input int    InpDivSymbolSize         = 8;            // サインの大きさ
input double InpDivSymbolOffsetPips   = 15.0;         // サインの描画オフセット (Pips)

input group "=== UI設定 ===";
input ENUM_PANEL_CORNER InpPanelCorner      = PC_RIGHT_LOWER; // パネルの表示コーナー
input bool              InpShowInfoPanel    = true;           // 情報パネルを表示する
input int               p_panel_x_offset    = 10;             // パネルX位置
input int               p_panel_y_offset    = 130;            // パネルY位置
input int               InpPanelFontSize    = 14;             // パネルのフォントサイズ
input bool              InpEnableButtons    = true;           // ボタン表示を有効にする

input group "=== オブジェクトとシグナルの外観 ===";
input string InpLinePrefix_Pivot     = "Pivot_";     // ピボットラインプレフィックス
input string InpDotPrefix            = "Dot_";       // ドットプレフィックス
input string InpArrowPrefix          = "Trigger_";   // 矢印プレフィックス
input int    InpSignalWidth          = 2;            // シグナルの太さ
input int    InpSignalFontSize       = 10;           // シグナルの大きさ
input double InpSignalOffsetPips     = 2.0;          // シグナルの描画オフセット (Pips)
input int    InpTouchBreakUpCode     = 221;          // タッチブレイク買いのシンボルコード
input int    InpTouchBreakDownCode   = 222;          // タッチブレイク売りのシンボルコード
input int    InpTouchReboundUpCode   = 233;          // タッチひげ反発買いのシンボルコード
input int    InpTouchReboundDownCode = 234;          // タッチひげ反発売りのシンボルコード
input int    InpFalseBreakBuyCode    = 117;          // フォールスブレイク (買い) のシンボルコード
input int    InpFalseBreakSellCode   = 117;          // フォールスブレイク (売り) のシンボルコード
input int    InpRetestBuyCode        = 110;          // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode       = 111;          // ブレイク＆リテスト (売り) のシンボルコード
input int    InpRetestExpiryBars     = 10;           // ブレイク後のリテスト有効期限 (バーの本数)

input group "=== 手動ライン設定 ===";
input color           p_ManualSupport_Color = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color  = clrTomato;     // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style    = STYLE_DOT;     // 手動ラインのスタイル
input int             p_ManualLine_Width    = 2;             // 手動ラインの太さ

//+------------------------------------------------------------------+
//|                     グローバル変数                               |
//+------------------------------------------------------------------+
// --- インジケーターハンドル ---
int h_gc_ma_short, h_gc_ma_middle, h_gc_ma_long;
int h_macd_exec, h_macd_mid, h_macd_long;
int h_stoch, h_atr_sl, zigzagHandle;
int h_atr_slope; // 新しいハンドル

// --- 状態管理 ---
EnvironmentState g_env_state;
LineState        g_lineStates[];
Line             allLines[];
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
ENUM_TP_MODE    prev_tp_mode      = WRONG_VALUE;
ENUM_TIMEFRAMES prev_tp_timeframe = WRONG_VALUE;

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
void UpdateScoresBasedOnState();
void CheckStateBasedExits();
void CheckEntry();
void PlaceOrder(bool isBuy, double price, int score);

// --- 分析ヘルパー関数 ---
bool InitSlopeAtr();
ENUM_SLOPE_STATE GetSlopeState(int ma_handle, int lookback);
DaijunkanMACDValues CalculateDaijunkanMACD();
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
void ManageInfoPanel();
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

// --- その他ヘルパー ---
bool IsNewBar();
double CalculateRiskBasedLotSize(int score);
double GetConversionRate(string from_currency, string to_currency);

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                     主要なイベントハンドラ関数                     |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| エキスパート初期化関数 (EA起動時に1回だけ呼ばれる)
//+------------------------------------------------------------------+
int OnInit()
{
    // --- 基本設定 ---
    g_pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pow(10, _Digits % 2);
    g_lastBarTime = 0;
    lastTradeTime = 0;
    g_lastPivotDrawTime = 0;
    
    // --- ハンドル作成 ---
    h_gc_ma_short = iMA(_Symbol, _Period, InpGCMAShortPeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
    h_gc_ma_middle = iMA(_Symbol, _Period, InpGCMAMiddlePeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
    h_gc_ma_long = iMA(_Symbol, _Period, InpGCMALongPeriod, 0, InpGCMAMethod, InpGCMAAppliedPrice);
    
    h_stoch = iStochastic(_Symbol, _Period, InpStoch_K_Period, InpStoch_D_Period, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
    h_atr_sl = iATR(_Symbol, InpAtrSlTimeframe, 14);
    zigzagHandle = iCustom(_Symbol, InpTP_Timeframe, "ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);
    
    // ゾーンエントリー用の古いMACDハンドルも互換性のために残す
    h_macd_exec = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    h_macd_mid  = iMACD(_Symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
    h_macd_long = iMACD(_Symbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE);

    // 新しい傾斜分析用のATRハンドルを初期化
    if(!InitSlopeAtr()) return(INIT_FAILED);
    
    // --- ハンドルチェック ---
    if(h_gc_ma_short == INVALID_HANDLE || h_gc_ma_middle == INVALID_HANDLE || h_gc_ma_long == INVALID_HANDLE || 
       h_stoch == INVALID_HANDLE || h_atr_sl == INVALID_HANDLE || zigzagHandle == INVALID_HANDLE || h_atr_slope == INVALID_HANDLE)
    {
        Print("インジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }
    
    // --- グループ初期化 ---
    InitGroup(buyGroup, true);
    InitGroup(sellGroup, false);
    
    isBuyTPManuallyMoved = false;
    isSellTPManuallyMoved = false;
    g_isZoneVisualizationEnabled = InpVisualizeZones;

    // --- ボタン作成 ---
    if(InpEnableButtons)
    {
        CreateManualLineButton();
        CreateClearButton();
        CreateClearLinesButton();
        CreateApexButton(BUTTON_BUY_CLOSE_ALL, 140, 50, 100, 20, "BUY 全決済", clrDodgerBlue);
        CreateApexButton(BUTTON_SELL_CLOSE_ALL, 140, 75, 100, 20, "SELL 全決済", clrTomato);
        CreateApexButton(BUTTON_ALL_CLOSE, 245, 50, 100, 20, "全決済", clrGray);
        CreateApexButton(BUTTON_RESET_BUY_TP, 245, 75, 100, 20, "BUY TPリセット", clrGoldenrod);
        CreateApexButton(BUTTON_RESET_SELL_TP, 245, 100, 100, 20, "SELL TPリセット", clrGoldenrod);
        CreateApexButton(BUTTON_RESET_BUY_SL, 350, 75, 100, 20, "BUY SLリセット", clrDarkOrange);
        CreateApexButton(BUTTON_RESET_SELL_SL, 350, 100, 100, 20, "SELL SLリセット", clrDarkOrange);
        CreateApexButton(BUTTON_TOGGLE_ZONES, 10, 130, 120, 20, "ゾーン表示", C'80,80,80');
        UpdateZoneButtonState();
    }
    
    // --- その他初期化 ---
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);
    prev_tp_mode = InpTPLineMode;
    prev_tp_timeframe = InpTP_Timeframe;
    UpdateLines();
    
    Print("ApexFlowEA v6.1 初期化完了 (統合戦略モデル)");
    EventSetTimer(1);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数 (EA終了時に1回だけ呼ばれる)
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    DeleteAllEaObjects();

    IndicatorRelease(h_gc_ma_short);
    IndicatorRelease(h_gc_ma_middle);
    IndicatorRelease(h_gc_ma_long);
    IndicatorRelease(h_stoch);
    IndicatorRelease(h_atr_sl);
    IndicatorRelease(zigzagHandle);
    IndicatorRelease(h_macd_exec);
    IndicatorRelease(h_macd_mid);
    IndicatorRelease(h_macd_long);
    IndicatorRelease(h_atr_slope); // 新しいハンドルを解放
    
    ChartRedraw();
    PrintFormat("ApexFlowEA v6.1 終了: 理由=%d。", reason);
}

//+------------------------------------------------------------------+
//| エキスパートティック関数 (ティック毎に呼ばれるメインループ)
//+------------------------------------------------------------------+
void OnTick()
{
    // --- ティック毎に必ず実行する処理 ---
    // 1. 最新の相場状態を分析
    UpdateEnvironmentAnalysis();
    // 2. パネルを更新
    ManageInfoPanel();

    // --- 決済ロジック ---
    // 3. 新しい状態ベースの決済
    CheckStateBasedExits();
    // 4. 分割決済 (TP)
    CheckExitForGroup(buyGroup);
    CheckExitForGroup(sellGroup);
    // 5. トレーリングストップ
    ManageTrailingSL(buyGroup);
    ManageTrailingSL(sellGroup);

    // --- 新しい足ができた時に実行する重めの処理 ---
    if(IsNewBar())
    {
        // データ準備と描画
        ManageManualLines();
        
        datetime currentPivotBarTime = iTime(_Symbol, InpPivotPeriod, 0);
        if(g_lastPivotDrawTime == 0 || g_lastPivotDrawTime < currentPivotBarTime)
        {
            ManagePivotLines();
            g_lastPivotDrawTime = currentPivotBarTime;
        }
        UpdateLines();

        // シグナル生成
        ProcessLineSignals();
        CheckStochasticSignal();

        // エントリー判断
        CheckZoneMacdCross();
        CheckEntry();

        // データと描画の同期
        SyncManagedPositions();
        ManagePositionGroups();
        UpdateZones();
        ManageSlLines();
        ManageZoneVisuals();
        ChartRedraw();
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//| ================================================================ |
//|                    その他のイベントハンドラ関数                    |
//| ================================================================ |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| タイマー処理関数 (1秒ごとに呼ばれる)
//+------------------------------------------------------------------+
void OnTimer()
{
    // パネル非表示ならタイマーラベルも消して終了
    if(!InpShowInfoPanel)
    {
        ObjectDelete(0, "ApexFlow_TimerLabel");
        return;
    }
    
    string timer_obj_name = "ApexFlow_TimerLabel";
    
    // タイマーオブジェクトがなければ作成
    if(ObjectFind(0, timer_obj_name) < 0)
    {
        ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER;
        bool is_lower_corner = false;
        switch(InpPanelCorner)
        {
            case PC_LEFT_UPPER:  corner = CORNER_LEFT_UPPER; break;
            case PC_RIGHT_UPPER: corner = CORNER_RIGHT_UPPER; break;
            case PC_LEFT_LOWER:  corner = CORNER_LEFT_LOWER;  is_lower_corner = true; break;
            case PC_RIGHT_LOWER: corner = CORNER_RIGHT_LOWER; is_lower_corner = true; break;
        }

        int total_panel_lines = 15; // パネルの総行数に合わせて調整
        int y_pos_start = p_panel_y_offset;
        int y_step = (int)round(InpPanelFontSize * 1.5);
        int timer_y_pos = y_pos_start + (total_panel_lines * y_step);

        ObjectCreate(0, timer_obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, timer_obj_name, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, timer_obj_name, OBJPROP_XDISTANCE, p_panel_x_offset);
        ObjectSetInteger(0, timer_obj_name, OBJPROP_YDISTANCE, timer_y_pos);
        ObjectSetString(0, timer_obj_name, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, timer_obj_name, OBJPROP_COLOR, clrGainsboro);
        ObjectSetInteger(0, timer_obj_name, OBJPROP_FONTSIZE, InpPanelFontSize);
    }

    // 足確定までの残り時間を計算して表示
    long time_remaining = (iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period)) - TimeCurrent();
    if (time_remaining < 0) time_remaining = 0;

    string timer_text = StringFormat("Next Bar: %02d:%02d", time_remaining / 60, time_remaining % 60);
    ObjectSetString(0, timer_obj_name, OBJPROP_TEXT, timer_text);
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数 (クリックやドラッグなどを処理)
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // --- (1) オブジェクトのクリックイベント ---
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        // ボタンごとの処理
        if(sparam == g_buttonName) { g_isDrawingMode = !g_isDrawingMode; if(g_isDrawingMode) g_ignoreNextChartClick = true; UpdateButtonState(); return; }
        if(sparam == g_clearButtonName) { ClearSignalObjects(); ChartRedraw(); return; }
        if(sparam == g_clearLinesButtonName) { ClearManualLines(); ChartRedraw(); return; }
        if(sparam == BUTTON_BUY_CLOSE_ALL)  { CloseAllPositionsInGroup(buyGroup); return; }
        if(sparam == BUTTON_SELL_CLOSE_ALL) { CloseAllPositionsInGroup(sellGroup); return; }
        if(sparam == BUTTON_ALL_CLOSE) { CloseAllPositionsInGroup(buyGroup); CloseAllPositionsInGroup(sellGroup); return; }
        
        if(sparam == BUTTON_RESET_BUY_TP)
        {
            isBuyTPManuallyMoved = false;
            if(ObjectFind(0, "TPLine_Buy") >= 0) ObjectSetInteger(0, "TPLine_Buy", OBJPROP_STYLE, STYLE_DOT);
            UpdateAllVisuals();
            return;
        }
        if(sparam == BUTTON_RESET_SELL_TP)
        {
            isSellTPManuallyMoved = false;
            if(ObjectFind(0, "TPLine_Sell") >= 0) ObjectSetInteger(0, "TPLine_Sell", OBJPROP_STYLE, STYLE_DOT);
            UpdateAllVisuals();
            return;
        }

        if(sparam == BUTTON_RESET_BUY_SL)  
        {  
            isBuySLManuallyMoved = false;  
            g_slLinePrice_Buy = 0;  
            ManageSlLines();  
            if(buyGroup.isActive){ UpdateGroupSL(buyGroup); UpdateGroupSplitLines(buyGroup); }  
            ChartRedraw();
            return;  
        }
        if(sparam == BUTTON_RESET_SELL_SL)  
        {  
            isSellSLManuallyMoved = false;  
            g_slLinePrice_Sell = 0;  
            ManageSlLines();  
            if(sellGroup.isActive){ UpdateGroupSL(sellGroup); UpdateGroupSplitLines(sellGroup); }  
            ChartRedraw();
            return;  
        }
        if(sparam == BUTTON_TOGGLE_ZONES)
        {
            g_isZoneVisualizationEnabled = !g_isZoneVisualizationEnabled;
            UpdateZoneButtonState();
            ManageZoneVisuals();
            ChartRedraw();
            return;
        }
    }

    // --- (2) チャート自体のクリックイベント ---
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
    
    // --- (3) オブジェクトのドラッグイベント ---
    if(id == CHARTEVENT_OBJECT_DRAG)
    {
        if(sparam == "TPLine_Buy") { isBuyTPManuallyMoved = true; ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID); }
        if(sparam == "TPLine_Sell") { isSellTPManuallyMoved = true; ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID); }
        if(sparam == "SLLine_Buy")  isBuySLManuallyMoved = true;
        if(sparam == "SLLine_Sell") isSellSLManuallyMoved = true;
        return;
    }

    // --- (4) オブジェクトの編集終了イベント ---
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
//| 【FSM修正版】環境分析を実行し、結果をg_env_stateに格納する
//+------------------------------------------------------------------+
void UpdateEnvironmentAnalysis()
{
    // --- 1. 毎ティック最新のデータを計算 ---
    ZeroMemory(g_env_state); // グローバル変数をリセット

    g_env_state.slope_short  = GetSlopeState(h_gc_ma_short, InpSlopeLookback);
    g_env_state.slope_middle = GetSlopeState(h_gc_ma_middle, InpSlopeLookback);
    g_env_state.slope_long   = GetSlopeState(h_gc_ma_long, InpSlopeLookback);
    g_env_state.macd_values = CalculateDaijunkanMACD();
    g_env_state.primary_stage = GetPrimaryStage(0);
    g_env_state.prev_primary_stage = GetPrimaryStage(1);

    // --- 2. 現在の「伝統的ステージ」に基づいて、新しい「マスター状態」を決定する ---
    ENUM_MASTER_STATE new_state = STATE_UNKNOWN;

    switch(g_env_state.primary_stage)
    {
        case 1: // ステージ1 (上昇トレンド)
            if(g_env_state.slope_long >= SLOPE_UP_WEAK)
                new_state = STATE_1B_CONFIRMED; // 長期MAが上昇なら本物
            else if(g_env_state.slope_short < SLOPE_FLAT)
                new_state = STATE_1C_MATURE;    // 短期MAが失速なら成熟
            else
                new_state = STATE_1A_NASCENT;   // それ以外は予兆
            break;

        case 2: // ステージ2 (上昇トレンドの調整)
            if(g_env_state.slope_long >= SLOPE_UP_WEAK)
                new_state = STATE_2_PULLBACK;       // 長期MAが強ければ「押し目」
            else
                new_state = STATE_2_REVERSAL_WARN;  // 長期MAが弱ければ「転換警告」
            break;

        case 3: // ステージ3 (下降への転換期)
        { // ▼▼▼ 修正: 波括弧 { を追加 ▼▼▼
            bool is_dc_ready = g_env_state.macd_values.is_obi_dc || (g_env_state.macd_values.obi_macd < g_env_state.macd_values.signal && g_env_state.macd_values.obi_macd_slope < 0);
            bool is_slope_weak = g_env_state.slope_long <= SLOPE_FLAT;
            if(is_dc_ready && is_slope_weak)
                new_state = STATE_3_TRANSITION_DOWN; // 条件が揃えば下降へ移行
            else
                new_state = STATE_3_REJECTION;       // 条件が揃わなければ「下降失敗」
            break;
        } // ▲▲▲ 修正: 波括弧 } を追加 ▲▲▲

        case 4: // ステージ4 (下降トレンド)
            if(g_env_state.slope_long <= SLOPE_DOWN_WEAK)
                new_state = STATE_4B_CONFIRMED;
            else if(g_env_state.slope_short > SLOPE_FLAT)
                new_state = STATE_4C_MATURE;
            else
                new_state = STATE_4A_NASCENT;
            break;

        case 5: // ステージ5 (下降トレンドの調整)
            if(g_env_state.slope_long <= SLOPE_DOWN_WEAK)
                new_state = STATE_5_RALLY;
            else
                new_state = STATE_5_REVERSAL_WARN;
            break;

        case 6: // ステージ6 (上昇への転換期)
        { // ▼▼▼ 修正: 波括弧 { を追加 ▼▼▼
            bool is_gc_ready = g_env_state.macd_values.is_obi_gc || (g_env_state.macd_values.obi_macd > g_env_state.macd_values.signal && g_env_state.macd_values.obi_macd_slope > 0);
            bool is_slope_ok = g_env_state.slope_long >= SLOPE_FLAT;
            if(is_gc_ready && is_slope_ok)
                new_state = STATE_6_TRANSITION_UP;
            else
                new_state = STATE_6_REJECTION;
            break;
        } // ▲▲▲ 修正: 波括弧 } を追加 ▲▲▲
    }
    
    g_env_state.master_state = new_state;
    
    // --- 3. 新しい状態に基づいてスコアを更新 ---
    UpdateScoresBasedOnState();
}

//+------------------------------------------------------------------+
//| 【新設】状態に基づいてスコアを更新する
//+------------------------------------------------------------------+
void UpdateScoresBasedOnState()
{
    g_env_state.currentBuyScore = 0;
    g_env_state.currentSellScore = 0;
    int score = 0;

    switch(g_env_state.master_state)
    {
        case STATE_1B_CONFIRMED:      score = 10; g_env_state.currentBuyScore = score; break;
        case STATE_2_PULLBACK:        score = 8;  g_env_state.currentBuyScore = score; break;
        case STATE_3_REJECTION:       score = 9;  g_env_state.currentBuyScore = score; break;
        case STATE_1A_NASCENT:        score = 6;  g_env_state.currentBuyScore = score; break;
        case STATE_5_REVERSAL_WARN:   score = 5;  g_env_state.currentBuyScore = score; break;
        case STATE_6_TRANSITION_UP:   score = 5;  g_env_state.currentBuyScore = score; break;
        case STATE_4B_CONFIRMED:      score = 10; g_env_state.currentSellScore = score; break;
        case STATE_5_RALLY:           score = 8;  g_env_state.currentSellScore = score; break;
        case STATE_6_REJECTION:       score = 9;  g_env_state.currentSellScore = score; break;
        case STATE_4A_NASCENT:        score = 6;  g_env_state.currentSellScore = score; break;
        case STATE_2_REVERSAL_WARN:   score = 5;  g_env_state.currentSellScore = score; break;
        case STATE_3_TRANSITION_DOWN: score = 5;  g_env_state.currentSellScore = score; break;
        default: break;
    }
}

//+------------------------------------------------------------------+
//| 【新設】状態に基づいて決済を判断する統合関数
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
                if (g_env_state.master_state == STATE_1C_MATURE || g_env_state.master_state == STATE_2_REVERSAL_WARN || g_env_state.master_state == STATE_4B_CONFIRMED || g_env_state.master_state == STATE_6_REJECTION)
                {
                    should_close = true;
                    reason = "状態変化(BUY決済): " + EnumToString(g_env_state.master_state);
                }
            }
            else
            {
                if (g_env_state.master_state == STATE_4C_MATURE || g_env_state.master_state == STATE_5_REVERSAL_WARN || g_env_state.master_state == STATE_1B_CONFIRMED || g_env_state.master_state == STATE_3_REJECTION)
                {
                    should_close = true;
                    reason = "状態変化(SELL決済): " + EnumToString(g_env_state.master_state);
                }
            }

            if (!should_close && InpEnableTimeExit)
            {
                datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                int bars_held = iBarShift(_Symbol, _Period, open_time, false);
                if (bars_held > InpExitAfterBars && (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)) < InpExitMinProfit)
                {
                    should_close = true;
                    reason = "時間経過";
                }
            }

            if (!should_close && InpEnableCounterSignalExit)
            {
                if(pos_type == POSITION_TYPE_BUY && g_env_state.currentSellScore >= InpCounterSignalScore)
                {
                     should_close = true;
                     reason = "反対シグナル(SELLスコア " + (string)g_env_state.currentSellScore + ")";
                }
                if(pos_type == POSITION_TYPE_SELL && g_env_state.currentBuyScore >= InpCounterSignalScore)
                {
                     should_close = true;
                     reason = "反対シグナル(BUYスコア " + (string)g_env_state.currentBuyScore + ")";
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
//| 【FSM版】新規エントリーを探す
//+------------------------------------------------------------------+
void CheckEntry()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;
    datetime currentTime = rates[0].time;
    bool buy_trigger = false, sell_trigger = false;

    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_ARROW);
        if(StringFind(name, InpArrowPrefix) != 0 && StringFind(name, InpDotPrefix) != 0) continue;
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
        if(currentTime - objTime > InpDotTimeout) continue;

        if(!buy_trigger && (StringFind(name, "_Buy") > 0 || StringFind(name, "_Buy_") > 0)) buy_trigger = true;
        if(!sell_trigger && (StringFind(name, "_Sell") > 0 || StringFind(name, "_Sell_") > 0)) sell_trigger = true;
        if(buy_trigger && sell_trigger) break;
    }

    if((buy_trigger || sell_trigger) && (TimeCurrent() > lastTradeTime + 5))
    {
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick)) return;

        if(buy_trigger && g_env_state.currentBuyScore >= InpEntryScore)
        {
            if (buyGroup.positionCount < InpMaxPositions) PlaceOrder(true, tick.ask, g_env_state.currentBuyScore);
        }
        
        if(sell_trigger && g_env_state.currentSellScore >= InpEntryScore)
        {
            if (sellGroup.positionCount < InpMaxPositions) PlaceOrder(false, tick.bid, g_env_state.currentSellScore);
        }
    }
}

//+------------------------------------------------------------------+
//| 【FSM版】注文を発注する
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, int score)
{
    double lot_size;
    if(InpEnableRiskBasedLot) { lot_size = CalculateRiskBasedLotSize(score); }
    else { lot_size = InpLotSize; }
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
    
    color state_color;
    req.comment = StringFormat("%s (State:%s Score:%d)", 
                                (string)(isBuy ? "Buy" : "Sell"), 
                                MasterStateToString(g_env_state.master_state, state_color), 
                                score);
                                
    req.type_filling = ORDER_FILLING_FOK;

    if(!OrderSend(req, res)) { Print("OrderSend error ", GetLastError()); }
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

                double sl_price = 0;
                if(InpSlMode == SL_MODE_OPPOSITE_TP) sl_price = isBuy ? zonalFinalTPLine_Sell : zonalFinalTPLine_Buy;
                else if(InpSlMode == SL_MODE_MANUAL) sl_price = isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell;
                else if(InpEnableAtrSL)
                {
                    double atr_buffer[1];
                    if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
                    {
                        sl_price = isBuy ? price - (atr_buffer[0] * InpAtrSlMultiplier) : price + (atr_buffer[0] * InpAtrSlMultiplier);
                    }
                }
                if(sl_price > 0) ModifyPositionSL(ticket, sl_price);
                
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
//| 移動平均線の傾斜状態を取得する
//+------------------------------------------------------------------+
ENUM_SLOPE_STATE GetSlopeState(int ma_handle, int lookback)
{
    double ma_buffer[];
    if(CopyBuffer(ma_handle, 0, 0, lookback + 1, ma_buffer) < lookback + 1) return SLOPE_FLAT;
    
    double atr_buffer[];
    if(CopyBuffer(h_atr_slope, 0, 0, 1, atr_buffer) < 1) return SLOPE_FLAT;

    double current_ma = ma_buffer[0];
    double past_ma = ma_buffer[lookback];
    double atr_value = atr_buffer[0];

    if (atr_value < _Point) return SLOPE_FLAT;

    double normalized_slope = (current_ma - past_ma) / atr_value;

    if (normalized_slope > InpSlopeUpStrong)    return SLOPE_UP_STRONG;
    if (normalized_slope > InpSlopeUpWeak)      return SLOPE_UP_WEAK;
    if (normalized_slope < InpSlopeDownStrong)  return SLOPE_DOWN_STRONG;
    if (normalized_slope < InpSlopeDownWeak)    return SLOPE_DOWN_WEAK;
    
    return SLOPE_FLAT;
}

//+------------------------------------------------------------------+
//| 大循環MACDの値を計算する
//+------------------------------------------------------------------+
DaijunkanMACDValues CalculateDaijunkanMACD()
{
    DaijunkanMACDValues result;
    ZeroMemory(result);

    int buffer_size = 15; 
    double short_ma[], middle_ma[], long_ma[];
    if(CopyBuffer(h_gc_ma_short, 0, 0, buffer_size, short_ma) < buffer_size ||
       CopyBuffer(h_gc_ma_middle, 0, 0, buffer_size, middle_ma) < buffer_size ||
       CopyBuffer(h_gc_ma_long, 0, 0, buffer_size, long_ma) < buffer_size)
    {
        return result;
    }
    
    result.macd1 = short_ma[0] - middle_ma[0];
    result.macd2 = short_ma[0] - long_ma[0];
    result.obi_macd = middle_ma[0] - long_ma[0];

    double obi_macd_history[];
    ArrayResize(obi_macd_history, buffer_size);
    for(int i = 0; i < buffer_size; i++)
    {
        obi_macd_history[i] = middle_ma[i] - long_ma[i];
    }
    
    double signal_sum = 0;
    int signal_period = 9;
    if(buffer_size >= signal_period)
    {
        for(int i = 0; i < signal_period; i++) signal_sum += obi_macd_history[i];
        result.signal = signal_sum / signal_period;
    }

    double prev_obi_macd = middle_ma[1] - long_ma[1];
    double prev_signal_sum = 0;
    if(buffer_size >= signal_period + 1)
    {
        for(int i = 1; i < signal_period + 1; i++) prev_signal_sum += obi_macd_history[i];
        double prev_signal = prev_signal_sum / signal_period;
        
        if(prev_obi_macd <= prev_signal && result.obi_macd > result.signal) result.is_obi_gc = true;
        if(prev_obi_macd >= prev_signal && result.obi_macd < result.signal) result.is_obi_dc = true;
    }
    
    result.obi_macd_slope = result.obi_macd - prev_obi_macd;

    return result;
}

//+------------------------------------------------------------------+
//| 伝統的な大循環分析のステージ番号を取得する
//+------------------------------------------------------------------+
int GetPrimaryStage(int shift)
{
    double s[], m[], l[];
    if(CopyBuffer(h_gc_ma_short, 0, shift, 1, s) < 1 ||
       CopyBuffer(h_gc_ma_middle, 0, shift, 1, m) < 1 ||
       CopyBuffer(h_gc_ma_long, 0, shift, 1, l) < 1)
    {
        return 0;
    }

    if (s[0] > m[0] && m[0] > l[0]) return 1;
    if (m[0] > s[0] && s[0] > l[0]) return 2;
    if (m[0] > l[0] && l[0] > s[0]) return 3;
    if (l[0] > m[0] && m[0] > s[0]) return 4;
    if (l[0] > s[0] && s[0] > m[0]) return 5;
    if (s[0] > l[0] && l[0] > m[0]) return 6;
    
    return 0;
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
//| ラインに対するシグナルを検出する
//+------------------------------------------------------------------+
void CheckLineSignals(Line &line)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;

    int stateIndex = GetLineState(line.name);
    if((g_lineStates[stateIndex].isBrokeUp || g_lineStates[stateIndex].isBrokeDown) && !InpAllowSignalAfterBreak) return;

    datetime prevBarTime = rates[1].time;
    double offset = InpSignalOffsetPips * g_pip;
    double prev_open = rates[1].open;
    double prev_high = rates[1].high;
    double prev_low = rates[1].low;
    double prev_close = rates[1].close;

    if(InpEntryMode == TOUCH_MODE || InpEntryMode == HYBRID_MODE)
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
                if (InpEntryMode != HYBRID_MODE) g_lineStates[stateIndex].isBrokeUp = true;
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
                if (InpEntryMode != HYBRID_MODE) g_lineStates[stateIndex].isBrokeDown = true;
            }
        }
    }
    
    if(InpEntryMode == ZONE_MODE || InpEntryMode == HYBRID_MODE)
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
//| ストキャスティクスの確定シグナルをチェックする
//+------------------------------------------------------------------+
void CheckStochasticSignal()
{
    double k_buffer[], d_buffer[];
    ArraySetAsSeries(k_buffer, true);
    ArraySetAsSeries(d_buffer, true);

    if(CopyBuffer(h_stoch, 0, 1, 2, k_buffer) < 2 || CopyBuffer(h_stoch, 1, 1, 2, d_buffer) < 2) return;
    
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 1, 1, rates) < 1) return;
    
    datetime bar_time = rates[0].time;
    double offset = InpSignalOffsetPips * g_pip;

    if(d_buffer[1] < InpStoch_Lower_Level && d_buffer[0] >= InpStoch_Lower_Level && k_buffer[0] > d_buffer[0])
    {
        CreateSignalObject(InpArrowPrefix + "Stoch_Buy_" + TimeToString(bar_time), bar_time, rates[0].low - offset, clrDeepSkyBlue, 233, "");
    }

    if(d_buffer[1] > InpStoch_Upper_Level && d_buffer[0] <= InpStoch_Upper_Level && k_buffer[0] < d_buffer[0])
    {
        CreateSignalObject(InpArrowPrefix + "Stoch_Sell_" + TimeToString(bar_time), bar_time, rates[0].high + offset, clrHotPink, 234, "");
    }
}

//+------------------------------------------------------------------+
//| ゾーン内でのMACDクロスエントリーをチェックする
//+------------------------------------------------------------------+
void CheckZoneMacdCross()
{
    if (!InpEnableZoneMacdCross || (InpEntryMode != ZONE_MODE && InpEntryMode != HYBRID_MODE)) return;
    static datetime lastZoneCrossEntryTime = 0;
    if (TimeCurrent() < lastZoneCrossEntryTime + PeriodSeconds()) return;

    double exec_main[3], exec_signal[3];
    ArraySetAsSeries(exec_main, true); ArraySetAsSeries(exec_signal, true);
    if (CopyBuffer(h_macd_exec, 0, 0, 3, exec_main) < 3 || CopyBuffer(h_macd_exec, 1, 0, 3, exec_signal) < 3) return;

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
            if (g_env_state.currentBuyScore >= InpEntryScore)
            {
                PlaceOrder(true, tick.ask, g_env_state.currentBuyScore);
                lastZoneCrossEntryTime = TimeCurrent();
                return;
            }
        }
        if (isSellCross && line.type == LINE_TYPE_RESISTANCE && tick.bid > lower_zone && tick.bid < upper_zone)
        {
            if (g_env_state.currentSellScore >= InpEntryScore)
            {
                PlaceOrder(false, tick.bid, g_env_state.currentSellScore);
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
    ArrayFree(group.positionTickets);
    ArrayFree(group.splitPrices);
    ArrayFree(group.splitLineNames);
    ArrayFree(group.splitLineTimes);
}

//+------------------------------------------------------------------+
//| ポジショングループの状態を更新する
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
                if(g_managedPositions[j].ticket == ticket)
                {
                    score = g_managedPositions[j].score;
                    break;
                }
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
            buyGroup.stampedFinalTP = oldBuyGroup.stampedFinalTP;
            buyGroup.openTime = oldBuyGroup.openTime;
        }
        if(InpEnableAtrSL && oldBuyGroup.positionCount != buyGroup.positionCount) UpdateGroupSL(buyGroup);
        UpdateGroupSplitLines(buyGroup);
    }
    else if(oldBuyGroup.isActive)
    {
        DeleteGroupSplitLines(buyGroup);
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
            sellGroup.stampedFinalTP = oldSellGroup.stampedFinalTP;
            sellGroup.openTime = oldSellGroup.openTime;
        }
        if(InpEnableAtrSL && oldSellGroup.positionCount != sellGroup.positionCount) UpdateGroupSL(sellGroup);
        UpdateGroupSplitLines(sellGroup);
    }
    else if(oldSellGroup.isActive)
    {
        DeleteGroupSplitLines(sellGroup);
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

    if (!OrderSend(request, result))
    {
        PrintFormat("ポジション #%d のSL変更に失敗しました。エラー: %d", ticket, GetLastError());
    }
}

//+------------------------------------------------------------------+
//| グループ全体のストップロスを更新する
//+------------------------------------------------------------------+
void UpdateGroupSL(PositionGroup &group)
{
    if (!group.isActive) return;
    
    double sl_price = 0;
    if(InpSlMode == SL_MODE_OPPOSITE_TP) { sl_price = group.isBuy ? zonalFinalTPLine_Sell : zonalFinalTPLine_Buy; }
    else if(InpSlMode == SL_MODE_MANUAL) { sl_price = group.isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell; }
    else if(InpSlMode == SL_MODE_ATR)
    {
        double atr_buffer[1];
        if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
        {
            sl_price = group.isBuy ? group.averageEntryPrice - (atr_buffer[0] * InpAtrSlMultiplier) : group.averageEntryPrice + (atr_buffer[0] * InpAtrSlMultiplier);
        }
    }
    
    if(sl_price <= 0) return;
    for (int i = 0; i < group.positionCount; i++)
    {
        ModifyPositionSL(group.positionTickets[i], sl_price);
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
double CalculateRiskBasedLotSize(int score)
{
    double sl_distance_price = 0;
    double atr_buffer[1];
    if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
    {
        sl_distance_price = atr_buffer[0] * InpAtrSlMultiplier;
    }
    if (sl_distance_price <= 0) return 0.0;

    double risk_percent_to_use = InpRiskPercent;
    if (InpEnableHighScoreRisk && score >= InpHighScoreThreshold)
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
//| 情報パネルの管理
//+------------------------------------------------------------------+
void ManageInfoPanel()
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

    int line = 0;
    string sep = "──────────────────";
    
    // --- パネル描画 ---
    DrawPanelLine(line++, "▶ ApexFlowEA v6.1", "", clrWhite, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, sep, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);

    // ▼▼▼ ここから修正 ▼▼▼
    color state_color;
    string state_text = MasterStateToString(g_env_state.master_state, state_color);
    DrawPanelLine(line++, "状態: " + state_text, "●", clrWhite, state_color, corner, anchor, InpPanelFontSize, is_lower_corner);
    
    // 伝統的ステージ番号を追加
    string stage_num_text = "  └ 伝統的ステージ: " + (string)g_env_state.primary_stage;
    DrawPanelLine(line++, stage_num_text, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    // ▲▲▲ ここまで修正 ▲▲▲

    DrawPanelLine(line++, sep, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    
    DrawPanelLine(line++, "■ 傾斜ダイナミクス", "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, "  ├ 長期MA: " + SlopeStateToString(g_env_state.slope_long), "", clrWhite, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, "  ├ 中期MA: " + SlopeStateToString(g_env_state.slope_middle), "", clrWhite, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, "  └ 短期MA: " + SlopeStateToString(g_env_state.slope_short), "", clrWhite, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, sep, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    
    DrawPanelLine(line++, "■ スコアリング", "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, "  ├ 現在スコア (Buy) : " + (string)g_env_state.currentBuyScore, "", clrLime, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, "  └ 現在スコア (Sell): " + (string)g_env_state.currentSellScore, "", clrTomato, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    DrawPanelLine(line++, sep, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    
    string buy_pos_text = "BUY : ---";
    if(buyGroup.isActive) buy_pos_text = StringFormat("BUY (%d): %.2f Lot", buyGroup.positionCount, buyGroup.totalLotSize);
    DrawPanelLine(line++, buy_pos_text, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
    
    string sell_pos_text = "SELL: ---";
    if(sellGroup.isActive) sell_pos_text = StringFormat("SELL(%d): %.2f Lot", sellGroup.positionCount, sellGroup.totalLotSize);
    DrawPanelLine(line++, sell_pos_text, "", clrGainsboro, clrNONE, corner, anchor, InpPanelFontSize, is_lower_corner);
}

//+------------------------------------------------------------------+
//| パネルの1行を描画するヘルパー関数
//+------------------------------------------------------------------+
void DrawPanelLine(int line_index, string text, string icon, color text_color, color icon_color, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor, int font_size, bool is_lower)
{
    string panel_prefix = g_panelPrefix;
    int x_pos = p_panel_x_offset;
    int y_pos_start = p_panel_y_offset;
    int y_step = (int)round(font_size * 1.5);
    int icon_text_gap = 210; 
    string font = "Arial";
    int y_pos;

    if(is_lower) {
        int total_lines = 14; 
        y_pos = y_pos_start + ((total_lines - 1 - line_index) * y_step);
    } else {
        y_pos = y_pos_start + (line_index * y_step);
    }

    string text_obj_name = panel_prefix + "Text_" + (string)line_index;
    string icon_obj_name = panel_prefix + "Icon_" + (string)line_index;
    
    if(ObjectFind(0, text_obj_name) < 0)
    {
        ObjectCreate(0, text_obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, text_obj_name, OBJPROP_CORNER, corner);
        ObjectSetString(0, text_obj_name, OBJPROP_FONT, font);
    }
    if(ObjectFind(0, icon_obj_name) < 0)
    {
        ObjectCreate(0, icon_obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, icon_obj_name, OBJPROP_CORNER, corner);
    }

    ObjectSetInteger(0, text_obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, text_obj_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, text_obj_name, OBJPROP_YDISTANCE, y_pos);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_YDISTANCE, y_pos);
    ObjectSetString(0, text_obj_name, OBJPROP_TEXT, text);
    ObjectSetString(0, icon_obj_name, OBJPROP_TEXT, icon);
    ObjectSetInteger(0, text_obj_name, OBJPROP_COLOR, text_color);
    ObjectSetInteger(0, icon_obj_name, OBJPROP_COLOR, icon_color);

    if(anchor == ANCHOR_RIGHT)
    {
        ObjectSetInteger(0, icon_obj_name, OBJPROP_XDISTANCE, x_pos);
        ObjectSetInteger(0, text_obj_name, OBJPROP_XDISTANCE, x_pos + 20);
    }
    else
    {
        ObjectSetInteger(0, text_obj_name, OBJPROP_XDISTANCE, x_pos);
        ObjectSetInteger(0, icon_obj_name, OBJPROP_XDISTANCE, x_pos + icon_text_gap);
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
//| 汎用的なボタンを作成する
//+------------------------------------------------------------------+
bool CreateApexButton(string name, int x, int y, int width, int height, string text, color clr)
{
    ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
    return true;
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
//| 手動で描画したラインをすべて削除する
//+------------------------------------------------------------------+
void ClearManualLines()
{
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, "ManualSupport_") == 0 || StringFind(name, "ManualResistance_") == 0)
        {
            ObjectDelete(0, name);
        }
    }
    UpdateLines();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| EAが作成した全てのチャートオブジェクトを削除する
//+------------------------------------------------------------------+
void DeleteAllEaObjects()
{
    ObjectsDeleteAll(0, g_panelPrefix);
    ObjectsDeleteAll(0, "ApexFlow_TimerLabel");
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);
    ObjectsDeleteAll(0, InpDotPrefix);
    ObjectsDeleteAll(0, InpArrowPrefix);
    ObjectsDeleteAll(0, InpDivSignalPrefix);
    ObjectsDeleteAll(0, "ManualSupport_");
    ObjectsDeleteAll(0, "ManualResistance_");
    ObjectsDeleteAll(0, "TPLine_");
    ObjectsDeleteAll(0, "SLLine_");
    ObjectsDeleteAll(0, "SplitLine_");
    ObjectsDeleteAll(0, "ZoneRect_");
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
    bool reached = (group.isBuy && price >= nextSplitPrice - buffer) || (!group.isBuy && price <= nextSplitPrice + buffer);

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
//| 内部のライン「データ」を更新する
//+------------------------------------------------------------------+
void UpdateLines()
{
    ArrayFree(allLines);
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
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, OBJ_TREND);
        bool isManualSupport = StringFind(objName, "ManualSupport_") == 0;
        bool isManualResistance = StringFind(objName, "ManualResistance_") == 0;
        if (!isManualSupport && !isManualResistance) continue;
        
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

            if (InpEntryMode != HYBRID_MODE)
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
//| クリックした位置に手動ラインを描画する
//+------------------------------------------------------------------+
void DrawManualTrendLine(double price, datetime time)
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;

    bool isSupport = (price < tick.ask);
    
    color line_color = isSupport ? p_ManualSupport_Color : p_ManualResist_Color;
    string role_text = isSupport ? "Support" : "Resistance";
    string name = isSupport ? "ManualSupport_" : "ManualResistance_";
    name += TimeToString(TimeCurrent(), TIME_SECONDS) + "_" + IntegerToString(rand());

    if(ObjectCreate(0, name, OBJ_TREND, 0, time, price, time + PeriodSeconds(_Period), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
        ObjectSetString(0, name, OBJPROP_TEXT, role_text);
        ObjectSetInteger(0, name, OBJPROP_STYLE, p_ManualLine_Style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, p_ManualLine_Width);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
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
            g_slLinePrice_Buy = tick.ask - (atr_buffer[0] * InpAtrSlMultiplier);
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
            g_slLinePrice_Sell = tick.bid + (atr_buffer[0] * InpAtrSlMultiplier);
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
//| ゾーンを長方形オブジェクトで可視化する
//+------------------------------------------------------------------+
void ManageZoneVisuals()
{
    ObjectsDeleteAll(0, "ZoneRect_");
    if (!g_isZoneVisualizationEnabled || (InpEntryMode != ZONE_MODE && InpEntryMode != HYBRID_MODE)) return;

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
            datetime endTime = line.breakTime > 0 ? line.breakTime : TimeCurrent() + 3600 * 24 * 30;
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
    ManageInfoPanel();
    
    // 5. チャートを強制的に再描画して、すべての変更を即時反映
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| シグナルオブジェクトをチャートに描画する
//+------------------------------------------------------------------+
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string msg)
{
    string uname = name + "_" + TimeToString(dt, TIME_MINUTES|TIME_SECONDS);
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
            if(StringLen(msg) > 0) Print(msg);
        }
    }
}