//+------------------------------------------------------------------+
//|                                               Git ApexFlowEA.mq5 |
//|                                      (ZoneEntry + ZephyrSplit)   |
//|                                    Final Corrected Version: 4.0  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "4.0"

// --- ラインカラー定数
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

// ==================================================================
// --- ENUM / 構造体定義 ---
// ==================================================================
// サポート/レジスタンスの種別を定義
enum ENUM_LINE_TYPE
{
    LINE_TYPE_SUPPORT,
    LINE_TYPE_RESISTANCE
};

// ライン情報を一元管理するための構造体 (ブレイク時刻追加版)
struct Line
{
    string      name;
    double      price;
    ENUM_LINE_TYPE type;
    color       signalColor;
    datetime    startTime;
    datetime    breakTime; // ★★★追加: ブレイクした正確な時刻を記憶するメンバ★★★
    bool        isBrokeUp;
    bool        isBrokeDown;
    bool        waitForRetest;
    bool        isInZone;
};

// 保有ポジションの情報を管理するための構造体
struct PositionInfo
{
    long ticket; // ポジションのチケット番号
    int  score;  // エントリー時のスコア
};

// スコアリングの各要素の検知状況と点数を保持する構造体 (修正版)
struct ScoreComponentInfo
{
    bool divergence;
    bool exec_angle;
    bool mid_angle;
    bool exec_hist;
    bool mid_hist_sync;
    bool mid_zeroline;
    bool long_zeroline;
    
    // ★★★ 各項目のスコアを保持する変数を追加 ★★★
    int score_divergence;
    int score_exec_angle;
    int score_mid_angle;
    int score_exec_hist;
    int score_mid_hist_sync;
    int score_mid_zeroline;
    int score_long_zeroline;
    
    int  total_score;
};

// 分割決済の順序ロジック
enum ENUM_EXIT_LOGIC
{
    EXIT_FIFO,        // 先入れ先出し
    EXIT_UNFAVORABLE, // 不利なポジションから決済
    EXIT_FAVORABLE    // 有利なポジションから決済
};

// TPラインの計算モード
enum ENUM_TP_MODE
{
    MODE_ZIGZAG,
    MODE_PIVOT
};

// ポジションの管理モード
enum ENUM_POSITION_MODE
{
    MODE_AGGREGATE, // 集約モード
    MODE_INDIVIDUAL // 個別モード
};

// 個別ポジションモードでの分割決済データを管理
struct SplitData
{
    ulong    ticket;
    double   entryPrice;
    double   lotSize;
    double   splitPrices[];
    string   splitLineNames[];
    datetime splitLineTimes[];
    int      splitsDone;
    bool     isBuy;
    datetime openTime;
    double   stampedFinalTP;
    int      score;
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

// ラインのブレイク状態を永続化するための構造体 (★★★ ゾーンモード改修版 ★★★)
struct LineState
{
    string   name;              // ライン名 ("S1", "Manual_123...")
    bool     isBrokeUp;
    bool     isBrokeDown;
    bool     waitForRetestUp;   // ★追加: 上抜け後、サポートとしてのリテストを待つ状態
    bool     waitForRetestDown; // ★追加: 下抜け後、レジスタンスとしてのリテストを待つ状態
    datetime breakTime;         // ★追加: ブレイクが発生した時刻（有効期限管理用）
};

// ==================================================================
// --- 入力パラメータ (日本語表記・コメントを完全維持) ---
// ==================================================================
input group "=== エントリーロジック設定 ===";
input bool         InpUsePivotLines        = true;        // ピボットラインを使用する
input ENUM_TIMEFRAMES InpPivotPeriod          = PERIOD_H1;   // ピボット時間足
enum ENTRY_MODE
{
    TOUCH_MODE,  // タッチモード：ラインへの単純な接触や反発を検知
    ZONE_MODE,   // ゾーンモード：フォールスブレイクやリテストを検知
    HYBRID_MODE  // タッチモードとゾーンモードの両方のロジックを有効化
};
input ENTRY_MODE InpEntryMode              = HYBRID_MODE; // エントリーモード
input bool       InpEnableZoneMacdCross    = true;        // (ゾーンモード限定) ゾーン内MACDクロスエントリーを有効にする
input bool       InpVisualizeZones         = true;        // (ゾーン/ハイブリッド) ゾーンを可視化する ★★★追加★★★
input bool       InpBreakMode              = true;        // ブレイクモード (タッチモード用)
input bool       InpAllowSignalAfterBreak  = true;        // ブレイク後の再シグナルを許可する
input double     InpZonePips               = 50.0;        // ゾーン幅 (pips)

input group "=== 取引設定 ===";
input double         InpLotSize              = 0.1;      // ロットサイズ
input int            InpMaxPositions         = 5;        // 同方向の最大ポジション数
input bool           InpEnableRiskBasedLot = true;   // リスクベースの自動ロット計算を有効にする
input double         InpRiskPercent        = 1.0;    // 1トレードあたりのリスク許容率 (% of balance)
input bool      InpEnableHighScoreRisk  = true;   // 高スコア時にリスクを変更する
input double    InpHighScoreRiskPercent = 2.0;    // 高スコア時のリスク許容率 (%)
input bool     InpEnableEntrySpacing = true;             // ポジション間隔フィルターを有効にする
input double   InpEntrySpacingPips   = 10.0;             // 最低限確保するポジション間隔 (pips)
input int            InpMagicNumber          = 123456;   // マジックナンバー
input int            InpDotTimeout           = 600;      // ドット/矢印有効期限 (秒)

enum ENUM_SL_MODE { SL_MODE_ATR, SL_MODE_MANUAL, SL_MODE_OPPOSITE_TP };
input group "=== ストップロス設定 ===";
input ENUM_SL_MODE InpSlMode = SL_MODE_OPPOSITE_TP; // ★新しいモードを追加し、デフォルトに設定
input bool         InpEnableAtrSL     = true;
input double       InpAtrSlMultiplier = 2.5;
input ENUM_TIMEFRAMES InpAtrSlTimeframe = PERIOD_H1;
input bool         InpEnableTrailingSL      = true;
input double       InpTrailingAtrMultiplier = 2.0;

input group "=== 動的決済ロジック ===";
input bool    InpEnableTimeExit        = true;  // タイム・エグジット（時間経過による決済）を有効にする
input int     InpExitAfterBars         = 48;    // 何本経過したら決済判断を行うか (M5で48本 = 4時間)
input double  InpExitMinProfit         = 1.0;   // この利益額(口座通貨)に達していない場合、時間で決済される
input bool    InpEnableCounterSignalExit = true;  // カウンターシグナル（反対サイン）による決済を有効にする
input int     InpCounterSignalScore    = 7;     // 決済のトリガーとなる反対シグナルの最低スコア

input group "=== 決済ロジック設定 (Zephyr) ===";
input ENUM_POSITION_MODE InpPositionMode           = MODE_AGGREGATE; // ポジション管理モード
input ENUM_EXIT_LOGIC    InpExitLogic              = EXIT_UNFAVORABLE; // 分割決済のロジック
input int                InpSplitCount             = 3;              // ★★★変更: 分割決済の回数 (デフォルトを3に)
input double             InpFinalTpRR_Ratio        = 2.5;            // (ATRモード用) 最終TPのRR比
input double             InpExitBufferPips         = 1.0;            // 決済バッファ (Pips)
input int                InpBreakEvenAfterSplits   = 1;              // N回分割決済後にBE設定 (0=無効, デフォルト1に変更)
input bool               InpEnableProfitBE         = true;           // 利益確保型BEを有効にする
input double             InpProfitBE_Pips          = 2.0;            // 利益確保BEの幅 (pips)
input double             InpHighSchoreTpRratio     = 1.5;            // 高スコア時のTP倍率
input ENUM_TP_MODE       InpTPLineMode             = MODE_ZIGZAG;    // TPラインのモード
input ENUM_TIMEFRAMES    InpTP_Timeframe           = PERIOD_H4;      // TP計算用の時間足 (ZigZagとPivotで共用)
input int                InpZigzagDepth            = 12;             // ZigZag: Depth
input int                InpZigzagDeviation        = 5;              // ZigZag: Deviation
input int                InpZigzagBackstep         = 3;              // ZigZag: Backstep
input bool               InpEnablePartialCloseEven = true;           // [新機能] パーシャルクローズイーブンを有効にする
input double             InpPartialCloseEvenProfit = 1.0;            // [新機能] 決済を実行する合計利益額 (0以上)

input group "=== トレンド強度フィルター (ADX) ===";
input bool          InpEnableAdxFilter = true;        // ADXフィルターを有効にする
input ENUM_TIMEFRAMES InpAdxTimeframe    = PERIOD_H1;   // ADXの時間足
input int           InpAdxPeriod       = 14;          // ADXの期間
input int           InpAdxThreshold    = 23;          // エントリーを許可するADXの最低値

input group "--- 動的フィルター設定 ---";
input bool           InpEnableVolatilityFilter = true;  // ボラティリティフィルターを有効にするか
input double         InpAtrMaxRatio          = 1.5;      // エントリーを許可する最大ATR倍率
input bool           InpEnableTimeFilter     = true;     // 取引時間フィルターを有効にするか
input int            InpTradingHourStart     = 15;       // 取引開始時間 (サーバー時間)
input int            InpTradingHourEnd       = 25;       // 取引終了時間 (サーバー時間, 25 = 翌午前1時)

input group "--- ダイバージェンスの可視化設定 ---";
input bool           InpShowDivergenceSignals = true;         // ダイバージェンスサインを表示するか
input string         InpDivSignalPrefix      = "DivSignal_";  // サインのオブジェクト名プレフィックス
input color          InpBullishDivColor      = clrDeepSkyBlue; // 強気ダイバージェンスの色
input color          InpBearishDivColor      = clrHotPink;     // 弱気ダイバージェンスの色
input int            InpDivSymbolCode        = 159;           // サインのシンボルコード (159 = ●)
input int            InpDivSymbolSize        = 8;             // サインの大きさ
input double         InpDivSymbolOffsetPips  = 15.0;          // サインの描画オフセット (Pips)

input group "=== 高度スコアリング設定 ===";
input int    InpScore_Standard        = 6;        // 標準エントリーの最低スコア
input int    InpScore_High            = 8;        // 高スコアエントリーの最低スコア
input bool   InpEnableWeightedScoring = true;      // (2) 各スコアの「重み付け」を有効にする
input double InpWeightDivergence      = 1.5;      // ダイバージェンスの重み
input double InpWeightLongTrend       = 2.0;      // 長期トレンドの重み
input double InpWeightMidTrend        = 1.2;      // 中期トレンドの重み
input double InpWeightExecAngle       = 0.8;      // 執行足の角度の重み
input double InpWeightMidAngle        = 1.0;      // 中期足の角度の重み
input double InpWeightExecHist        = 0.8;      // 執行足のヒストグラムの重み
input double InpWeightMidHist         = 1.0;      // 中期足のヒストグラムの重み
input bool   InpEnableComboBonuses    = true;      // (3) 「コンボボーナス」を有効にする
input int    InpBonusTrendAlignment   = 2;        // 長期＋中期トレンド一致時のボーナス点
input int    InpBonusTrendDivergence  = 3;        // 長期トレンド＋ダイバージェンス一致時のボーナス点
input bool   InpEnableSoftVeto        = true;      // (4) 「ソフトVeto（減点）」を有効にする
input int    InpPenaltyCounterTrend   = -5;       // 長期トレンド逆行時の減点数 (必ずマイナス値を入力)

input group "--- 執行足MACD (トリガー) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Exec         = PERIOD_CURRENT; // 時間足 (PERIOD_CURRENT=チャートの時間足)
input int             InpMACD_Fast_Exec       = 12;             // Fast EMA
input int             InpMACD_Slow_Exec       = 26;             // Slow EMA
input int             InpMACD_Signal_Exec     = 9;              // Signal SMA

input group "--- 中期足MACD (コンテキスト) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Mid          = PERIOD_H1;      // 時間足
input int             InpMACD_Fast_Mid        = 12;             // Fast EMA
input int             InpMACD_Slow_Mid        = 26;             // Slow EMA
input int             InpMACD_Signal_Mid      = 9;              // Signal SMA

input group "--- 長期足MACD (コンファメーション) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Long         = PERIOD_H4;      // 時間足
input int             InpMACD_Fast_Long       = 12;             // Fast EMA
input int             InpMACD_Slow_Long       = 26;             // Slow EMA
input int             InpMACD_Signal_Long     = 9;              // Signal SMA

input group "=== ピボットライン設定 ===";
input int             InpPivotHistoryCount    = 1;          // 表示する過去ピボットの数 (0=現在のみ)
input bool            InpShowS2R2             = true;         // S2/R2ラインを表示
input bool            InpShowS3R3             = true;         // S3/R3ラインを表示

input group "=== 手動ライン設定 ===";
input color           p_ManualSupport_Color   = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color    = clrTomato;     // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style      = STYLE_DOT;     // 手動ラインのスタイル
input int             p_ManualLine_Width      = 2;             // 手動ラインの太さ

input group "=== UI設定 ===";
enum ENUM_PANEL_CORNER
{
    PC_LEFT_UPPER,   // 左上
    PC_RIGHT_UPPER,  // 右上
    PC_LEFT_LOWER,   // 左下
    PC_RIGHT_LOWER   // 右下
};
input ENUM_PANEL_CORNER InpPanelCorner = PC_LEFT_UPPER; // パネルの表示コーナー
input bool           InpShowInfoPanel        = true;     // 情報パネルを表示する
input int            p_panel_x_offset        = 10;       // パネルX位置
input int            p_panel_y_offset        = 130;      // パネルY位置
input int            InpPanelFontSize        = 8;        // パネルのフォントサイズ
input bool           InpEnableButtons        = true;     // ボタン表示を有効にする

input group "=== オブジェクトとシグナルの外観 ===";
input string InpLinePrefix_Pivot     = "Pivot_";      // ピボットラインプレフィックス
input string InpDotPrefix            = "Dot_";        // ドットプレフィックス
input string InpArrowPrefix          = "Trigger_";    // 矢印プレフィックス
input int    InpSignalWidth          = 2;             // シグナルの太さ
input int    InpSignalFontSize       = 10;            // シグナルの大きさ
input double InpSignalOffsetPips     = 2.0;           // シグナルの描画オフセット (Pips)
input int    InpTouchBreakUpCode     = 221;           // タッチブレイク買いのシンボルコード
input int    InpTouchBreakDownCode   = 222;           // タッチブレイク売りのシンボルコード
input int    InpTouchReboundUpCode   = 233;           // タッチひげ反発買いのシンボルコード
input int    InpTouchReboundDownCode = 234;           // タッチひげ反発売りのシンボルコード
input int    InpFalseBreakBuyCode    = 117;           // フォールスブレイク (買い) のシンボルコード (例: ◆)
input int    InpFalseBreakSellCode   = 117;           // フォールスブレイク (売り) のシンボルコード (例: ◆)
input int    InpRetestBuyCode          = 110;           // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode         = 111;           // ブレイク＆リテスト (売り) のシンボルコード
input int    InpRetestExpiryBars       = 10;            // ブレイク後のリテスト有効期限 (バーの本数)

// ==================================================================
// --- グローバル変数 ---
// ==================================================================
LineState   g_lineStates[];   // 全てのラインの永続的な状態を管理
double       g_pip;
Line         allLines[];
PositionInfo g_managedPositions[];
int          h_macd_exec, h_macd_mid, h_macd_long, h_atr;
int         h_atr_sl;
int         h_adx;            // ★★★ ADXインジケータハンドルを追加 ★★★
datetime    g_lastBarTime = 0; // ★★★ lastBar[2] を廃止し、この変数に変更
datetime     lastArrowTime = 0;
bool         g_isDrawingMode = false;
string       g_buttonName           = "DrawManualLineButton";
string       g_clearButtonName      = "ClearSignalsButton";
string       g_clearLinesButtonName = "ClearLinesButton";
string       g_panelPrefix          = "InfoPanel_";
double       s1, r1, s2, r2, s3, r3, pivot;
PositionGroup buyGroup;
PositionGroup sellGroup;
SplitData    splitPositions[];
int          zigzagHandle;
double       zonalFinalTPLine_Buy, zonalFinalTPLine_Sell;
bool         isBuyTPManuallyMoved = false, isSellTPManuallyMoved = false;
datetime     lastTradeTime;
bool         g_ignoreNextChartClick = false;
datetime    g_lastPivotDrawTime = 0; // ピボットを最後に描画した時間足を記憶
ENUM_TP_MODE      prev_tp_mode      = WRONG_VALUE; // TPモードの前回値を記憶
ENUM_TIMEFRAMES   prev_tp_timeframe = WRONG_VALUE; // TP時間足の前回値を記憶
double      g_slLinePrice_Buy = 0;             // 買いポジション用の手動SLライン価格
double      g_slLinePrice_Sell = 0;            // 売りポジション用の手動SLライン価格
bool        isBuySLManuallyMoved = false;      // 買いSLラインが手動で動かされたか
bool        isSellSLManuallyMoved = false;     // 売りSLラインが手動で動かされたか
bool        g_isZoneVisualizationEnabled; // ★★★追加: ゾーン可視化の状態管理用★★★


// ==================================================================
// --- 関数のプロトタイプ宣言 ---
// ==================================================================
void InitGroup(PositionGroup &group, bool isBuy);
void UpdateLines();
void DrawPivotLine();
void SyncManagedPositions();
void UpdateZones();
void ManagePositionGroups();
void CheckExitForGroup(PositionGroup &group);
void DetectNewEntrances();
void CheckExits();
void ManageInfoPanel();
void ManageManualLines();
void CheckEntry();
void UpdateButtonState();
void ClearSignalObjects();
void ClearManualLines();
void DrawManualTrendLine(double price, datetime time);
void CloseAllPositionsInGroup(PositionGroup &group);
void ClosePosition(ulong ticket);
void SetBreakEvenForGroup(PositionGroup &group);
bool SetBreakEven(ulong ticket, double entryPrice);
void UpdateGroupSplitLines(PositionGroup &group);
bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose);
bool CreateApexButton(string name, int x, int y, int width, int height, string text, color clr);
void CreateManualLineButton();
void CreateClearButton();
void CreateClearLinesButton();
void CalculatePivot();
void CheckLineSignals(Line &line);
bool IsNewBar(ENUM_TIMEFRAMES timeframe);
void PlaceOrder(bool isBuy, double price, int score);
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string msg);
void DrawDivergenceSignal(datetime time, double price, color clr);
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal);
bool CheckMACDDivergence(bool is_buy_signal, int macd_handle);
void AddPanelLine(string &lines[], const string text);
void AddSplitData(ulong ticket);
bool ExecuteSplitExit(ulong ticket, double lot, SplitData &split, int splitIndex);
int GetLineState(string lineName); // ★★★ LineState& から int に修正 ★★★
void DeleteGroupSplitLines(PositionGroup &group);
void CheckPartialCloseEven();

// ==================================================================
// --- 主要関数 ---
// ==================================================================

//+------------------------------------------------------------------+
//| 全てのラインをチェックしてシグナルを生成する専門関数 (新設)      |
//+------------------------------------------------------------------+
void ProcessLineSignals()
{
    // allLines配列に格納された全てのラインをループ処理
    for (int i = 0; i < ArraySize(allLines); i++)
    {
        // 各ラインに対してシグナルチェックを実行
        CheckLineSignals(allLines[i]);
    }
}

//+------------------------------------------------------------------+
//| エキスパートティック関数 (シグナル生成プロセスを復活させた最終版) |
//+------------------------------------------------------------------+
void OnTick()
{
    // ==================================================================
    // === セクション1: 新規バーでのみ実行する処理                       ===
    // ==================================================================
    if(IsNewBar())
    {
        // --- 1. 状態の検知とデータ準備 ---
        ManageManualLines(); // 手動ラインのブレイク状態を更新

        datetime currentPivotBarTime = iTime(_Symbol, InpPivotPeriod, 0);
        if(g_lastPivotDrawTime == 0 || g_lastPivotDrawTime < currentPivotBarTime)
        {
            ManagePivotLines();
            g_lastPivotDrawTime = currentPivotBarTime;
        }
        UpdateLines(); // 全てのライン情報をallLines配列に集約

        // --- 2. シグナルの生成 ---
        // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        // ★★★ ここで新設した関数を呼び出し、シグナルを生成します ★★★
        ProcessLineSignals();
        // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

        // --- 3. エントリー判断 ---
        // 生成されたシグナルを元にエントリーを試みる
        CheckZoneMacdCross();
        CheckEntry();

        // --- 4. データと描画の同期 ---
        // 取引後の最新の状態でデータと描画を更新
        SyncManagedPositions();
        if (InpPositionMode == MODE_AGGREGATE) { ManagePositionGroups(); }
        else { DetectNewEntrances(); }
        
        UpdateZones();
        ManageSlLines();
        ManageZoneVisuals();
        ManageInfoPanel();
    }

    // ==================================================================
    // === セクション2: 毎ティック実行する処理 (決済ロジック)           ===
    // ==================================================================
    CheckPartialCloseEven();
    CheckDynamicExits();
    if (InpPositionMode == MODE_AGGREGATE)
    {
        CheckExitForGroup(buyGroup);
        CheckExitForGroup(sellGroup);
        ManageTrailingSL(buyGroup);
        ManageTrailingSL(sellGroup);
    }
    else { CheckExits(); }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 全ての視覚的要素（ライン、パネル等）を更新する統合関数           |
//+------------------------------------------------------------------+
void UpdateAllVisuals()
{
    // 1. サポート・レジスタンスライン（ピボット等）を更新・再描画
    UpdateLines();
    
    // 2. TPラインを更新・再描画
    UpdateZones();
    
    // 3. ポジショングループを管理し、分割決済ラインを更新・再描画
    if (InpPositionMode == MODE_AGGREGATE)
    {
        ManagePositionGroups();
    }
    else
    {
        // 個別モードのロジックもここに集約可能だが、現状のOnTickに依存
    }

    // 4. 情報パネルを更新・再描画
    ManageInfoPanel();
    
    // 5. チャートを強制的に再描画して、すべての変更を即時反映
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 【最終統合版】すべての修正を統合したピボット管理関数             |
//+------------------------------------------------------------------+
void ManagePivotLines()
{
    // まず、既存のピボットラインをすべて削除
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);

    // パラメータで無効なら、ここで処理を終了
    if (!InpUsePivotLines) return;

    long periodSeconds = PeriodSeconds(InpPivotPeriod);

    // 統一されたループ（i=0が現在, i>0が過去）
    for(int i = InpPivotHistoryCount; i >= 0; i--)
    {
        MqlRates rates[];
        if(CopyRates(_Symbol, InpPivotPeriod, i + 1, 1, rates) < 1) continue;

        double h = rates[0].high;
        double l = rates[0].low;
        double c = rates[0].close;
        
        // ローカル変数名を変更し、グローバル変数との衝突を回避
        double p_val = (h + l + c) / 3.0;
        double s1_val = 2.0 * p_val - h;
        double r1_val = 2.0 * p_val - l;
        double s2_val = p_val - (h - l);
        double r2_val = p_val + (h - l);
        double s3_val = l - 2.0 * (h - p_val);
        double r3_val = h + 2.0 * (p_val - l);
        
        // i=0（現在）の場合のみ、計算結果をグローバル変数に反映させる
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
            datetime endTime;

            // ★★★ 警告が出ないように修正 ★★★
            if(rayRight) {
                // 現在ラインの場合：1期間分の短い線分を定義し、そこから右に延長
                endTime = startTime + (datetime)periodSeconds;
            } else {
                // 過去ラインの場合：期間の終わりで描画を止める
                endTime = startTime + (datetime)periodSeconds - 1;
            }

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
//| EAが作成した全てのチャートオブジェクトを削除するヘルパー関数     |
//+------------------------------------------------------------------+
void DeleteAllEaObjects()
{
    // オブジェクト名やプレフィックスに基づいて一括削除
    ObjectsDeleteAll(0, g_panelPrefix);          // 情報パネル
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);    // ピボットライン
    ObjectsDeleteAll(0, InpDotPrefix);           // ドットシグナル
    ObjectsDeleteAll(0, InpArrowPrefix);         // 矢印シグナル
    ObjectsDeleteAll(0, InpDivSignalPrefix);     // ダイバージェンスシグナル
    ObjectsDeleteAll(0, "ManualTrend_");         // 手動ライン
    ObjectsDeleteAll(0, "TPLine_");              // TPライン
    ObjectsDeleteAll(0, "SplitLine_");           // 分割決済ライン

    // ボタン類
    ObjectsDeleteAll(0, g_buttonName);
    ObjectsDeleteAll(0, g_clearButtonName);
    ObjectsDeleteAll(0, g_clearLinesButtonName);
    ObjectsDeleteAll(0, BUTTON_BUY_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_SELL_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_ALL_CLOSE);
    ObjectsDeleteAll(0, BUTTON_RESET_BUY_TP);
    ObjectsDeleteAll(0, BUTTON_RESET_SELL_TP);

    ChartRedraw(); // 念のためチャートを再描画
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数 (クリーン・スレート版)                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // EAが作成した全てのオブジェクトをクリーンアップする
    DeleteAllEaObjects();

    // インジケータハンドルを解放
    IndicatorRelease(h_macd_exec);
    IndicatorRelease(h_macd_mid);
    IndicatorRelease(h_macd_long);
    IndicatorRelease(h_atr);
    IndicatorRelease(zigzagHandle);

    PrintFormat("ApexFlowEA 終了: 理由=%d。全オブジェクトをクリーンアップしました。", reason);
}

//+------------------------------------------------------------------+
//| エキスパート初期化関数 (最終修正版)                             |
//+------------------------------------------------------------------+
int OnInit()
{
    g_pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pow(10, _Digits % 2);
    g_lastBarTime = 0;
    lastTradeTime = 0;
    g_lastPivotDrawTime = 0; 

    h_macd_exec = iMACD(_Symbol, InpMACD_TF_Exec, InpMACD_Fast_Exec, InpMACD_Slow_Exec, InpMACD_Signal_Exec, PRICE_CLOSE);
    h_macd_mid = iMACD(_Symbol, InpMACD_TF_Mid, InpMACD_Fast_Mid, InpMACD_Slow_Mid, InpMACD_Signal_Mid, PRICE_CLOSE);
    h_macd_long = iMACD(_Symbol, InpMACD_TF_Long, InpMACD_Fast_Long, InpMACD_Slow_Long, InpMACD_Signal_Long, PRICE_CLOSE);
    h_atr = iATR(_Symbol, InpMACD_TF_Exec, 14);
    h_atr_sl = iATR(_Symbol, InpAtrSlTimeframe, 14);
    zigzagHandle = iCustom(_Symbol, InpTP_Timeframe, "ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);
    h_adx = iADX(_Symbol, InpAdxTimeframe, InpAdxPeriod);
    
    if(h_macd_exec == INVALID_HANDLE || h_macd_mid == INVALID_HANDLE || h_macd_long == INVALID_HANDLE || zigzagHandle == INVALID_HANDLE || h_atr_sl == INVALID_HANDLE || h_adx == INVALID_HANDLE)
    {
        Print("インジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }
    
    if (InpPositionMode == MODE_AGGREGATE) { InitGroup(buyGroup, true); InitGroup(sellGroup, false); }
    else { ArrayResize(splitPositions, 0); }
    isBuyTPManuallyMoved = false;
    isSellTPManuallyMoved = false;
    
    g_isZoneVisualizationEnabled = InpVisualizeZones;

    if(InpEnableButtons)
    {
        CreateManualLineButton(); CreateClearButton(); CreateClearLinesButton();
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

    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);
    
    prev_tp_mode = InpTPLineMode;
    prev_tp_timeframe = InpTP_Timeframe;
    
    UpdateLines();
    
    Print("ApexFlowEA v4.0 初期化完了 (最終修正版)");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数 (全てのロジックを含む最終修正版)          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // --- (1) オブジェクトのクリックイベント ---
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == g_buttonName)
        {
            g_isDrawingMode = !g_isDrawingMode;
            if(g_isDrawingMode) { g_ignoreNextChartClick = true; }
            UpdateButtonState();
            return;
        }
        if(sparam == g_clearButtonName) { ClearSignalObjects(); return; }
        if(sparam == g_clearLinesButtonName) { ClearManualLines(); return; }
        if(sparam == BUTTON_BUY_CLOSE_ALL)  { CloseAllPositionsInGroup(buyGroup); return; }
        if(sparam == BUTTON_SELL_CLOSE_ALL) { CloseAllPositionsInGroup(sellGroup); return; }
        if(sparam == BUTTON_ALL_CLOSE) { CloseAllPositionsInGroup(buyGroup); CloseAllPositionsInGroup(sellGroup); return; }
        
        if(sparam == BUTTON_RESET_BUY_TP)
        {
            isBuyTPManuallyMoved = false;
            // リセット時に線のスタイルを点線に戻す
            if(ObjectFind(0, "TPLine_Buy") >= 0) ObjectSetInteger(0, "TPLine_Buy", OBJPROP_STYLE, STYLE_DOT);
            UpdateAllVisuals();
            return;
        }
        if(sparam == BUTTON_RESET_SELL_TP)
        {
            isSellTPManuallyMoved = false;
            // リセット時に線のスタイルを点線に戻す
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
        if(sparam == "TPLine_Buy")
        {
            isBuyTPManuallyMoved = true;
            // ドラッグ開始と同時に実線にして、手動操作の事実を刻印
            ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
        }
        if(sparam == "TPLine_Sell")
        {
            isSellTPManuallyMoved = true;
            // ドラッグ開始と同時に実線にして、手動操作の事実を刻印
            ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
        }
        if(sparam == "SLLine_Buy")  isBuySLManuallyMoved = true;
        if(sparam == "SLLine_Sell") isSellSLManuallyMoved = true;
        return;
    }

    // --- (4) オブジェクトの編集終了イベント ---
    if(id == CHARTEVENT_OBJECT_ENDEDIT)
    {
        if(StringFind(sparam, "TPLine_") == 0)
        {
            double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0);
            if(sparam == "TPLine_Buy")
            {
                zonalFinalTPLine_Buy = newPrice;
                if(buyGroup.isActive) { buyGroup.stampedFinalTP = newPrice; UpdateGroupSplitLines(buyGroup); }
            }
            else if(sparam == "TPLine_Sell")
            {
                zonalFinalTPLine_Sell = newPrice;
                if(sellGroup.isActive) { sellGroup.stampedFinalTP = newPrice; UpdateGroupSplitLines(sellGroup); }
            }
            ChartRedraw();
        }
        if(StringFind(sparam, "SLLine_") == 0)
        {
            double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0);
            if(sparam == "SLLine_Buy")
            {
                g_slLinePrice_Buy = newPrice;
                if(buyGroup.isActive) { UpdateGroupSL(buyGroup); UpdateGroupSplitLines(buyGroup); }
            }
            if(sparam == "SLLine_Sell")
            {
                g_slLinePrice_Sell = newPrice;
                if(sellGroup.isActive) { UpdateGroupSL(sellGroup); UpdateGroupSplitLines(sellGroup); }
            }
            ChartRedraw();
        }
        return;
    }
}

// ==================================================================
// --- ヘルパー関数群 ---
// ==================================================================

//+------------------------------------------------------------------+
//| ポジショングループを初期化する                                   |
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
//| ポジショングループの状態を更新する (動的分割数削除版)          |
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
            
            if(buyEarliestTime == 0 || posOpenTime < buyEarliestTime)
            {
               buyEarliestTime = posOpenTime;
            }
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
            
            if(sellEarliestTime == 0 || posOpenTime < sellEarliestTime)
            {
               sellEarliestTime = posOpenTime;
            }
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
      if(!oldBuyGroup.isActive) // 新規グループ結成
      {
         buyGroup.initialTotalLotSize = buyGroup.totalLotSize;
         buyGroup.splitsDone = 0;
         buyGroup.lockedInSplitCount = InpSplitCount; // ★★★ 修正点: スコアによる増減ロジックを削除
         // ★★★ ここから最終TPの計算ロジックを変更 ★★★
         if(!isBuyTPManuallyMoved)
         {
            // グループ内のポジションからSLを取得してSL値幅を計算
            double sl_price = 0;
            if(buyGroup.positionCount > 0 && PositionSelectByTicket(buyGroup.positionTickets[0]))
            {
               sl_price = PositionGetDouble(POSITION_SL);
            }
            
            if(sl_price > 0)
            {
               double sl_distance = MathAbs(buyGroup.averageEntryPrice - sl_price);
               double final_tp = buyGroup.averageEntryPrice + (sl_distance * InpFinalTpRR_Ratio);
               // 高スコア倍率を適用
               if (buyGroup.highestScore >= InpScore_High)
               {
                  final_tp = buyGroup.averageEntryPrice + (sl_distance * InpFinalTpRR_Ratio * InpHighSchoreTpRratio);
               }
               buyGroup.stampedFinalTP = final_tp;
            } else {
               // SL未設定の場合は従来のロジックにフォールバック
               UpdateZones();
               buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
            }
         }
         // ★★★ ここまで ★★★
         buyGroup.openTime = buyEarliestTime;
      }
      else // 既存グループへの追加
      {
         buyGroup.initialTotalLotSize = oldBuyGroup.initialTotalLotSize;
         buyGroup.splitsDone = oldBuyGroup.splitsDone;
         buyGroup.lockedInSplitCount = oldBuyGroup.lockedInSplitCount;
         buyGroup.stampedFinalTP = oldBuyGroup.stampedFinalTP;
         buyGroup.openTime = oldBuyGroup.openTime;
      }

      if(InpEnableAtrSL && oldBuyGroup.positionCount != buyGroup.positionCount)
      {
         UpdateGroupSL(buyGroup);
      }
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
         sellGroup.lockedInSplitCount = InpSplitCount; // ★★★ 修正点: スコアによる増減ロジックを削除
         // ★★★ ここから最終TPの計算ロジックを変更 ★★★
         if(!isSellTPManuallyMoved)
         {
            double sl_price = 0;
            if(sellGroup.positionCount > 0 && PositionSelectByTicket(sellGroup.positionTickets[0]))
            {
               sl_price = PositionGetDouble(POSITION_SL);
            }
            
            if(sl_price > 0)
            {
               double sl_distance = MathAbs(sellGroup.averageEntryPrice - sl_price);
               double final_tp = sellGroup.averageEntryPrice - (sl_distance * InpFinalTpRR_Ratio);
               if (sellGroup.highestScore >= InpScore_High)
               {
                    final_tp = sellGroup.averageEntryPrice - (sl_distance * InpFinalTpRR_Ratio * InpHighSchoreTpRratio);
               }
               sellGroup.stampedFinalTP = final_tp;
            } else {
               UpdateZones();
               sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
            }
         }
         // ★★★ ここまで ★★★
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
      
      if(InpEnableAtrSL && oldSellGroup.positionCount != sellGroup.positionCount)
      {
         UpdateGroupSL(sellGroup);
      }
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
//| ゾーンを更新する (オブジェクトスタイルで状態管理する最終版)        |
//+------------------------------------------------------------------+
void UpdateZones()
{
    // --- BUY TP LOGIC ---
    string buy_tp_line_name = "TPLine_Buy";
    bool is_buy_line_manually_moved = false;

    // Step 1: オブジェクトの「線のスタイル」を直接確認し、手動かどうかを判断
    if(ObjectFind(0, buy_tp_line_name) >= 0)
    {
        if(ObjectGetInteger(0, buy_tp_line_name, OBJPROP_STYLE) == STYLE_SOLID)
        {
            is_buy_line_manually_moved = true; // 実線なら手動と判断
        }
    }

    // Step 2: 手動（実線）でない場合「のみ」自動計算を実行
    if (!is_buy_line_manually_moved)
    {
        double new_buy_tp = 0;
        switch(InpTPLineMode)
        {
            case MODE_ZIGZAG:
            {
                double zigzag[]; ArraySetAsSeries(zigzag, true);
                if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) > 0){ double levelHigh = 0; for(int i = 0; i < 100; i++){ if(zigzag[i] > 0){ if(zigzag[i] > levelHigh) levelHigh = zigzag[i]; } } new_buy_tp = levelHigh; }
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
                    for(int i=0; i<ArraySize(resistances); i++){ if(resistances[i] > buy_ref_price){ if(closest_r == 0 || resistances[i] < closest_r){ closest_r = resistances[i]; }}}
                    new_buy_tp = closest_r;
                }
                break;
            }
        }
        if (new_buy_tp > 0)
        {
            double final_buy_tp = new_buy_tp;
            if (buyGroup.isActive && buyGroup.highestScore >= InpScore_High)
            { 
                double originalDiff = final_buy_tp - buyGroup.averageEntryPrice; 
                if (originalDiff > 0) final_buy_tp = buyGroup.averageEntryPrice + (originalDiff * InpHighSchoreTpRratio); 
            }
            zonalFinalTPLine_Buy = final_buy_tp;
        }
    }
    else
    {
        // 手動（実線）の場合、オブジェクトの現在価格を正としてグローバル変数に反映
        zonalFinalTPLine_Buy = ObjectGetDouble(0, buy_tp_line_name, OBJPROP_PRICE, 0);
    }

    // Step 3: 最終的な価格でラインを描画
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

    // --- SELL TP LOGIC (同様に修正) ---
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
                double zigzag[]; ArraySetAsSeries(zigzag, true);
                if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) > 0){ double levelLow = DBL_MAX; for(int i = 0; i < 100; i++){ if(zigzag[i] > 0){ if(zigzag[i] < levelLow) levelLow = zigzag[i]; } } new_sell_tp = (levelLow < DBL_MAX) ? levelLow : 0; }
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
                    for(int i=0; i<ArraySize(supports); i++){ if(supports[i] < sell_ref_price && supports[i] > 0){ if(closest_s == 0 || supports[i] > closest_s){ closest_s = supports[i]; }}}
                    new_sell_tp = closest_s;
                }
                break;
            }
        }
        if(new_sell_tp > 0)
        {
            double final_sell_tp = new_sell_tp;
            if (sellGroup.isActive && sellGroup.highestScore >= InpScore_High) 
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
//| 分割決済ラインを更新する (手動SLモード対応・RR1:1ロジック版)   |
//+------------------------------------------------------------------+
void UpdateGroupSplitLines(PositionGroup &group)
{
    DeleteGroupSplitLines(group);

    if(!group.isActive || group.lockedInSplitCount <= 0) return;

    // --- TP/SLの価格を取得 ---
    double finalTpPrice = group.stampedFinalTP;
    if(finalTpPrice <= 0 || finalTpPrice == DBL_MAX) return;

    ArrayResize(group.splitPrices, group.lockedInSplitCount);
    ArrayResize(group.splitLineNames, group.lockedInSplitCount);
    ArrayResize(group.splitLineTimes, group.lockedInSplitCount);

    // ★★★★★ ここから計算ロジックを全面的に改修 ★★★★★

    if(InpSlMode == SL_MODE_MANUAL)
    {
        // --- 手動SLモード：RR1:1基準で計算 ---
        double slPrice = group.isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell;

        // SLが未設定、またはエントリー価格に対してSLが有利な側にある場合は計算不可
        if(slPrice <= 0 || (group.isBuy && slPrice >= group.averageEntryPrice) || (!group.isBuy && slPrice <= group.averageEntryPrice))
        {
             return; // 不正なSL価格では描画しない
        }

        double riskDistance = MathAbs(group.averageEntryPrice - slPrice);
        if(riskDistance <= 0) return;

        // 1. TP1 (RR 1:1) を設定
        double tp1Price = group.averageEntryPrice + (group.isBuy ? riskDistance : -riskDistance);
        group.splitPrices[0] = tp1Price;

        // 2. TP2以降を設定
        int remainingSplits = group.lockedInSplitCount - 1;
        if(remainingSplits > 0)
        {
            // TP1が最終TPを超えてしまった場合は、すべてのTPを最終TPに設定する
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
        // --- ATRモード：従来通りの均等分割 ---
        double step = MathAbs(finalTpPrice - group.averageEntryPrice) / group.lockedInSplitCount;
        for(int i = 0; i < group.lockedInSplitCount; i++)
        {
            group.splitPrices[i] = group.averageEntryPrice + (group.isBuy ? 1 : -1) * step * (i + 1);
        }
    }

    // ★★★★★ 計算ロジックの改修ここまで ★★★★★


    // --- ラインの描画処理 ---
    color pendingColor = group.isBuy ? clrGoldenrod : clrPurple;
    color settledColor = group.isBuy ? clrLimeGreen : clrHotPink;

    for(int i = 0; i < group.lockedInSplitCount; i++)
    {
        group.splitLineNames[i] = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_" + (string)i;
        
        if(i < group.splitsDone)
        {
            // 決済済みラインの描画 (既存ロジック)
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
            // 未決済ラインの描画 (既存ロジック)
            ObjectCreate(0, group.splitLineNames[i], OBJ_HLINE, 0, 0, group.splitPrices[i]);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_COLOR, pendingColor);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_ZORDER, 5);
            ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_SELECTABLE, false);
        }
    }
}

//+------------------------------------------------------------------+
//| 分割決済ラインをすべて削除する                                   |
//+------------------------------------------------------------------+
void DeleteGroupSplitLines(PositionGroup &group)
{
    string prefix = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_";
    ObjectsDeleteAll(0, prefix);
}

//+------------------------------------------------------------------+
//| グループの決済条件をチェックする (ロジック整理版)                |
//+------------------------------------------------------------------+
void CheckExitForGroup(PositionGroup &group)
{
    if (!group.isActive) return;

    int effectiveSplitCount = group.lockedInSplitCount;
    if (group.splitsDone >= effectiveSplitCount || effectiveSplitCount <= 0) return;

    if (group.splitsDone >= ArraySize(group.splitPrices))
    {
        PrintFormat("Error: splitsDone (%d) is out of range for splitPrices array (size: %d). Halting exit check for this tick.", group.splitsDone, ArraySize(group.splitPrices));
        return;
    }

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
        if (lotToClose > 0 && lotToClose < minLot)
        {
            lotToClose = minLot;
        }

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
//| 個別モード：分割決済を実行する (ライン描画停止・色変更版)        |
//+------------------------------------------------------------------+
bool ExecuteSplitExit(ulong ticket, double lot, SplitData &split, int splitIndex)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    if(!PositionSelectByTicket(ticket)) return false;
    ZeroMemory(request);
    ZeroMemory(result);
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = lot;
    request.type = split.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = split.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.type_filling = ORDER_FILLING_IOC;
    request.sl = 0.0;
    request.tp = 0.0;
    if(!OrderSend(request, result))
    {
        PrintFormat("ExecuteSplitExit 失敗: %d", GetLastError());
        return false;
    }
    
    // --- ★★★ ここから下を修正 ★★★ ---
    split.splitLineTimes[splitIndex] = TimeCurrent();
    string lineName = split.splitLineNames[splitIndex];

    // 既存のHLINEオブジェクトのプロパティを変更する方式に統一
    if(ObjectFind(0, lineName) >= 0)
    {
        // 終点を現在の足に設定して、それ以上描画されないようにする
        ObjectSetInteger(0, lineName, OBJPROP_TIME, 1, TimeCurrent());
        ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
        
        // 色をハイライト（スタイルは点線のまま）
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, split.isBuy ? clrGold : clrMediumPurple);
    }
    // --- ★★★ ここまでを修正 ★★★ ---

    return true;
}

//+------------------------------------------------------------------+
//| 新規エントリーを探す (ADXフィルター追加版)                       |
//+------------------------------------------------------------------+
void CheckEntry()
{
    MqlRates rates[]; ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;
    datetime currentTime = rates[0].time;
    string buy_trigger_reason = "", sell_trigger_reason = "";

    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_ARROW);
        if(StringFind(name, InpArrowPrefix) != 0 && StringFind(name, InpDotPrefix) != 0) continue;
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
        if(currentTime - objTime > InpDotTimeout) continue;

        if(buy_trigger_reason == "" && (StringFind(name, "_Buy") > 0 || StringFind(name, "_Buy_") > 0))
        {
            if(StringFind(name, "TouchBreak") > 0) buy_trigger_reason = "Touch Break Buy";
            else if(StringFind(name, "TouchRebound") > 0) buy_trigger_reason = "Touch Rebound Buy";
            else if(StringFind(name, "FalseBreak") > 0) buy_trigger_reason = "False Break Buy";
            else if(StringFind(name, "Retest") > 0) buy_trigger_reason = "Retest Buy";
            else buy_trigger_reason = "Signal Buy";
        }
        if(sell_trigger_reason == "" && (StringFind(name, "_Sell") > 0 || StringFind(name, "_Sell_") > 0))
        {
            if(StringFind(name, "TouchBreak") > 0) sell_trigger_reason = "Touch Break Sell";
            else if(StringFind(name, "TouchRebound") > 0) sell_trigger_reason = "Touch Rebound Sell";
            else if(StringFind(name, "FalseBreak") > 0) sell_trigger_reason = "False Break Sell";
            else if(StringFind(name, "Retest") > 0) sell_trigger_reason = "Retest Sell";
            else sell_trigger_reason = "Signal Sell";
        }
    }

    if((buy_trigger_reason != "" || sell_trigger_reason != "") && (TimeCurrent() > lastTradeTime + 5))
    {
        if(InpEnableTimeFilter)
        {
            MqlDateTime time; TimeCurrent(time); int h = time.hour; bool outside = false;
            if(InpTradingHourStart > InpTradingHourEnd){ if(h < InpTradingHourStart && h >= InpTradingHourEnd) outside = true; }
            else { if(h < InpTradingHourStart || h >= InpTradingHourEnd) outside = true; }
            if(outside) { Print("エントリースキップ (時間フィルター)"); return; }
        }
        if(InpEnableVolatilityFilter)
        {
            double atr_buffer[100];
            if(CopyBuffer(h_atr, 0, 0, 100, atr_buffer) == 100)
            {
                double avg_atr = 0; for(int j = 0; j < 100; j++) avg_atr += atr_buffer[j];
                double avg_atr_100 = avg_atr / 100;
                if(atr_buffer[0] > avg_atr_100 * InpAtrMaxRatio) { PrintFormat("エントリースキップ (ボラティリティフィルター)"); return; }
            }
        }
        if(InpEnableAdxFilter)
        {
            double adx_buffer[2];
            if(CopyBuffer(h_adx, 0, 0, 2, adx_buffer) < 2) { Print("ADXフィルターエラー"); return; }
            if(adx_buffer[1] < InpAdxThreshold) { PrintFormat("エントリースキップ (ADXフィルター)"); return; }
        }

        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick)) return;

        if(buy_trigger_reason != "")
        {
            string reason = "";
            if(buyGroup.positionCount >= InpMaxPositions) { reason = "最大ポジション数(" + (string)buyGroup.positionCount + ")に到達"; }
            else if(InpEnableEntrySpacing && buyGroup.isActive)
            {
                datetime lastOpenTime = 0; double lastOpenPrice = 0;
                for(int j = 0; j < buyGroup.positionCount; j++) { if(PositionSelectByTicket(buyGroup.positionTickets[j])) { datetime openTime = (datetime)PositionGetInteger(POSITION_TIME); if(openTime > lastOpenTime) { lastOpenTime = openTime; lastOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN); } } }
                if(lastOpenPrice > 0 && (tick.ask - lastOpenPrice) <= InpEntrySpacingPips * g_pip) { reason = "間隔フィルター(" + DoubleToString((tick.ask - lastOpenPrice)/g_pip, 1) + "pips差)"; }
            }
            if(reason != "") { Print("エントリースキップ (BUY): " + reason); }
            else { ScoreComponentInfo info = CalculateMACDScore(true); if(info.total_score >= InpScore_Standard) PlaceOrder(true, tick.ask, info.total_score, buy_trigger_reason); else PrintFormat("エントリースキップ (BUY/スコア): スコア(%d)が基準値(%d)に未達です。", info.total_score, InpScore_Standard); }
        }
        
        if(sell_trigger_reason != "")
        {
            string reason = "";
            if(sellGroup.positionCount >= InpMaxPositions) { reason = "最大ポジション数(" + (string)sellGroup.positionCount + ")に到達"; }
            else if(InpEnableEntrySpacing && sellGroup.isActive)
            {
                datetime lastOpenTime = 0; double lastOpenPrice = 0;
                for(int j = 0; j < sellGroup.positionCount; j++) { if(PositionSelectByTicket(sellGroup.positionTickets[j])) { datetime openTime = (datetime)PositionGetInteger(POSITION_TIME); if(openTime > lastOpenTime) { lastOpenTime = openTime; lastOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN); } } }
                if(lastOpenPrice > 0 && (lastOpenPrice - tick.bid) <= InpEntrySpacingPips * g_pip) { reason = "間隔フィルター(" + DoubleToString((lastOpenPrice - tick.bid)/g_pip, 1) + "pips差)"; }
            }
            if(reason != "") { Print("エントリースキップ (SELL): " + reason); }
            else { ScoreComponentInfo info = CalculateMACDScore(false); if(info.total_score >= InpScore_Standard) PlaceOrder(false, tick.bid, info.total_score, sell_trigger_reason); else PrintFormat("エントリースキップ (SELL/スコア): スコア(%d)が基準値(%d)に未達です。", info.total_score, InpScore_Standard); }
        }
    }
}

//+------------------------------------------------------------------+
//| 注文を発注する (手動SLモード対応版)                            |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, int score, string triggerReason)
{
    double lot_size;
    if(InpEnableRiskBasedLot) { lot_size = CalculateRiskBasedLotSize(score); }
    else { lot_size = InpLotSize; }
    if (lot_size <= 0) { PrintFormat("ロットサイズの計算結果が0以下のため、エントリーを中止しました。"); return; }

    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    ZeroMemory(res);
    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = lot_size;
    req.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price = NormalizeDouble(price, _Digits);
    req.sl = 0;
    req.tp = 0;
    req.magic = InpMagicNumber;
    req.comment = triggerReason + " (Score " + (string)score + ")";
    req.type_filling = ORDER_FILLING_IOC;

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
                        double atr_val = atr_buffer[0];
                        sl_price = isBuy ? price - (atr_val * InpAtrSlMultiplier) : price + (atr_val * InpAtrSlMultiplier);
                    }
                }
                if(sl_price > 0) ModifyPositionSL(ticket, sl_price);
                
                if (InpPositionMode == MODE_AGGREGATE) { ManagePositionGroups(); }
                else { DetectNewEntrances(); }
                ChartRedraw();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ラインに対するシグナルを検出する (ゾーンブレイクの状態記録を追加)   |
//+------------------------------------------------------------------+
void CheckLineSignals(Line &line)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;

    int stateIndex = GetLineState(line.name);
    if((g_lineStates[stateIndex].isBrokeUp || g_lineStates[stateIndex].isBrokeDown) && !InpAllowSignalAfterBreak)
    {
        return;
    }

    datetime prevBarTime = rates[1].time;
    double offset = InpSignalOffsetPips * g_pip;
    double prev_open = rates[1].open;
    double prev_high = rates[1].high;
    double prev_low = rates[1].low;
    double prev_close = rates[1].close;

    // ==========================================================
    // === タッチモード・ロジック ===============================
    // ==========================================================
    if(InpEntryMode == TOUCH_MODE || InpEntryMode == HYBRID_MODE)
    {
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(prev_open <= line.price && prev_high >= line.price && prev_close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Sell_" + line.name, prevBarTime, line.price + offset, line.signalColor, InpTouchReboundDownCode, line.name + " タッチ反発(売り)");
            }
            if(InpBreakMode && !g_lineStates[stateIndex].isBrokeUp && prev_open < line.price && prev_close >= line.price)
            {
                CreateSignalObject(InpArrowPrefix + "TouchBreak_Buy_" + line.name, prevBarTime, prev_low - offset, line.signalColor, InpTouchBreakUpCode, line.name + " タッチブレイク(買い)");
                if (InpEntryMode != HYBRID_MODE)
                {
                   g_lineStates[stateIndex].isBrokeUp = true;
                }
            }
        }
        else // LINE_TYPE_SUPPORT
        {
            if(prev_open >= line.price && prev_low <= line.price && prev_close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Buy_" + line.name, prevBarTime, line.price - offset, line.signalColor, InpTouchReboundUpCode, line.name + " タッチ反発(買い)");
            }
            if(InpBreakMode && !g_lineStates[stateIndex].isBrokeDown && prev_open > line.price && prev_close <= line.price)
            {
                CreateSignalObject(InpArrowPrefix + "TouchBreak_Sell_" + line.name, prevBarTime, prev_high + offset, line.signalColor, InpTouchBreakDownCode, line.name + " タッチブレイク(売り)");
                if (InpEntryMode != HYBRID_MODE)
                {
                    g_lineStates[stateIndex].isBrokeDown = true;
                }
            }
        }
    }
    
    // ==========================================================
    // === ゾーンモード・ロジック ===============================
    // ==========================================================
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
            // 1. フォールスブレイク検知 (売りシグナル) → ゾーンの役割終了
            if (prev_high > line.price + zone_width && prev_close < line.price)
            {
                CreateSignalObject(InpDotPrefix + "FalseBreak_Sell_" + line.name, prevBarTime, prev_high + offset, clrHotPink, InpFalseBreakSellCode, line.name + " フォールスブレイク(売り)");
                // ★★★ ゾーンの役割が完了したので、ブレイク時刻を記録してゾーンを停止させる ★★★
                g_lineStates[stateIndex].breakTime = prevBarTime;
            }
            // 2. ブレイク＆リテスト検知 (買いシグナル) → ゾーンの役割終了
            else if (g_lineStates[stateIndex].waitForRetestUp)
            {
                if (prev_low <= line.price && prev_close > line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Buy_" + line.name, prevBarTime, prev_low - offset, clrDeepSkyBlue, InpRetestBuyCode, line.name + " ブレイク＆リテスト(買い)");
                    g_lineStates[stateIndex].waitForRetestUp = false;
                    // ★★★ ゾーンの役割が完了したので、ブレイク時刻を記録してゾーンを停止させる ★★★
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
            // 3. 新規ブレイクの検知 (状態設定)
            else if (!g_lineStates[stateIndex].isBrokeUp)
            {
                if (prev_open < line.price && prev_close > line.price)
                {
                    g_lineStates[stateIndex].isBrokeUp = true;
                    g_lineStates[stateIndex].waitForRetestUp = true; 
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                    PrintFormat("%s が上にブレイクしました。リテスト待ちを開始します。", line.name);
                }
            }
        }
        else // サポートラインの場合 (LINE_TYPE_SUPPORT)
        {
            // 1. フォールスブレイク検知 (買いシグナル) → ゾーンの役割終了
            if (prev_low < line.price - zone_width && prev_close > line.price)
            {
                CreateSignalObject(InpDotPrefix + "FalseBreak_Buy_" + line.name, prevBarTime, prev_low - offset, clrDeepSkyBlue, InpFalseBreakBuyCode, line.name + " フォールスブレイク(買い)");
                // ★★★ ゾーンの役割が完了したので、ブレイク時刻を記録してゾーンを停止させる ★★★
                g_lineStates[stateIndex].breakTime = prevBarTime;
            }
            // 2. ブレイク＆リテスト検知 (売りシグナル) → ゾーンの役割終了
            else if (g_lineStates[stateIndex].waitForRetestDown)
            {
                if (prev_high >= line.price && prev_close < line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Sell_" + line.name, prevBarTime, prev_high + offset, clrHotPink, InpRetestSellCode, line.name + " ブレイク＆リテスト(売り)");
                    g_lineStates[stateIndex].waitForRetestDown = false;
                    // ★★★ ゾーンの役割が完了したので、ブレイク時刻を記録してゾーンを停止させる ★★★
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                }
            }
            // 3. 新規ブレイクの検知 (状態設定)
            else if (!g_lineStates[stateIndex].isBrokeDown)
            {
                if (prev_open > line.price && prev_close < line.price)
                {
                    g_lineStates[stateIndex].isBrokeDown = true;
                    g_lineStates[stateIndex].waitForRetestDown = true;
                    g_lineStates[stateIndex].breakTime = prevBarTime;
                    PrintFormat("%s が下にブレイクしました。リテスト待ちを開始します。", line.name);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 内部のライン「データ」を更新する (ブレイク時刻対応・名前バグ修正版) |
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
//| ピボット値を計算する                                             |
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
//| 個別モード：新規ポジションを検出し、管理対象に追加する           |
//+------------------------------------------------------------------+
void DetectNewEntrances()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            bool exists = false;
            for(int j = 0; j < ArraySize(splitPositions); j++)
            {
                if(splitPositions[j].ticket == ticket)
                {
                    exists = true;
                    break;
                }
            }
            if(!exists) AddSplitData(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| 個別モード：ポジションの決済をチェックする                       |
//+------------------------------------------------------------------+
void CheckExits()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    for(int i = ArraySize(splitPositions) - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(splitPositions[i].ticket))
        {
            for(int j=0; j<ArraySize(splitPositions[i].splitLineNames); j++) ObjectDelete(0, splitPositions[i].splitLineNames[j]);
            ArrayRemove(splitPositions, i, 1);
            continue;
        }
        int effectiveSplitCount = ArraySize(splitPositions[i].splitPrices);
        if(splitPositions[i].splitsDone >= effectiveSplitCount || effectiveSplitCount <= 0) continue;
        double currentPrice = splitPositions[i].isBuy ? bid : ask;
        double nextSplitPrice = splitPositions[i].splitPrices[splitPositions[i].splitsDone];
        if (nextSplitPrice <= 0) continue;
        double priceBuffer = InpExitBufferPips * g_pip;
        bool splitPriceReached = (splitPositions[i].isBuy && currentPrice >= (nextSplitPrice - priceBuffer)) ||
                                 (!splitPositions[i].isBuy && currentPrice <= (nextSplitPrice + priceBuffer));
        if(splitPriceReached && splitPositions[i].splitLineTimes[splitPositions[i].splitsDone] == 0)
        {
            double lotToClose = 0.0;
            double remainingLot = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
            if (remainingLot < minLot) continue;
            if (splitPositions[i].splitsDone == effectiveSplitCount - 1)
            {
                lotToClose = remainingLot;
            }
            else
            {
                double baseLot = floor(splitPositions[i].lotSize / effectiveSplitCount / volStep) * volStep;
                double remainderLot = NormalizeDouble(splitPositions[i].lotSize - (baseLot * effectiveSplitCount), 2);
                int upgradeCount = (int)round(remainderLot / volStep);
                lotToClose = baseLot;
                if(splitPositions[i].splitsDone < upgradeCount)
                {
                    lotToClose += volStep;
                }
                if(lotToClose < minLot) lotToClose = minLot;
                if(lotToClose > remainingLot) lotToClose = remainingLot;
            }
            lotToClose = NormalizeDouble(lotToClose, 2);
            if(lotToClose > 0 && ExecuteSplitExit(splitPositions[i].ticket, lotToClose, splitPositions[i], splitPositions[i].splitsDone))
            {
                splitPositions[i].splitsDone++;
                if(InpBreakEvenAfterSplits > 0 && splitPositions[i].splitsDone >= InpBreakEvenAfterSplits)
                {
                    SetBreakEven(splitPositions[i].ticket, splitPositions[i].entryPrice);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 個別モード：新規ポジションの分割決済データを準備する (動的分割数削除版)
//+------------------------------------------------------------------+
void AddSplitData(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   SplitData newSplit;
   newSplit.ticket = ticket;
   newSplit.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   newSplit.lotSize = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
   newSplit.isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   newSplit.splitsDone = 0;
   newSplit.openTime = (datetime)PositionGetInteger(POSITION_TIME);
   newSplit.score = 0;
   for(int i = 0; i < ArraySize(g_managedPositions); i++)
   {
      if(g_managedPositions[i].ticket == ticket)
      {
         newSplit.score = g_managedPositions[i].score;
         break;
      }
   }
   newSplit.stampedFinalTP = newSplit.isBuy ? zonalFinalTPLine_Buy : zonalFinalTPLine_Sell;
   double tpPrice = newSplit.stampedFinalTP;
   if(tpPrice <= 0 || tpPrice == DBL_MAX) tpPrice = newSplit.entryPrice + (newSplit.isBuy ? 1000 : -1000) * g_pip;
   if(newSplit.score >= InpScore_High && tpPrice > 0)
   {
      double originalDiff = MathAbs(tpPrice - newSplit.entryPrice);
      tpPrice = newSplit.entryPrice + (newSplit.isBuy ? 1 : -1) * (originalDiff * InpHighSchoreTpRratio);
   }
   newSplit.stampedFinalTP = tpPrice;
   double priceDiff = MathAbs(tpPrice - newSplit.entryPrice);
   
   // ★★★ 修正点: スコアによる増減ロジックを削除し、固定値を使用 ★★★
   int splitCount = InpSplitCount;
   
   if(splitCount > 0)
   {
      ArrayResize(newSplit.splitPrices, splitCount);
      ArrayResize(newSplit.splitLineNames, splitCount);
      ArrayResize(newSplit.splitLineTimes, splitCount);
      double step = priceDiff / splitCount;
      for(int i = 0; i < splitCount; i++)
      {
         newSplit.splitPrices[i] = newSplit.isBuy ? newSplit.entryPrice + step * (i + 1) : newSplit.entryPrice - step * (i + 1);
         string lineName = "SplitLine_" + (string)ticket + "_" + (string)i;
         newSplit.splitLineNames[i] = lineName;
         newSplit.splitLineTimes[i] = 0;
         ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, newSplit.splitPrices[i]);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, newSplit.isBuy ? clrGoldenrod : clrPurple);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 5);
      }
   }
   int size = ArraySize(splitPositions);
   ArrayResize(splitPositions, size + 1);
   splitPositions[size] = newSplit;
}

//+------------------------------------------------------------------+
//| 汎用的なボタンを作成する                                         |
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
//| 手動ライン描画ボタンを作成する                                   |
//+------------------------------------------------------------------+
void CreateManualLineButton()
{
    CreateApexButton(g_buttonName, 10, 50, 120, 20, "手動ライン描画 OFF", C'220,220,220');
}
//+------------------------------------------------------------------+
//| シグナル消去ボタンを作成する                                     |
//+------------------------------------------------------------------+
void CreateClearButton()
{
    CreateApexButton(g_clearButtonName, 10, 75, 120, 20, "シグナル消去", C'255,228,225');
}
//+------------------------------------------------------------------+
//| 手動ライン消去ボタンを作成する                                   |
//+------------------------------------------------------------------+
void CreateClearLinesButton()
{
    CreateApexButton(g_clearLinesButtonName, 10, 100, 120, 20, "手動ライン消去", C'225,240,255');
}
//+------------------------------------------------------------------+
//| グループ内の全ポジションを決済する                               |
//+------------------------------------------------------------------+
void CloseAllPositionsInGroup(PositionGroup &group)
{
    for(int i = ArraySize(group.positionTickets) - 1; i >= 0; i--) ClosePosition(group.positionTickets[i]);
}

//+------------------------------------------------------------------+
//| 【最終修正版】指定されたチケットのポジションを決済する           |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    // 構造体をリセット
    ZeroMemory(request);
    ZeroMemory(result);

    // チケット番号でポジションを選択
    if(!PositionSelectByTicket(ticket))
    {
        PrintFormat("決済エラー: ポジション #%d が見つかりませんでした。", ticket);
        return;
    }

    // --- ★★★ ポジション自体から正確な情報を取得 ★★★ ---
    string           position_symbol = PositionGetString(POSITION_SYMBOL); // ポジションが持つ本来のシンボル名を取得
    double           position_volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE position_type   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    // --- ★★★ より安全で堅牢な決済リクエストを構築 ★★★ ---
    request.action       = TRADE_ACTION_DEAL;
    request.position     = ticket;                      // 決済対象のポジションチケット
    request.symbol       = position_symbol;             // ★修正: ポジション自身のシンボル名を使用
    request.volume       = position_volume;
    request.deviation    = 100;                         // ★追加: スリッページの許容範囲を100ポイントに設定
    request.type_filling = ORDER_FILLING_IOC;           // ★追加: 決済方法をIOCに明示的に指定
    request.magic        = InpMagicNumber;
    request.comment      = "ApexFlowEA Close";

    // 決済注文のタイプを決定 (保有ポジションと逆の注文)
    if(position_type == POSITION_TYPE_BUY)
    {
        request.type = ORDER_TYPE_SELL;
    }
    else
    {
        request.type = ORDER_TYPE_BUY;
    }

    // ★修正: 成行決済の場合、価格はサーバーに任せるため0を指定するのが最も安全
    request.price = 0;

    // 決済リクエストを送信
    if(!OrderSend(request, result))
    {
        // 失敗した場合、サーバーからのリターンコードも表示して原因を特定しやすくする
        PrintFormat("ポジション #%d の決済に失敗しました。エラーコード: %d, サーバー応答: %s",
                    ticket, result.retcode, result.comment);
    }
    else
    {
        PrintFormat("ポジション #%d の決済リクエストを正常に送信しました。サーバー応答: %s",
                    ticket, result.comment);
    }
}

//+------------------------------------------------------------------+
//| グループ全体のSLを平均建値に設定する（ブレークイーブン）           |
//+------------------------------------------------------------------+
void SetBreakEvenForGroup(PositionGroup &group)
{
    for(int i = 0; i < ArraySize(group.positionTickets); i++) SetBreakEven(group.positionTickets[i], group.averageEntryPrice);
}

//+------------------------------------------------------------------+
//| 指定されたポジションのSLを設定する (利益確保機能付き)            |
//+------------------------------------------------------------------+
bool SetBreakEven(ulong ticket, double entryPrice)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    if(PositionSelectByTicket(ticket))
    {
        // --- 新しいSL価格を計算 ---
        double newSL = entryPrice; // デフォルトは建値
        
        // 利益確保BEが有効な場合、指定pipsを加算/減算
        if(InpEnableProfitBE)
        {
            double profit_in_points = InpProfitBE_Pips * g_pip;
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            if(pos_type == POSITION_TYPE_BUY)
            {
                newSL = entryPrice + profit_in_points;
            }
            else // POSITION_TYPE_SELL
            {
                newSL = entryPrice - profit_in_points;
            }
        }
        // --- 計算ここまで ---

        // 既にSLが設定済みの場合は何もしない
        double currentSL = PositionGetDouble(POSITION_SL);
        if(MathAbs(currentSL - newSL) < g_pip)
        {
            return true;
        }

        req.action = TRADE_ACTION_SLTP;
        req.position = ticket;
        req.symbol = _Symbol;
        req.sl = NormalizeDouble(newSL, _Digits);
        req.tp = PositionGetDouble(POSITION_TP);
        
        // ストップレベルの内側に入ってしまう場合は、エラーを防ぐため設定をスキップ
        double stops_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_pip;
        double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(pos_type == POSITION_TYPE_BUY && req.sl >= current_bid - stops_level)
        {
            PrintFormat("BE設定スキップ(BUY): SL(%f)がストップレベル(%f)の内側です。", req.sl, current_bid - stops_level);
            return false;
        }
        if(pos_type == POSITION_TYPE_SELL && req.sl <= current_ask + stops_level)
        {
            PrintFormat("BE設定スキップ(SELL): SL(%f)がストップレベル(%f)の内側です。", req.sl, current_ask + stops_level);
            return false;
        }

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
//| 手動ラインの状態を監視し、ブレイクを検出する (ハイブリッドモード対応版) |
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
        
        bool is_broken = (StringFind(text, "Resistance") >= 0 && rates[1].close > price) ||
                         (StringFind(text, "Support") >= 0 && rates[1].close < price);
                         
        if(is_broken)
        {
            // 1. ラインの見た目を停止させる処理は、どのモードでも実行
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, rates[1].time);
            ObjectSetString(0, name, OBJPROP_TEXT, text + "-Broken");
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);

            // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
            // ★★★ ここが今回の修正ポイントです ★★★
            // ハイブリッドモード「以外」の場合のみ、状態を更新する
            if (InpEntryMode != HYBRID_MODE)
            {
                // 2. EAの記憶（状態管理）にブレイクした事実と時刻を記録する
                int stateIndex = GetLineState(name);
                if(stateIndex >= 0)
                {
                    g_lineStates[stateIndex].breakTime = rates[1].time;
                    if(StringFind(text, "Resistance") >= 0)
                    {
                        g_lineStates[stateIndex].isBrokeUp = true;
                    }
                    else
                    {
                        g_lineStates[stateIndex].isBrokeDown = true;
                    }
                }
            }
            // ★★★ 修正ここまで ★★★
        }
    }
}

//+------------------------------------------------------------------+
//| シグナルオブジェクトをチャートに描画する                         |
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

//+------------------------------------------------------------------+
//| ダイバージェンスシグナルをチャートに描画する                     |
//+------------------------------------------------------------------+
void DrawDivergenceSignal(datetime time, double price, color clr)
{
    if(!InpShowDivergenceSignals) return;
    string name = InpDivSignalPrefix + TimeToString(time, TIME_DATE|TIME_MINUTES);
    if(ObjectFind(0, name) >= 0) return;
    if(ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, InpDivSymbolCode);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpDivSymbolSize);
    }
}

//+------------------------------------------------------------------+
//| 描画されたエントリーシグナルをすべて削除する                     |
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
//| 手動で描画したラインをすべて削除する (S/R分離版)                 |
//+------------------------------------------------------------------+
void ClearManualLines()
{
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        // ★★★ 変更点: 新しいプレフィックスを両方チェック ★★★
        if(StringFind(name, "ManualSupport_") == 0 || StringFind(name, "ManualResistance_") == 0)
        {
            ObjectDelete(0, name);
        }
    }
    UpdateLines();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| クリックした位置に手動ラインを描画する (S/R自動判別版)           |
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
    else
    {
        int error_code = GetLastError();
        PrintFormat("ObjectCreate に失敗しました。オブジェクト名: %s, エラーコード: %d", name, error_code);
    }
}

//+------------------------------------------------------------------+
//| 手動ライン描画ボタンの状態を更新する                             |
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
//| 新しい足ができたかチェックする (チャート時間足 追従版)           |
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
//| 管理ポジションリストと実際のポジションを同期する                 |
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
//| 情報パネルの管理 (サイズ変更対応版)                              |
//+------------------------------------------------------------------+
void ManageInfoPanel()
{
    if(!InpShowInfoPanel)
    {
        ObjectsDeleteAll(0, g_panelPrefix);
        return;
    }
    string panel_lines[];
    AddPanelLine(panel_lines, "▶ ApexFlowEA");
    AddPanelLine(panel_lines, " Magic: " + (string)InpMagicNumber);
    AddPanelLine(panel_lines, " Spread: " + (string)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) + " points");
    AddPanelLine(panel_lines, "──────────────────────");
    ScoreComponentInfo buy_info  = CalculateMACDScore(true);
    ScoreComponentInfo sell_info = CalculateMACDScore(false);
    AddPanelLine(panel_lines, "--- Score Details ---");
    
    AddPanelLine(panel_lines, "             [ Buy / Sell ]");
    
    string div_buy_str  = buy_info.score_divergence > 0 ? (string)buy_info.score_divergence : "-";
    string div_sell_str = sell_info.score_divergence > 0 ? (string)sell_info.score_divergence : "-";
    AddPanelLine(panel_lines, "Divergence:  [ " + div_buy_str + " / " + div_sell_str + " ]");

    string zero_buy  = (buy_info.score_mid_zeroline > 0 ? (string)buy_info.score_mid_zeroline : "-") + "/" + 
                       (buy_info.score_long_zeroline > 0 ? (string)buy_info.score_long_zeroline : "-");
    string zero_sell = (sell_info.score_mid_zeroline > 0 ? (string)sell_info.score_mid_zeroline : "-") + "/" + 
                       (sell_info.score_long_zeroline > 0 ? (string)sell_info.score_long_zeroline : "-");
    AddPanelLine(panel_lines, "Zero(M/L):   [ " + zero_buy + " / " + zero_sell + " ]");

    string angle_buy = (buy_info.score_exec_angle > 0 ? (string)buy_info.score_exec_angle : "-") + "/" + 
                       (buy_info.score_mid_angle > 0 ? (string)buy_info.score_mid_angle : "-");
    string angle_sell= (sell_info.score_exec_angle > 0 ? (string)sell_info.score_exec_angle : "-") + "/" + 
                       (sell_info.score_mid_angle > 0 ? (string)sell_info.score_mid_angle : "-");
    AddPanelLine(panel_lines, "Angle(E/M):  [ " + angle_buy + " / " + angle_sell + " ]");

    string hist_buy = (buy_info.score_exec_hist > 0 ? (string)buy_info.score_exec_hist : "-") + "/" + 
                      (buy_info.score_mid_hist_sync > 0 ? (string)buy_info.score_mid_hist_sync : "-");
    string hist_sell= (sell_info.score_exec_hist > 0 ? (string)sell_info.score_exec_hist : "-") + "/" + 
                      (sell_info.score_mid_hist_sync > 0 ? (string)sell_info.score_mid_hist_sync : "-");
    AddPanelLine(panel_lines, "Hist(E/M):   [ " + hist_buy + " / " + hist_sell + " ]");
    
    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, "Forecast: Buy " + (string)buy_info.total_score + " / Sell " + (string)sell_info.total_score);
    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, "Buy Group: " + (string)buyGroup.positionCount + " pos, " + DoubleToString(buyGroup.totalLotSize, 2) + " lots");
    AddPanelLine(panel_lines, "Sell Group: " + (string)sellGroup.positionCount + " pos, " + DoubleToString(sellGroup.totalLotSize, 2) + " lots");
    
    ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER;
    switch(InpPanelCorner)
    {
        case PC_LEFT_UPPER:   corner = CORNER_LEFT_UPPER;   break;
        case PC_RIGHT_UPPER:  corner = CORNER_RIGHT_UPPER;  break;
        case PC_LEFT_LOWER:   corner = CORNER_LEFT_LOWER;   break;
        case PC_RIGHT_LOWER:  corner = CORNER_RIGHT_LOWER;  break;
    }
    
    // ★★★ 変更点: フォントサイズに応じて行の高さを動的に変更 ★★★
    int line_height = (int)round(InpPanelFontSize * 1.5);

    for(int i = 0; i < ArraySize(panel_lines); i++)
    {
        string obj_name = g_panelPrefix + (string)i;
        int    y_pos    = p_panel_y_offset + (i * line_height);
        if(ObjectFind(0, obj_name) < 0)
        {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, p_panel_x_offset);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, corner);
            ObjectSetString(0, obj_name, OBJPROP_FONT, "Lucida Console");
            // ★★★ 変更点: フォントサイズを入力パラメータから取得 ★★★
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, InpPanelFontSize);
            
            if(InpPanelCorner == PC_RIGHT_UPPER || InpPanelCorner == PC_RIGHT_LOWER)
            {
                ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_RIGHT);
            }
            else
            {
                ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
            }
        }
        ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y_pos);
        ObjectSetString(0, obj_name, OBJPROP_TEXT, panel_lines[i]);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrLightGray);
    }
    for(int i = ArraySize(panel_lines); i < 30; i++)
    {
        string obj_name = g_panelPrefix + (string)i;
        if(ObjectFind(0, obj_name) >= 0)
            ObjectDelete(0, obj_name);
        else
            break;
    }
}

//+------------------------------------------------------------------+
//| 情報パネルにテキスト行を追加するヘルパー関数                     |
//+------------------------------------------------------------------+
void AddPanelLine(string &lines[], const string text)
{
    int size = ArraySize(lines);
    ArrayResize(lines, size + 1);
    lines[size] = text;
}

//+------------------------------------------------------------------+
//| MACDスコアを計算（ソフトVetoのログ出力を無効化）                 |
//+------------------------------------------------------------------+
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal)
{
    ScoreComponentInfo info;
    ZeroMemory(info);
    
    double exec_main[], exec_signal[], mid_main[], mid_signal[], long_main[];
    ArraySetAsSeries(exec_main, true); ArraySetAsSeries(exec_signal, true);
    ArraySetAsSeries(mid_main, true);  ArraySetAsSeries(mid_signal, true);
    ArraySetAsSeries(long_main, true);
    
    if(CopyBuffer(h_macd_exec, 0, 0, 30, exec_main) < 30 || CopyBuffer(h_macd_exec, 1, 0, 30, exec_signal) < 30) return info;
    if(CopyBuffer(h_macd_mid, 0, 0, 4, mid_main) < 4 || CopyBuffer(h_macd_mid, 1, 0, 1, mid_signal) < 1) return info;
    if(CopyBuffer(h_macd_long, 0, 0, 1, long_main) < 1) return info;
    
    // --- 1. ベース条件の判定 ---
    if(is_buy_signal)
    {
        if(CheckMACDDivergence(true, h_macd_exec)) info.divergence = true;
        if(mid_main[0] > 0)  info.mid_zeroline = true;
        if(long_main[0] > 0) info.long_zeroline = true;
        if(exec_main[0] - exec_main[3] > 0) info.exec_angle = true;
        if(mid_main[0] - mid_main[3] > 0)   info.mid_angle = true;
        double h0=exec_main[0]-exec_signal[0], h1=exec_main[1]-exec_signal[1];
        if(h0 > h1 && h1 > 0) info.exec_hist = true;
        if(mid_main[0] - mid_signal[0] > 0) info.mid_hist_sync = true;
    }
    else
    {
        if(CheckMACDDivergence(false, h_macd_exec)) info.divergence = true;
        if(mid_main[0] < 0)  info.mid_zeroline = true;
        if(long_main[0] < 0) info.long_zeroline = true;
        if(exec_main[0] - exec_main[3] < 0) info.exec_angle = true;
        if(mid_main[0] - mid_main[3] < 0)   info.mid_angle = true;
        double h0=exec_main[0]-exec_signal[0], h1=exec_main[1]-exec_signal[1];
        if(h0 < h1 && h1 < 0) info.exec_hist = true;
        if(mid_main[0] - mid_signal[0] < 0) info.mid_hist_sync = true;
    }
    
    // --- ベーススコアの記録 ---
    if(info.divergence)   info.score_divergence    = 3;
    if(info.mid_zeroline)  info.score_mid_zeroline  = 2;
    if(info.long_zeroline) info.score_long_zeroline = 3;
    if(info.exec_angle)    info.score_exec_angle    = 1;
    if(info.mid_angle)     info.score_mid_angle     = 2;
    if(info.exec_hist)     info.score_exec_hist     = 1;
    if(info.mid_hist_sync) info.score_mid_hist_sync = 1;

    // --- 2. スコア合計の計算 ---
    if(InpEnableWeightedScoring)
    {
        double weighted_score = 0;
        if(info.divergence)   weighted_score += info.score_divergence    * InpWeightDivergence;
        if(info.mid_zeroline)  weighted_score += info.score_mid_zeroline  * InpWeightMidTrend;
        if(info.long_zeroline) weighted_score += info.score_long_zeroline * InpWeightLongTrend;
        if(info.exec_angle)    weighted_score += info.score_exec_angle    * InpWeightExecAngle;
        if(info.mid_angle)     weighted_score += info.score_mid_angle     * InpWeightMidAngle;
        if(info.exec_hist)     weighted_score += info.score_exec_hist     * InpWeightExecHist;
        if(info.mid_hist_sync) weighted_score += info.score_mid_hist_sync * InpWeightMidHist;
        info.total_score = (int)round(weighted_score);
    }
    else
    {
        info.total_score = info.score_divergence + info.score_mid_zeroline + info.score_long_zeroline +
                           info.score_exec_angle + info.score_mid_angle + info.score_exec_hist + info.score_mid_hist_sync;
    }

    // --- 3. コンボボーナスの加点 ---
    if(InpEnableComboBonuses)
    {
        if(info.long_zeroline && info.mid_zeroline) info.total_score += InpBonusTrendAlignment;
        if(info.long_zeroline && info.divergence)   info.total_score += InpBonusTrendDivergence;
    }

    // --- 4. ソフトVetoの適用（減点）---
    if(InpEnableSoftVeto)
    {
        if(!info.long_zeroline)
        {
            // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
            // ★★★ この行をコメントアウトして無効化します ★★★
            // PrintFormat("ソフトVeto: 長期トレンド逆行のため、スコア(%d)にペナルティ(%d)を適用します。", info.total_score, InpPenaltyCounterTrend);
            // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
            info.total_score += InpPenaltyCounterTrend;
        }
    }
    
    if(info.total_score < 0) info.total_score = 0;

    return info;
}

//+------------------------------------------------------------------+
//| MACDのダイバージェンスを検出                                     |
//+------------------------------------------------------------------+
bool CheckMACDDivergence(bool is_buy_signal, int macd_handle)
{
    MqlRates rates[];
    double macd_main[];
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(macd_main, true);
    int check_bars = 30;
    if(CopyRates(_Symbol, InpMACD_TF_Exec, 0, check_bars, rates) < check_bars) return false;
    if(CopyBuffer(macd_handle, 0, 0, check_bars, macd_main) < check_bars) return false;
    int p1_idx = -1, p2_idx = -1;
    if(is_buy_signal)
    {
        for(int i = 1; i < check_bars - 1; i++)
        {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
            {
                if(p1_idx == -1)
                {
                    p1_idx = i;
                }
                else
                {
                    p2_idx = p1_idx;
                    p1_idx = i;
                    break;
                }
            }
        }
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].low < rates[p2_idx].low && macd_main[p1_idx] > macd_main[p2_idx])
            {
                double price = rates[p1_idx].low - InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBullishDivColor);
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
                if(p1_idx == -1)
                {
                    p1_idx = i;
                }
                else
                {
                    p2_idx = p1_idx;
                    p1_idx = i;
                    break;
                }
            }
        }
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].high > rates[p2_idx].high && macd_main[p1_idx] < macd_main[p2_idx])
            {
                double price = rates[p1_idx].high + InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBearishDivColor);
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| 【決済競合対策版】パーシャルクローズイーブンのロジック           |
//| 両建てポジションの合計損益がプラスになったら全決済する           |
//+------------------------------------------------------------------+
void CheckPartialCloseEven()
{
    // この関数が最後に決済を発動した時刻を記憶する静的変数
    static datetime lastExecutionTime = 0;
    
    // 前回の実行から60秒経過していない場合は、処理を中断して重複実行を防止
    if (TimeCurrent() < lastExecutionTime + 60)
    {
        return;
    }

    // パラメータで機能が無効化されている場合は何もしない
    if (!InpEnablePartialCloseEven)
    {
        return;
    }

    // BUYとSELLの両方のグループがアクティブ（両建て状態）でない場合は何もしない
    if (!buyGroup.isActive || !sellGroup.isActive)
    {
        return;
    }

    double totalProfit = 0;

    // EAが管理するすべてのポジションをループ
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            // 現在のポジションの損益（スワップ、手数料込み）を取得して合計に加算
            totalProfit += PositionGetDouble(POSITION_PROFIT);
        }
    }

    // 合計損益がユーザー設定値を超えた場合
    if (totalProfit >= InpPartialCloseEvenProfit)
    {
        PrintFormat("パーシャルクローズイーブン発動: 合計利益=%.2f. 全ポジションを決済します。", totalProfit);
        
        // ★★★ 決済を発動した現在時刻を記録 ★★★
        lastExecutionTime = TimeCurrent();
        
        // 全てのBUYポジションとSELLポジションを決済
        // 注: CloseAllPositionsInGroupは内部でClosePositionを呼ぶため、そちらの関数は変更不要です。
        CloseAllPositionsInGroup(buyGroup);
        CloseAllPositionsInGroup(sellGroup);
        
        // 念のためチャートを再描画
        ChartRedraw();
    }
}

//+------------------------------------------------------------------+
//| 【改修版】ライン名から永続的な状態オブジェクトの番号を取得・作成する |
//+------------------------------------------------------------------+
int GetLineState(string lineName)
{
    for(int i = 0; i < ArraySize(g_lineStates); i++)
    {
        if(g_lineStates[i].name == lineName)
        {
            return i;
        }
    }

    // 見つからない場合は新規作成
    int size = ArraySize(g_lineStates);
    ArrayResize(g_lineStates, size + 1);
    g_lineStates[size].name = lineName;
    g_lineStates[size].isBrokeUp = false;
    g_lineStates[size].isBrokeDown = false;
    // ★★★ 追加されたメンバの初期化 ★★★
    g_lineStates[size].waitForRetestUp = false;
    g_lineStates[size].waitForRetestDown = false;
    g_lineStates[size].breakTime = 0;
    
    return size;
}

//+------------------------------------------------------------------+
//| グループの分割決済を実行する                                     |
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
        ZeroMemory(tradeResult);
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.type_filling = ORDER_FILLING_IOC;
        request.sl = 0.0;
        request.tp = 0.0;
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
//| 指定したポジションのSL (ストップロス) を変更する                 |
//+------------------------------------------------------------------+
void ModifyPositionSL(ulong ticket, double sl_price)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    if (!PositionSelectByTicket(ticket)) return;

    // 現在設定されているSLとTPを取得
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);

    // 新しいSLが現在のSLと同じなら何もしない
    if (MathAbs(current_sl - sl_price) < g_pip)
    {
        return;
    }
    
    // BE設定などで、より有利なSLが既に設定されている場合は更新しない
    // (買いポジションの場合、新しいSLが現在より低いなら不利なので更新しない)
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_sl > 0 && sl_price < current_sl)
    {
        return;
    }
    // (売りポジションの場合、新しいSLが現在より高いなら不利なので更新しない)
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_sl > 0 && sl_price > current_sl)
    {
        return;
    }

    request.action   = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol   = _Symbol;
    request.sl       = NormalizeDouble(sl_price, _Digits);
    request.tp       = current_tp; // TPは変更しない

    if (!OrderSend(request, result))
    {
        PrintFormat("ポジション #%d のSL変更に失敗しました。エラー: %d", ticket, GetLastError());
    }
    else
    {
        PrintFormat("ポジション #%d のSLを %.5f に設定しました。", ticket, sl_price);
    }
}

//+------------------------------------------------------------------+
//| グループ全体のストップロスを更新する (手動SLモード対応版)        |
//+------------------------------------------------------------------+
void UpdateGroupSL(PositionGroup &group)
{
    if (!group.isActive) return;
    double sl_price = 0;
    if(InpSlMode == SL_MODE_OPPOSITE_TP) { sl_price = group.isBuy ? zonalFinalTPLine_Sell : zonalFinalTPLine_Buy; }
    else if(InpSlMode == SL_MODE_MANUAL) { sl_price = group.isBuy ? g_slLinePrice_Buy : g_slLinePrice_Sell; }
    else if(InpEnableAtrSL)
    {
        double atr_buffer[1];
        if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) > 0)
        {
            sl_price = group.isBuy ? group.averageEntryPrice - (atr_buffer[0] * InpAtrSlMultiplier) : group.averageEntryPrice + (atr_buffer[0] * InpAtrSlMultiplier);
        }
    }
    if(sl_price <= 0) return;
    for (int i = 0; i < group.positionCount; i++) { ModifyPositionSL(group.positionTickets[i], sl_price); }
}

//+------------------------------------------------------------------+
//| ロットサイズを計算する (高スコアリスク対応版)                    |
//+------------------------------------------------------------------+
double CalculateRiskBasedLotSize(int score) // ★★★ 引数にscoreを追加 ★★★
{
    // --- 1. SLまでの価格差を計算 ---
    double atr_buffer[1];
    if (CopyBuffer(h_atr_sl, 0, 0, 1, atr_buffer) <= 0)
    {
        Print("ロット計算エラー: ATR値が取得できませんでした。");
        return 0.0;
    }
    double sl_distance_price = atr_buffer[0] * InpAtrSlMultiplier;
    if (sl_distance_price <= 0)
    {
        Print("ロット計算エラー: SL値幅が0以下です。");
        return 0.0;
    }

    // --- 2. 適用するリスク率を決定 ---
    double risk_percent_to_use = InpRiskPercent; // デフォルトのリスク率
    if (InpEnableHighScoreRisk && score >= InpScore_High)
    {
        risk_percent_to_use = InpHighScoreRiskPercent; // 高スコア時のリスク率を適用
        PrintFormat("高スコア(%d)のため、リスク率を %.2f%% に変更します。", score, risk_percent_to_use);
    }
    
    // --- 3. 許容損失額を口座通貨で計算 ---
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount_account_ccy = account_balance * (risk_percent_to_use / 100.0);

    // --- 4. 1ロットあたりの損失額を、為替レートを考慮して計算 ---
    double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    string quote_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    string account_currency = AccountInfoString(ACCOUNT_CURRENCY);

    double loss_per_lot_quote_ccy = sl_distance_price * contract_size;
    
    double conversion_rate = 1.0;
    if (quote_currency != account_currency)
    {
        conversion_rate = GetConversionRate(quote_currency, account_currency);
        if (conversion_rate <= 0)
        {
            PrintFormat("ロット計算エラー: 通貨ペア %s -> %s の為替レートが取得できませんでした。", quote_currency, account_currency);
            return 0.0;
        }
    }
    
    double loss_per_lot_account_ccy = loss_per_lot_quote_ccy * conversion_rate;

    if(loss_per_lot_account_ccy <= 0)
    {
        Print("ロット計算エラー: 1ロットあたりの損失額が0以下です。");
        return 0.0;
    }
    
    // --- 5. 最終的なロットサイズを計算 ---
    double desired_lot = risk_amount_account_ccy / loss_per_lot_account_ccy;

    // --- 6. ロットサイズを正規化（取引単位に合わせる）し、上限・下限をチェック ---
    double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double vol_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double normalized_lot = floor(desired_lot / vol_step) * vol_step;

    if (normalized_lot < vol_min)
    {
        normalized_lot = vol_min;
        PrintFormat("計算ロット(%.2f)が最小ロット(%.2f)より小さいため、最小ロットに調整しました。", desired_lot, vol_min);
    }
    if (normalized_lot > vol_max)
    {
        normalized_lot = vol_max;
        PrintFormat("計算ロット(%.2f)が最大ロット(%.2f)より大きいため、最大ロットに調整しました。", desired_lot, vol_max);
    }

    return normalized_lot;
}

//+------------------------------------------------------------------+
//| 2つの通貨間の為替レートを取得するヘルパー関数                    |
//+------------------------------------------------------------------+
double GetConversionRate(string from_currency, string to_currency)
{
    // 通貨が同じならレートは1.0
    if (from_currency == to_currency)
    {
        return 1.0;
    }

    // 正方向のペアを試す (例: USDJPY)
    string pair_direct = from_currency + to_currency;
    if (SymbolSelect(pair_direct, true))
    {
        return SymbolInfoDouble(pair_direct, SYMBOL_ASK);
    }

    // 逆方向のペアを試す (例: JPYUSD -> USDJPYの逆数)
    string pair_inverse = to_currency + from_currency;
    if (SymbolSelect(pair_inverse, true))
    {
        double inverse_rate = SymbolInfoDouble(pair_inverse, SYMBOL_BID);
        if (inverse_rate > 0)
        {
            return 1.0 / inverse_rate;
        }
    }

    // レートが見つからなかった場合
    return 0.0;
}

//+------------------------------------------------------------------+
//| グループのトレーリングストップを管理する (ロジック整理版)          |
//+------------------------------------------------------------------+
void ManageTrailingSL(PositionGroup &group)
{
    if (!InpEnableTrailingSL || !group.isActive || group.splitsDone < InpBreakEvenAfterSplits || InpBreakEvenAfterSplits == 0)
    {
        return;
    }

    double atr_buffer[1];
    if (CopyBuffer(h_atr_sl, 0, 1, 1, atr_buffer) <= 0) return;
    double atr_value = atr_buffer[0];

    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;
    double reference_price = rates[1].close;

    double new_sl_price = 0;
    if (group.isBuy)
    {
        new_sl_price = reference_price - (atr_value * InpTrailingAtrMultiplier);
    }
    else
    {
        new_sl_price = reference_price + (atr_value * InpTrailingAtrMultiplier);
    }

    for (int i = 0; i < group.positionCount; i++)
    {
        ModifyPositionSL(group.positionTickets[i], new_sl_price);
    }
}

//+------------------------------------------------------------------+
//| 動的決済ロジック（時間経過・反対シグナル）をチェックする         |
//+------------------------------------------------------------------+
void CheckDynamicExits()
{
    // どちらの機能も無効なら何もしない
    if (!InpEnableTimeExit && !InpEnableCounterSignalExit)
    {
        return;
    }

    // 管理下の全ポジションをループしてチェック
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        // このEAが管理するポジションでなければスキップ
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
        {
            continue;
        }
        
        if (PositionSelectByTicket(ticket))
        {
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            // --- 1. タイム・エグジットのチェック ---
            if (InpEnableTimeExit)
            {
                datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                // 現在の足が何本目かを計算
                int bars_held = iBarShift(_Symbol, _Period, open_time, false);

                if (bars_held > InpExitAfterBars)
                {
                    // 現在の含み損益を取得
                    double current_profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                    if (current_profit < InpExitMinProfit)
                    {
                        PrintFormat("動的決済(時間): ポジション #%d が%d本経過後も利益%.2fに未達のため決済します。", ticket, InpExitAfterBars, InpExitMinProfit);
                        ClosePosition(ticket);
                        continue; // このポジションは決済したので次のループへ
                    }
                }
            }

            // --- 2. カウンターシグナル・エグジットのチェック ---
            if (InpEnableCounterSignalExit)
            {
                if (pos_type == POSITION_TYPE_BUY)
                {
                    // 買いポジション保有中に、強い「売り」スコアが出たら決済
                    ScoreComponentInfo sell_info = CalculateMACDScore(false);
                    if (sell_info.total_score >= InpCounterSignalScore)
                    {
                        PrintFormat("動的決済(反対シグナル): 買いポジション #%d 保有中に強い売りスコア(%d)が出たため決済します。", ticket, sell_info.total_score);
                        ClosePosition(ticket);
                        continue; // このポジションは決済したので次のループへ
                    }
                }
                else // POSITION_TYPE_SELL
                {
                    // 売りポジション保有中に、強い「買い」スコアが出たら決済
                    ScoreComponentInfo buy_info = CalculateMACDScore(true);
                    if (buy_info.total_score >= InpCounterSignalScore)
                    {
                        PrintFormat("動的決済(反対シグナル): 売りポジション #%d 保有中に強い買いスコア(%d)が出たため決済します。", ticket, buy_info.total_score);
                        ClosePosition(ticket);
                        continue; // このポジションは決済したので次のループへ
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ★★★修正版★★★ 手動SLラインを描画・管理する (実線固定)      |
//+------------------------------------------------------------------+
void ManageSlLines()
{
    // 手動SLモードでない場合は、ラインを消して処理を終了
    if(InpSlMode != SL_MODE_MANUAL)
    {
        ObjectDelete(0, "SLLine_Buy");
        ObjectDelete(0, "SLLine_Sell");
        return;
    }

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;

    // --- 買いSLラインの管理 ---
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
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID); // ★★★ 線種を実線に固定 ★★★
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
    }

    // --- 売りSLラインの管理 ---
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
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID); // ★★★ 線種を実線に固定 ★★★
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
    }
}

//+------------------------------------------------------------------+
//| ★★★修正版★★★ ゾーン内でのMACDクロスエントリーをチェックする |
//+------------------------------------------------------------------+
void CheckZoneMacdCross()
{
    if (!InpEnableZoneMacdCross || InpEntryMode != ZONE_MODE) return;
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

        if (isBuyCross && line.type == LINE_TYPE_SUPPORT)
        {
            if (tick.ask > lower_zone && tick.ask < upper_zone)
            {
                PrintFormat("%s のゾーン内でMACDクロス(BUY)検出", line.name);
                ScoreComponentInfo info = CalculateMACDScore(true);
                if (info.total_score >= InpScore_Standard)
                {
                    PlaceOrder(true, tick.ask, info.total_score, "Zone MACD Cross Buy");
                    lastZoneCrossEntryTime = TimeCurrent();
                    return;
                }
            }
        }
        if (isSellCross && line.type == LINE_TYPE_RESISTANCE)
        {
            if (tick.bid > lower_zone && tick.bid < upper_zone)
            {
                PrintFormat("%s のゾーン内でMACDクロス(SELL)検出", line.name);
                ScoreComponentInfo info = CalculateMACDScore(false);
                if (info.total_score >= InpScore_Standard)
                {
                    PlaceOrder(false, tick.bid, info.total_score, "Zone MACD Cross Sell");
                    lastZoneCrossEntryTime = TimeCurrent();
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ゾーンを長方形オブジェクトで可視化する (終点ロジック修正版)        |
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
            datetime endTime;
            if (line.breakTime > 0)
            {
                endTime = line.breakTime;
            }
            else
            {
                endTime = TimeCurrent() + 3600 * 24 * 30;
            }
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
//| ★★★新規★★★ ゾーン可視化ボタンの状態を更新する          |
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
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'80,80,80'); // Dark Gray
    }
}