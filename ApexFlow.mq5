//+------------------------------------------------------------------+
//|                                                   ApexFlowEA.mq5 |
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

// --- ボタン名定義
#define BUTTON_BUY_CLOSE_ALL  "Button_BuyCloseAll"
#define BUTTON_SELL_CLOSE_ALL "Button_SellCloseAll"
#define BUTTON_ALL_CLOSE      "Button_AllClose"
#define BUTTON_RESET_BUY_TP   "Button_ResetBuyTP"
#define BUTTON_RESET_SELL_TP  "Button_ResetSellTP"

// ==================================================================
// --- ENUM / 構造体定義 ---
// ==================================================================
// サポート/レジスタンスの種別を定義
enum ENUM_LINE_TYPE
{
    LINE_TYPE_SUPPORT,
    LINE_TYPE_RESISTANCE
};

// ライン情報を一元管理するための構造体
struct Line
{
    string         name;
    double         price;
    ENUM_LINE_TYPE type;
    color          signalColor;
    bool           isBrokeUp;
    bool           isBrokeDown;
    bool           waitForRetest;
    bool           isInZone;
};

// 保有ポジションの情報を管理するための構造体
struct PositionInfo
{
    long ticket; // ポジションのチケット番号
    int  score;  // エントリー時のスコア
};

// スコアリングの各要素の検知状況を保持する構造体
struct ScoreComponentInfo
{
    bool divergence;
    bool exec_angle;
    bool mid_angle;
    bool exec_hist;
    bool mid_hist_sync;
    bool mid_zeroline;
    bool long_zeroline;
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

// ==================================================================
// --- 入力パラメータ (日本語表記・コメントを完全維持) ---
// ==================================================================
input group "=== エントリーロジック設定 ===";
input bool           InpUsePivotLines        = true;     // ピボットラインを使用する
enum ENTRY_MODE
{
    TOUCH_MODE,
    ZONE_MODE
};
input ENTRY_MODE     InpEntryMode            = ZONE_MODE; // エントリーモード
input bool           InpBreakMode            = true;     // ブレイクモード
input double         InpZonePips             = 50.0;     // ゾーン幅 (pips)

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
input bool           InpEnableButtons        = true;     // ボタン表示を有効にする

input group "=== 取引設定 ===";
input double         InpLotSize              = 0.1;      // ロットサイズ
input int            InpMaxPositions         = 5;        // 同方向の最大ポジション数
input int            InpMagicNumber          = 123456;   // マジックナンバー
input int            InpDotTimeout           = 600;      // ドット/矢印有効期限 (秒)

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

input group "=== MACDスコアリング設定 ===";
input int            InpScore_Standard       = 4;       // 標準エントリーの最低スコア
input int            InpScore_High           = 6;       // 高スコアエントリーの最低スコア

input group "--- 執行足MACD (トリガー) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Exec        = PERIOD_CURRENT; // 時間足 (PERIOD_CURRENT=チャートの時間足)
input int             InpMACD_Fast_Exec       = 12;             // Fast EMA
input int             InpMACD_Slow_Exec       = 26;             // Slow EMA
input int             InpMACD_Signal_Exec     = 9;              // Signal SMA

input group "--- 中期足MACD (コンテキスト) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Mid         = PERIOD_H1;      // 時間足
input int             InpMACD_Fast_Mid        = 12;             // Fast EMA
input int             InpMACD_Slow_Mid        = 26;             // Slow EMA
input int             InpMACD_Signal_Mid      = 9;              // Signal SMA

input group "--- 長期足MACD (コンファメーション) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Long        = PERIOD_H4;      // 時間足
input int             InpMACD_Fast_Long       = 12;             // Fast EMA
input int             InpMACD_Slow_Long       = 26;             // Slow EMA
input int             InpMACD_Signal_Long     = 9;              // Signal SMA

input group "=== 決済ロジック設定 (Zephyr) ===";
input ENUM_POSITION_MODE InpPositionMode         = MODE_AGGREGATE; // ポジション管理モード
input ENUM_EXIT_LOGIC    InpExitLogic            = EXIT_UNFAVORABLE; // 分割決済のロジック
input int                InpSplitCount           = 5;              // 分割決済の回数
input bool               InpEnableDynamicSplits  = true;           // スコアで分割数を増やす
input int                InpHighScoreSplit_Add   = 3;              // 高スコア時に追加する分割数
input double             InpExitBufferPips       = 1.0;            // 決済バッファ (Pips)
input int                InpBreakEvenAfterSplits = 2;              // N回分割決済後にBE設定 (0=無効)
input double             InpHighSchoreTpRratio   = 1.5;            // 高スコア時のTP倍率
input ENUM_TP_MODE       InpTPLineMode           = MODE_ZIGZAG;    // TPラインのモード
input int                InpZigzagDepth          = 12;             // ZigZag: Depth
input int                InpZigzagDeviation      = 5;              // ZigZag: Deviation
input int                InpZigzagBackstep       = 3;              // ZigZag: Backstep

input group "=== ピボットライン設定 ===";
input ENUM_TIMEFRAMES InpPivotPeriod          = PERIOD_H1;    // ピボット時間足
input bool            InpShowS2R2             = true;         // S2/R2ラインを表示
input bool            InpShowS3R3             = true;         // S3/R3ラインを表示
input bool            InpAllowOuterTouch      = false;        // ライン外側からのタッチ/ブレイク検知を許可

input group "=== 手動ライン設定 ===";
input color           p_ManualSupport_Color   = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color    = clrTomato;     // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style      = STYLE_DOT;     // 手動ラインのスタイル
input int             p_ManualLine_Width      = 2;             // 手動ラインの太さ

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
input int    InpZoneReboundBuyCode   = 231;          // ゾーン内反発 (買い) のシンボルコード
input int    InpZoneReboundSellCode  = 232;          // ゾーン内反発 (売り) のシンボルコード
input int    InpVReversalBuyCode     = 233;          // V字回復 (買い) のシンボルコード
input int    InpVReversalSellCode    = 234;          // V字回復 (売り) のシンボルコード
input int    InpRetestBuyCode        = 110;          // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode       = 111;          // ブレイク＆リテスト (売り) のシンボルコード

// ==================================================================
// --- グローバル変数 ---
// ==================================================================
double       g_pip;
Line         allLines[];
PositionInfo g_managedPositions[];
int          h_macd_exec, h_macd_mid, h_macd_long, h_atr;
datetime     lastBar[2];
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
void DeleteGroupSplitLines(PositionGroup &group);

// ==================================================================
// --- 主要関数 ---
// ==================================================================

//+------------------------------------------------------------------+
//| エキスパート初期化関数                                         |
//+------------------------------------------------------------------+
int OnInit()
{
    g_pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pow(10, _Digits % 2);
    lastBar[0] = 0;
    lastBar[1] = 0;
    lastTradeTime = 0;
    h_macd_exec = iMACD(_Symbol, InpMACD_TF_Exec, InpMACD_Fast_Exec, InpMACD_Slow_Exec, InpMACD_Signal_Exec, PRICE_CLOSE);
    h_macd_mid = iMACD(_Symbol, InpMACD_TF_Mid, InpMACD_Fast_Mid, InpMACD_Slow_Mid, InpMACD_Signal_Mid, PRICE_CLOSE);
    h_macd_long = iMACD(_Symbol, InpMACD_TF_Long, InpMACD_Fast_Long, InpMACD_Slow_Long, InpMACD_Signal_Long, PRICE_CLOSE);
    h_atr = iATR(_Symbol, InpMACD_TF_Exec, 14);
    zigzagHandle = iCustom(_Symbol, _Period, "ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);
    if(h_macd_exec == INVALID_HANDLE || h_macd_mid == INVALID_HANDLE || h_macd_long == INVALID_HANDLE || zigzagHandle == INVALID_HANDLE)
    {
        Print("インジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }
    if (InpPositionMode == MODE_AGGREGATE)
    {
        InitGroup(buyGroup, true);
        InitGroup(sellGroup, false);
    }
    else
    {
        ArrayResize(splitPositions, 0);
    }
    UpdateLines();
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
    }
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);
    Print("ApexFlowEA v4.0 初期化完了");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, g_buttonName);
    ObjectsDeleteAll(0, g_clearButtonName);
    ObjectsDeleteAll(0, g_clearLinesButtonName);
    ObjectsDeleteAll(0, g_panelPrefix);
    ObjectsDeleteAll(0, InpLinePrefix_Pivot);
    ObjectsDeleteAll(0, InpDotPrefix);
    ObjectsDeleteAll(0, InpArrowPrefix);
    ObjectsDeleteAll(0, InpDivSignalPrefix);
    ObjectsDeleteAll(0, "ManualTrend_");
    ObjectsDeleteAll(0, BUTTON_BUY_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_SELL_CLOSE_ALL);
    ObjectsDeleteAll(0, BUTTON_ALL_CLOSE);
    ObjectsDeleteAll(0, BUTTON_RESET_BUY_TP);
    ObjectsDeleteAll(0, BUTTON_RESET_SELL_TP);
    ObjectsDeleteAll(0, "TPLine_Buy");
    ObjectsDeleteAll(0, "TPLine_Sell");
    ObjectsDeleteAll(0, "SplitLine_");
    IndicatorRelease(h_macd_exec);
    IndicatorRelease(h_macd_mid);
    IndicatorRelease(h_macd_long);
    IndicatorRelease(h_atr);
    IndicatorRelease(zigzagHandle);
    PrintFormat("ApexFlowEA 終了: 理由=%d", reason);
}

//+------------------------------------------------------------------+
//| エキスパートティック関数                                         |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewBar(InpPivotPeriod))
    {
        UpdateLines();
    }
    if(IsNewBar(PERIOD_M5))
    {
        SyncManagedPositions();
        if (InpPositionMode == MODE_AGGREGATE)
        {
            ManagePositionGroups();
        }
        else
        {
            DetectNewEntrances();
        }
        if (InpPositionMode == MODE_AGGREGATE)
        {
            CheckExitForGroup(buyGroup);
            CheckExitForGroup(sellGroup);
        }
        else
        {
            CheckExits();
        }
        CheckEntry();
        UpdateZones();
        ManageInfoPanel();
        ManageManualLines();
    }
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数 (最終調整版)
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == g_buttonName)
        {
            g_isDrawingMode = !g_isDrawingMode;
            UpdateButtonState();
            if(g_isDrawingMode)
            {
                g_ignoreNextChartClick = true;
            }
            return;
        }
        if(sparam == g_clearButtonName) { ClearSignalObjects(); return; }
        if(sparam == g_clearLinesButtonName) { ClearManualLines(); return; }
        if(sparam == BUTTON_BUY_CLOSE_ALL) { if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup); return; }
        if(sparam == BUTTON_SELL_CLOSE_ALL) { if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup); return; }
        if(sparam == BUTTON_ALL_CLOSE) { if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup); if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup); return; }
        if(sparam == BUTTON_RESET_BUY_TP) { isBuyTPManuallyMoved = false; UpdateZones(); if(buyGroup.isActive) { buyGroup.stampedFinalTP = zonalFinalTPLine_Buy; UpdateGroupSplitLines(buyGroup); } ChartRedraw(); return; }
        if(sparam == BUTTON_RESET_SELL_TP) { isSellTPManuallyMoved = false; UpdateZones(); if(sellGroup.isActive) { sellGroup.stampedFinalTP = zonalFinalTPLine_Sell; UpdateGroupSplitLines(sellGroup); } ChartRedraw(); return; }
    }
    
    if(id == CHARTEVENT_CLICK && g_isDrawingMode)
    {
        if(g_ignoreNextChartClick)
        {
            g_ignoreNextChartClick = false;
            return;
        }

        int sub;
        datetime t;
        double p;
        if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sub, t, p) && sub == 0)
        {
            DrawManualTrendLine(p, t);
            // ★★★ 修正箇所: 1回描画してもモードを解除しないように変更 ★★★
            // g_isDrawingMode = false;
            // UpdateButtonState();
        }
        return;
    }

    if (id == CHARTEVENT_OBJECT_DRAG && (sparam == "TPLine_Buy" || sparam == "TPLine_Sell"))
    {
        double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0);
        if(sparam == "TPLine_Buy")
        {
            if (!isBuyTPManuallyMoved || zonalFinalTPLine_Buy != newPrice)
            {
                isBuyTPManuallyMoved = true;
                zonalFinalTPLine_Buy = newPrice;
                ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                if(buyGroup.isActive) { buyGroup.stampedFinalTP = newPrice; UpdateGroupSplitLines(buyGroup); }
            }
        }
        else
        {
            if (!isSellTPManuallyMoved || zonalFinalTPLine_Sell != newPrice)
            {
                isSellTPManuallyMoved = true;
                zonalFinalTPLine_Sell = newPrice;
                ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                if(sellGroup.isActive) { sellGroup.stampedFinalTP = newPrice; UpdateGroupSplitLines(sellGroup); }
            }
        }
        ChartRedraw();
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
//| ポジショングループの状態を更新する                               |
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
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double volume = PositionGetDouble(POSITION_VOLUME);
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
            if(InpEnableDynamicSplits && buyGroup.highestScore >= InpScore_High)
            {
                buyGroup.lockedInSplitCount += InpHighScoreSplit_Add;
            }
            if(!isBuyTPManuallyMoved)
            {
                UpdateZones();
                buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
            }
        }
        else
        {
            buyGroup.initialTotalLotSize = oldBuyGroup.initialTotalLotSize;
            buyGroup.splitsDone = oldBuyGroup.splitsDone;
            buyGroup.lockedInSplitCount = oldBuyGroup.lockedInSplitCount;
            buyGroup.stampedFinalTP = oldBuyGroup.stampedFinalTP;
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
            sellGroup.lockedInSplitCount = InpSplitCount;
            if(InpEnableDynamicSplits && sellGroup.highestScore >= InpScore_High)
            {
                sellGroup.lockedInSplitCount += InpHighScoreSplit_Add;
            }
            if(!isSellTPManuallyMoved)
            {
                UpdateZones();
                sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
            }
        }
        else
        {
            sellGroup.initialTotalLotSize = oldSellGroup.initialTotalLotSize;
            sellGroup.splitsDone = oldSellGroup.splitsDone;
            sellGroup.lockedInSplitCount = oldSellGroup.lockedInSplitCount;
            sellGroup.stampedFinalTP = oldSellGroup.stampedFinalTP;
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
//| ZigZagに基づくTPラインを更新する                                 |
//+------------------------------------------------------------------+
void UpdateZones()
{
    double zigzag[];
    ArraySetAsSeries(zigzag, true);
    if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) <= 0) return;
    double levelHigh = 0, levelLow = DBL_MAX;
    for(int i = 0; i < 100; i++)
    {
        if(zigzag[i] > 0)
        {
            if(zigzag[i] > levelHigh) levelHigh = zigzag[i];
            if(zigzag[i] < levelLow) levelLow = zigzag[i];
        }
    }
    if(!isBuyTPManuallyMoved)
    {
        double newBuyTP = (levelHigh > 0) ? levelHigh : 0;
        if(buyGroup.isActive && buyGroup.highestScore >= InpScore_High && newBuyTP > 0)
        {
            double entryPrice = buyGroup.averageEntryPrice;
            double originalDiff = newBuyTP - entryPrice;
            if(originalDiff > 0) newBuyTP = entryPrice + (originalDiff * InpHighSchoreTpRratio);
        }
        if (newBuyTP > 0 && MathAbs(newBuyTP - zonalFinalTPLine_Buy) > g_pip)
        {
            zonalFinalTPLine_Buy = newBuyTP;
            string name = "TPLine_Buy";
            if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
            ObjectMove(0, name, 0, 0, zonalFinalTPLine_Buy);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        }
    }
    if(!isSellTPManuallyMoved)
    {
        double newSellTP = (levelLow < DBL_MAX) ? levelLow : 0;
        if(sellGroup.isActive && sellGroup.highestScore >= InpScore_High && newSellTP > 0)
        {
            double entryPrice = sellGroup.averageEntryPrice;
            double originalDiff = entryPrice - newSellTP;
            if(originalDiff > 0) newSellTP = entryPrice - (originalDiff * InpHighSchoreTpRratio);
        }
        if (newSellTP > 0 && MathAbs(newSellTP - zonalFinalTPLine_Sell) > g_pip)
        {
            zonalFinalTPLine_Sell = newSellTP;
            string name = "TPLine_Sell";
            if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
            ObjectMove(0, name, 0, 0, zonalFinalTPLine_Sell);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrMediumPurple);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        }
    }
}

//+------------------------------------------------------------------+
//| 分割決済ラインを更新する                                         |
//+------------------------------------------------------------------+
void UpdateGroupSplitLines(PositionGroup &group)
{
    DeleteGroupSplitLines(group);
    if(!group.isActive || group.lockedInSplitCount <= 0) return;
    double tpPrice = group.stampedFinalTP;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) return;
    ArrayResize(group.splitPrices, group.lockedInSplitCount);
    ArrayResize(group.splitLineNames, group.lockedInSplitCount);
    ArrayResize(group.splitLineTimes, group.lockedInSplitCount);
    double step = MathAbs(tpPrice - group.averageEntryPrice) / group.lockedInSplitCount;
    for(int i = 0; i < group.lockedInSplitCount; i++)
    {
        group.splitPrices[i] = group.averageEntryPrice + (group.isBuy ? 1 : -1) * step * (i + 1);
        group.splitLineNames[i] = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_" + (string)i;
        group.splitLineTimes[i] = 0;
        ObjectCreate(0, group.splitLineNames[i], OBJ_HLINE, 0, 0, group.splitPrices[i]);
        ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_COLOR, group.isBuy ? clrGoldenrod : clrPurple);
        ObjectSetInteger(0, group.splitLineNames[i], OBJPROP_STYLE, STYLE_DOT);
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
//| グループの決済条件をチェックする                                 |
//+------------------------------------------------------------------+
void CheckExitForGroup(PositionGroup &group)
{
    if (!group.isActive) return;
    int effectiveSplitCount = group.lockedInSplitCount;
    if (group.splitsDone >= effectiveSplitCount || effectiveSplitCount <= 0) return;
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
                group.splitsDone++;
                if(InpBreakEvenAfterSplits > 0 && group.splitsDone >= InpBreakEvenAfterSplits)
                {
                    SetBreakEvenForGroup(group);
                }
            }
        }
    }
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
//| 新規エントリーを探す                                             |
//+------------------------------------------------------------------+
void CheckEntry()
{
    for(int i = 0; i < ArraySize(allLines); i++)
    {
        CheckLineSignals(allLines[i]);
    }
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, PERIOD_M5, 0, 1, rates) < 1) return;
    datetime currentTime = rates[0].time;
    bool hasBuySignal = false, hasSellSignal = false;
    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_ARROW);
        if(StringFind(name, InpArrowPrefix) != 0) continue;
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
        if(currentTime - objTime > InpDotTimeout) continue;
        if(StringFind(name, "_Buy") > 0) hasBuySignal = true;
        if(StringFind(name, "_Sell") > 0) hasSellSignal = true;
    }
    if((hasBuySignal || hasSellSignal) && (TimeCurrent() > lastTradeTime + 5))
    {
        if(InpEnableTimeFilter)
        {
            MqlDateTime time;
            TimeCurrent(time);
            int h = time.hour;
            bool outside = false;
            if(InpTradingHourStart > InpTradingHourEnd)
            {
                if(h < InpTradingHourStart && h >= InpTradingHourEnd) outside = true;
            }
            else
            {
                if(h < InpTradingHourStart || h >= InpTradingHourEnd) outside = true;
            }
            if(outside) return;
        }
        if(InpEnableVolatilityFilter)
        {
            double atr_buffer[100];
            if(CopyBuffer(h_atr, 0, 0, 100, atr_buffer) == 100)
            {
                double avg_atr = 0;
                for(int j = 0; j < 100; j++) avg_atr += atr_buffer[j];
                if(atr_buffer[0] > (avg_atr / 100) * InpAtrMaxRatio) return;
            }
        }
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick)) return;
        if(hasBuySignal && buyGroup.positionCount < InpMaxPositions)
        {
            ScoreComponentInfo info = CalculateMACDScore(true);
            if(info.total_score >= InpScore_Standard) PlaceOrder(true, tick.ask, info.total_score);
        }
        if(hasSellSignal && sellGroup.positionCount < InpMaxPositions)
        {
            ScoreComponentInfo info = CalculateMACDScore(false);
            if(info.total_score >= InpScore_Standard) PlaceOrder(false, tick.bid, info.total_score);
        }
    }
}

//+------------------------------------------------------------------+
//| 注文を発注する                                                   |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, int score)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = InpLotSize;
    req.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price = NormalizeDouble(price, _Digits);
    req.magic = InpMagicNumber;
    req.comment = (isBuy ? "Buy" : "Sell") + " (Score " + (string)score + ")";
    req.type_filling = ORDER_FILLING_IOC;
    if(!OrderSend(req, res))
    {
        Print("OrderSend error ", GetLastError());
    }
    else
    {
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
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ラインに対するシグナルを検出する                                 |
//+------------------------------------------------------------------+
void CheckLineSignals(Line &line)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, PERIOD_M5, 0, 2, rates) < 2) return;
    if(line.isBrokeUp && rates[0].close < line.price)
    {
        line.isBrokeUp = false;
    }
    if(line.isBrokeDown && rates[0].close > line.price)
    {
        line.isBrokeDown = false;
    }
    datetime currentTime = rates[0].time, prevBarTime = rates[1].time;
    double offset = InpSignalOffsetPips * g_pip;
    if(InpEntryMode == TOUCH_MODE)
    {
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(!line.isBrokeUp && rates[1].open < line.price && rates[1].close >= line.price)
            {
                if(!InpAllowOuterTouch)
                {
                    CreateSignalObject(InpArrowPrefix + "TouchBreak_Buy_" + line.name, prevBarTime, rates[1].low - offset, line.signalColor, InpTouchBreakUpCode, line.name + " タッチブレイク(買い)");
                }
                line.isBrokeUp = true;
            }
            if(!line.isBrokeUp && rates[1].open <= line.price && rates[1].high >= line.price && rates[1].close <= line.price && rates[1].low < line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Sell_" + line.name, prevBarTime, line.price + offset, line.signalColor, InpTouchReboundDownCode, line.name + " タッチ反発(売り)");
            }
        }
        else
        {
            if(!line.isBrokeDown && rates[1].open > line.price && rates[1].close <= line.price)
            {
                if(!InpAllowOuterTouch)
                {
                    CreateSignalObject(InpArrowPrefix + "TouchBreak_Sell_" + line.name, prevBarTime, rates[1].high + offset, line.signalColor, InpTouchBreakDownCode, line.name + " タッチブレイク(売り)");
                }
                line.isBrokeDown = true;
            }
            if(!line.isBrokeDown && rates[1].open >= line.price && rates[1].low <= line.price && rates[1].close >= line.price && rates[1].high > line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Buy_" + line.name, prevBarTime, line.price - offset, line.signalColor, InpTouchReboundUpCode, line.name + " タッチ反発(買い)");
            }
        }
    }
    else if(InpEntryMode == ZONE_MODE)
    {
        double zone_lower = line.price - InpZonePips * g_pip, zone_upper = line.price + InpZonePips * g_pip;
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(rates[0].close >= line.price && rates[0].close < zone_upper) line.isInZone = true;
            else if(rates[0].close >= zone_upper || rates[0].close < line.price) line.isInZone = false;
            if(line.isInZone && rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix+"ZoneRebound_Sell_"+line.name,currentTime,line.price+offset,line.signalColor,InpZoneReboundSellCode, line.name + " ゾーン内反発(売り)");
                line.isInZone=false;
            }
            if(rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix+"VReversal_Sell_"+line.name,currentTime,line.price+offset,line.signalColor,InpVReversalSellCode, line.name + " V字回復(売り)");
            }
            if(InpBreakMode)
            {
                if(rates[0].close > zone_upper) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].high >= line.price && rates[0].close < line.price)
                {
                    CreateSignalObject(InpArrowPrefix+"Retest_Sell_"+line.name,currentTime,line.price+offset,line.signalColor,InpRetestSellCode, line.name + " B&R(売り)");
                    line.waitForRetest=false;
                }
            }
        }
        else
        {
            if(rates[0].close <= line.price && rates[0].close > zone_lower) line.isInZone = true;
            else if(rates[0].close <= zone_lower || rates[0].close > line.price) line.isInZone = false;
            if(line.isInZone && rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix+"ZoneRebound_Buy_"+line.name,currentTime,line.price-offset,line.signalColor,InpZoneReboundBuyCode, line.name + " ゾーン内反発(買い)");
                line.isInZone=false;
            }
            if(rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix+"VReversal_Buy_"+line.name,currentTime,line.price-offset,line.signalColor,InpVReversalBuyCode, line.name + " V字回復(買い)");
            }
            if(InpBreakMode)
            {
                if(rates[0].close < zone_lower) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].low <= line.price && rates[0].close > line.price)
                {
                    CreateSignalObject(InpArrowPrefix+"Retest_Buy_"+line.name,currentTime,line.price-offset,line.signalColor,InpRetestBuyCode, line.name + " B&R(買い)");
                    line.waitForRetest=false;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ライン情報を更新する                                             |
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
        for(int i = 0; i < 6; i++)
        {
            if(i >= 2 && !InpShowS2R2) continue;
            if(i >= 4 && !InpShowS3R3) continue;
            Line line;
            line.name = p_names[i];
            line.price = p_prices[i];
            line.type = p_types[i];
            line.signalColor = p_colors[i];
            int size = ArraySize(allLines);
            ArrayResize(allLines, size + 1);
            allLines[size] = line;
        }
    }
    DrawPivotLine();
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick))
    {
        for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
        {
            string objName = ObjectName(0, i, -1, OBJ_TREND);
            if(StringFind(objName, "ManualTrend_") != 0) continue;
            string obj_text = ObjectGetString(0, objName, OBJPROP_TEXT);
            if(StringFind(obj_text, "-Broken") >= 0) continue;
            Line m_line;
            m_line.name = "Manual_" + StringSubstr(objName, StringFind(objName, "_", 0) + 1);
            m_line.price = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
            m_line.signalColor = (color)ObjectGetInteger(0, objName, OBJPROP_COLOR);
            m_line.type = (m_line.price > tick.ask) ? LINE_TYPE_RESISTANCE : LINE_TYPE_SUPPORT;
            int size = ArraySize(allLines);
            ArrayResize(allLines, size + 1);
            allLines[size] = m_line;
        }
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
//| ピボットラインを描画する                                         |
//+------------------------------------------------------------------+
void DrawPivotLine()
{
    datetime new_start_time = iTime(_Symbol, InpPivotPeriod, 0);
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, InpLinePrefix_Pivot) == 0)
        {
            if(ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) == true)
            {
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, name, OBJPROP_TIME, 1, new_start_time);
            }
        }
    }
    string ts = TimeToString(new_start_time, TIME_DATE|TIME_MINUTES);
    StringReplace(ts, ":", "_");
    StringReplace(ts, ".", "_");
    double p_prices[] = {s1, r1, s2, r2, s3, r3};
    color p_colors[] = {(color)CLR_S1, (color)CLR_R1, (color)CLR_S2, (color)CLR_R2, (color)CLR_S3, (color)CLR_R3};
    string p_names[] = {"S1", "R1", "S2", "R2", "S3", "R3"};
    for(int i=0; i<6; i++)
    {
        if(i >= 2 && !InpShowS2R2) continue;
        if(i >= 4 && !InpShowS3R3) continue;
        string name = InpLinePrefix_Pivot + p_names[i] + "_" + ts;
        if(ObjectFind(0, name) < 0)
        {
            if(ObjectCreate(0, name, OBJ_TREND, 0, new_start_time, p_prices[i], new_start_time + PeriodSeconds(InpPivotPeriod), p_prices[i]))
            {
                ObjectSetInteger(0, name, OBJPROP_COLOR, p_colors[i]);
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
                ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
            }
        }
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
//| 個別モード：新規ポジションの分割決済データを準備する             |
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
    int dynamicSplitCount = InpSplitCount;
    if(InpEnableDynamicSplits && newSplit.score >= InpScore_High)
    {
        dynamicSplitCount += InpHighScoreSplit_Add;
    }
    if(dynamicSplitCount > 0)
    {
        ArrayResize(newSplit.splitPrices, dynamicSplitCount);
        ArrayResize(newSplit.splitLineNames, dynamicSplitCount);
        ArrayResize(newSplit.splitLineTimes, dynamicSplitCount);
        double step = priceDiff / dynamicSplitCount;
        for(int i = 0; i < dynamicSplitCount; i++)
        {
            newSplit.splitPrices[i] = newSplit.isBuy ? newSplit.entryPrice + step * (i + 1) : newSplit.entryPrice - step * (i + 1);
            string lineName = "SplitLine_" + (string)ticket + "_" + (string)i;
            newSplit.splitLineNames[i] = lineName;
            newSplit.splitLineTimes[i] = 0;
            ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, newSplit.splitPrices[i]);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, newSplit.isBuy ? clrGoldenrod : clrPurple);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
        }
    }
    int size = ArraySize(splitPositions);
    ArrayResize(splitPositions, size + 1);
    splitPositions[size] = newSplit;
}

//+------------------------------------------------------------------+
//| 個別モード：分割決済を実行する                                   |
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
    split.splitLineTimes[splitIndex] = TimeCurrent();
    string lineName = split.splitLineNames[splitIndex];
    double splitPrice = split.splitPrices[splitIndex];
    if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
    ObjectCreate(0, lineName, OBJ_TREND, 0, split.openTime, splitPrice, TimeCurrent(), splitPrice);
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, split.isBuy ? clrLightGoldenrod : clrLightBlue);
    ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
    return true;
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
//| 指定されたチケットのポジションを決済する                         |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    if(PositionSelectByTicket(ticket))
    {
        req.action = TRADE_ACTION_DEAL;
        req.position = ticket;
        req.symbol = _Symbol;
        req.volume = PositionGetDouble(POSITION_VOLUME);
        req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        req.price = (req.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        if(!OrderSend(req, res)) PrintFormat("ポジション #%d の決済に失敗しました。エラー: %d", ticket, GetLastError());
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
//| 指定されたポジションのSLを設定する                               |
//+------------------------------------------------------------------+
bool SetBreakEven(ulong ticket, double entryPrice)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    if(PositionSelectByTicket(ticket))
    {
        double currentSL = PositionGetDouble(POSITION_SL);
        if(MathAbs(currentSL - entryPrice) < g_pip)
        {
            return true;
        }
        req.action = TRADE_ACTION_SLTP;
        req.position = ticket;
        req.symbol = _Symbol;
        req.sl = NormalizeDouble(entryPrice, _Digits);
        req.tp = PositionGetDouble(POSITION_TP);
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
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 手動ラインの状態を監視し、ブレイクを検出する                     |
//+------------------------------------------------------------------+
void ManageManualLines()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, "ManualTrend_") != 0) continue;
        string text = ObjectGetString(0, name, OBJPROP_TEXT);
        if(StringFind(text, "-Broken") >= 0) continue;
        double price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
        bool is_broken = (StringFind(text, "Resistance") >= 0 && rates[1].close > price) || (StringFind(text, "Support") >= 0 && rates[1].close < price);
        if(is_broken)
        {
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, rates[1].time);
            ObjectSetString(0, name, OBJPROP_TEXT, text + "-Broken");
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
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
//| 手動で描画したラインをすべて削除する                             |
//+------------------------------------------------------------------+
void ClearManualLines()
{
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, "ManualTrend_") == 0) ObjectDelete(0, name);
    }
    UpdateLines();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| クリックした位置に手動ラインを描画する                           |
//+------------------------------------------------------------------+
void DrawManualTrendLine(double price, datetime time)
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    color line_color = (price < tick.ask) ? p_ManualSupport_Color : p_ManualResist_Color;
    string role_text = (price < tick.ask) ? "Support" : "Resistance";
    string name = "ManualTrend_" + TimeToString(TimeCurrent(), TIME_SECONDS);
    if(ObjectCreate(0, name, OBJ_TREND, 0, time, price, time + PeriodSeconds(_Period), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
        ObjectSetString(0, name, OBJPROP_TEXT, role_text);
        ObjectSetInteger(0, name, OBJPROP_STYLE, p_ManualLine_Style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, p_ManualLine_Width);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
        UpdateLines();
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
//| 新しい足ができたかチェックする                                   |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    int index = (timeframe == PERIOD_M5) ? 0 : 1;
    if(timeframe != PERIOD_M5 && timeframe != InpPivotPeriod) return false;
    datetime currentTime = iTime(_Symbol, timeframe, 0);
    if(currentTime != lastBar[index])
    {
        lastBar[index] = currentTime;
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
//| 情報パネルの管理 (作成と更新) (最終調整版)
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
    AddPanelLine(panel_lines, "              [ Buy / Sell ]");
    AddPanelLine(panel_lines, "Divergence:   [ " + (string)(buy_info.divergence ? "✔" : "-") + " / " + (string)(sell_info.divergence ? "✔" : "-") + " ]");
    string zero_buy  = (string)(buy_info.mid_zeroline ? "✔" : "-") + "/" + (string)(buy_info.long_zeroline ? "✔" : "-");
    string zero_sell = (string)(sell_info.mid_zeroline ? "✔" : "-") + "/" + (string)(sell_info.long_zeroline ? "✔" : "-");
    AddPanelLine(panel_lines, "Zero(M/L):    [ " + zero_buy + " / " + zero_sell + " ]");
    string angle_buy = (string)(buy_info.exec_angle ? "✔" : "-") + "/" + (string)(buy_info.mid_angle ? "✔" : "-");
    string angle_sell= (string)(sell_info.exec_angle ? "✔" : "-") + "/" + (string)(sell_info.mid_angle ? "✔" : "-");
    AddPanelLine(panel_lines, "Angle(E/M):   [ " + angle_buy + " / " + angle_sell + " ]");
    string hist_buy = (string)(buy_info.exec_hist ? "✔" : "-") + "/" + (string)(buy_info.mid_hist_sync ? "✔" : "-");
    string hist_sell= (string)(sell_info.exec_hist ? "✔" : "-") + "/" + (string)(sell_info.mid_hist_sync ? "✔" : "-");
    AddPanelLine(panel_lines, "Hist(E/M):    [ " + hist_buy + " / " + hist_sell + " ]");
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

    int line_height = 12;
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
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
            
            // ★★★ ロジック追加: 右側のコーナーが選択されたら、文字を右揃えにする ★★★
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
//| MACD指標に基づく取引スコアを計算                                 |
//+------------------------------------------------------------------+
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal)
{
    ScoreComponentInfo info;
    ZeroMemory(info);
    double exec_main[], exec_signal[];
    double mid_main[], mid_signal[];
    double long_main[];
    ArraySetAsSeries(exec_main, true);
    ArraySetAsSeries(exec_signal, true);
    ArraySetAsSeries(mid_main, true);
    ArraySetAsSeries(mid_signal, true);
    ArraySetAsSeries(long_main, true);
    if(CopyBuffer(h_macd_exec, 0, 0, 30, exec_main) < 30 || CopyBuffer(h_macd_exec, 1, 0, 30, exec_signal) < 30) return info;
    if(CopyBuffer(h_macd_mid, 0, 0, 4, mid_main) < 4 || CopyBuffer(h_macd_mid, 1, 0, 1, mid_signal) < 1) return info;
    if(CopyBuffer(h_macd_long, 0, 0, 1, long_main) < 1) return info;
    if(is_buy_signal)
    {
        if(CheckMACDDivergence(true, h_macd_exec)) info.divergence = true;
        if(mid_main[0] > 0)  info.mid_zeroline = true;
        if(long_main[0] > 0) info.long_zeroline = true;
        if(exec_main[0] - exec_main[3] > 0) info.exec_angle = true;
        if(mid_main[0] - mid_main[3] > 0)   info.mid_angle = true;
        double h0=exec_main[0]-exec_signal[0], h1=exec_main[1]-exec_signal[1], h2=exec_main[2]-exec_signal[2];
        if(h0 > h1 && h1 > 0 && h2 > 0) info.exec_hist = true;
        if(mid_main[0] - mid_signal[0] > 0) info.mid_hist_sync = true;
    }
    else
    {
        if(CheckMACDDivergence(false, h_macd_exec)) info.divergence = true;
        if(mid_main[0] < 0)  info.mid_zeroline = true;
        if(long_main[0] < 0) info.long_zeroline = true;
        if(exec_main[0] - exec_main[3] < 0) info.exec_angle = true;
        if(mid_main[0] - mid_main[3] < 0)   info.mid_angle = true;
        double h0=exec_main[0]-exec_signal[0], h1=exec_main[1]-exec_signal[1], h2=exec_main[2]-exec_signal[2];
        if(h0 < h1 && h1 < 0 && h2 < 0) info.exec_hist = true;
        if(mid_main[0] - mid_signal[0] < 0) info.mid_hist_sync = true;
    }
    if(info.divergence)   info.total_score += 3;
    if(info.mid_zeroline)  info.total_score += 2;
    if(info.long_zeroline) info.total_score += 3;
    if(info.exec_angle)    info.total_score += 1;
    if(info.mid_angle)     info.total_score += 2;
    if(info.exec_hist)     info.total_score += 1;
    if(info.mid_hist_sync) info.total_score += 1;
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