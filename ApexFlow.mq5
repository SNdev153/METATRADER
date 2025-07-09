//+------------------------------------------------------------------+
//|                                ApexFlow.mq5                      |
//|                         (ZoneEntry + ZephyrSplit)                |
//|                         Final Complete Version: 1.0               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.0"

// --- ラインカラー定数 (from ZoneEntryEA)
#define CLR_S1 2970272
#define CLR_R1 13434880
#define CLR_S2 36095
#define CLR_R2 16748574
#define CLR_S3 42495
#define CLR_R3 15453831

// --- ボタン名定義 (from ZephyrSplitEA)
#define BUTTON_BUY_CLOSE_ALL  "Button_BuyCloseAll"
#define BUTTON_SELL_CLOSE_ALL "Button_SellCloseAll"
#define BUTTON_ALL_CLOSE      "Button_AllClose"
#define BUTTON_RESET_BUY_TP   "Button_ResetBuyTP"
#define BUTTON_RESET_SELL_TP  "Button_ResetSellTP"

// ==================================================================
// --- ENUM / 構造体定義 (両EAから統合) ---
// ==================================================================

enum ENUM_LINE_TYPE
{
    LINE_TYPE_SUPPORT,
    LINE_TYPE_RESISTANCE
};

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

struct PositionInfo
{
    long   ticket;
    int    score;
    double entryPrice;
    double lotSize;
    bool   isBuy;
    datetime openTime;
};

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

enum ENUM_EXIT_LOGIC {
    EXIT_FIFO,
    EXIT_UNFAVORABLE,
    EXIT_FAVORABLE
};

enum ENUM_TP_MODE {
    MODE_ZIGZAG,
    MODE_PIVOT,
    MODE_MANUAL
};

enum ENUM_POSITION_MODE {
    MODE_AGGREGATE,
    MODE_INDIVIDUAL
};

struct SplitData {
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

struct PositionGroup {
    bool     isBuy;
    bool     isActive;
    double   averageEntryPrice;
    double   totalLotSize;
    double   initialTotalLotSize;
    ulong    positionTickets[];
    double   splitPrices[];
    string   splitLineNames[];
    datetime splitLineTimes[];
    int      splitsDone;
    datetime openTime;
    double   stampedFinalTP;
    double   averageScore;
    int      highestScore;
    int      positionCount;
};

struct SortablePosition {
    ulong  ticket;
    double openPrice;
};

// ==================================================================
// --- 入力パラメータ (完全版) ---
// ==================================================================

input group "=== [重要] 基本取引設定 ===";
input int    InpMagicNumber        = 123456;      // マジックナンバー
input double InpLotSize            = 0.1;         // ロットサイズ
input int    InpMaxPositions       = 5;           // 同方向の最大ポジション数

input group "=== [Zone] エントリーロジック設定 ===";
enum ENTRY_MODE { TOUCH_MODE, ZONE_MODE };        
input ENTRY_MODE InpEntryMode        = ZONE_MODE;  // エントリーモード
input bool   InpBreakMode          = true;        // ブレイクモード
input double InpZonePips           = 50.0;        // ゾーン幅 (pips)
input int    InpDotTimeout         = 600;         // ドット/矢印有効期限 (秒)

input group "--- [Zone] 動的フィルター設定 ---";
input bool   InpEnableTimeFilter   = true;        // 取引時間フィルターを有効にする
input int    InpTradingHourStart   = 15;          // 取引開始時間 (サーバー時間)
input int    InpTradingHourEnd     = 25;          // 取引終了時間 (サーバー時間, 25 = 翌午前1時)
input bool   InpEnableVolatilityFilter = true;    // ボラティリティフィルターを有効にする
input double InpAtrMaxRatio        = 1.5;         // エントリーを許可する最大ATR倍率

input group "=== [Zone] MACDスコアリング設定 ===";
input int    InpScore_Standard       = 4;         // 標準エントリーの最低スコア
input int    InpScore_High         = 6;           // ロットアップエントリーの最低スコア

input group "--- [Zone] 執行足MACD (トリガー) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Exec   = PERIOD_CURRENT; // 時間足 (PERIOD_CURRENT=チャートの時間足)
input int             InpMACD_Fast_Exec   = 12;           // Fast EMA
input int             InpMACD_Slow_Exec   = 26;           // Slow EMA
input int             InpMACD_Signal_Exec = 9;            // Signal SMA

input group "--- [Zone] 中期足MACD (コンテキスト) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Mid    = PERIOD_H1;      // 時間足
input int             InpMACD_Fast_Mid    = 12;           // Fast EMA
input int             InpMACD_Slow_Mid    = 26;           // Slow EMA
input int             InpMACD_Signal_Mid  = 9;            // Signal SMA

input group "--- [Zone] 長期足MACD (コンファメーション) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Long   = PERIOD_H4;      // 時間足
input int             InpMACD_Fast_Long   = 12;           // Fast EMA
input int             InpMACD_Slow_Long   = 26;           // Slow EMA
input int             InpMACD_Signal_Long = 9;            // Signal SMA

input group "=== [Zephyr] 決済ロジック設定 ===";
input ENUM_POSITION_MODE InpPositionMode     = MODE_AGGREGATE; // ポジション管理モード
input ENUM_EXIT_LOGIC    InpExitLogic        = EXIT_UNFAVORABLE; // 決済ロジック
input int                InpSplitCount       = 5;              // 分割決済の回数
input double             InpExitBufferPips   = 1.0;            // 決済バッファ (pips)
input int                InpBreakEvenAfterSplits = 2;          // ブレークイーブン発動までの分割回数
input double             InpTPProximityPips  = 100.0;          // TP近接判定距離 (pips)
input ENUM_TP_MODE       InpTPLineMode       = MODE_ZIGZAG;    // TPライン設定モード

input group "--- [Zephyr] ★スコア連動の動的TP設定 ---";
input double             InpHighSchoreTpRratio = 1.5;          // 高スコア時のTP倍率

input group "--- [Zephyr] 自動TP計算: ZigZag設定 ---";
input int                InpZigzagDepth      = 12;             // ZigZagの深度
input int                InpZigzagDeviation  = 5;              // ZigZagの偏差
input int                InpZigzagBackstep   = 3;              // ZigZagのバックステップ

input group "=== UIとオブジェクト設定 ===";
input bool   InpShowInfoPanel        = true;       // 情報パネルを表示する
input int    p_panel_x_offset        = 10;         // パネルX位置
input int    p_panel_y_offset        = 130;        // パネルY位置
input bool   InpEnableButtons        = true;       // ボタンを有効にする

input group "--- [Zone] ピボットと手動ライン設定 ---";
input bool   InpUsePivotLines      = true;        // ピボットラインを使用する
input ENUM_TIMEFRAMES InpPivotPeriod      = PERIOD_H1; // ピボット時間足
input bool            InpShowS2R2         = true;  // S2/R2ラインを表示
input bool            InpShowS3R3         = true;  // S3/R3ラインを表示
input bool            InpAllowOuterTouch  = false; // ライン外側からのタッチ/ブレイク検知を許可
input color           p_ManualSupport_Color = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color  = clrTomato;     // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style    = STYLE_DOT;     // 手動ラインのスタイル
input int             p_ManualLine_Width    = 2;             // 手動ラインの太さ

input group "--- [Zone] オブジェクトとシグナルの外観 ---";
input bool   InpShowDivergenceSignals = true;               // ダイバージェンスサインを表示する
input string InpDivSignalPrefix      = "DivSignal_";       // サインのオブジェクト名プレフィックス
input color  InpBullishDivColor      = clrDeepSkyBlue;     // 強気ダイバージェンスの色
input color  InpBearishDivColor      = clrHotPink;         // 弱気ダイバージェンスの色
input int    InpDivSymbolCode        = 159;                // サインのシンボルコード (159 = ●)
input int    InpDivSymbolSize        = 8;                  // サインの大きさ
input double InpDivSymbolOffsetPips  = 15.0;               // サインの描画オフセット (pips)
input string InpDotPrefix           = "Dot_";              // ドットプレフィックス
input string InpArrowPrefix         = "Trigger_";          // 矢印プレフィックス
input int    InpSignalWidth         = 2;                   // シグナルの太さ
input int    InpSignalFontSize      = 10;                  // シグナルの大きさ
input double InpSignalOffsetPips    = 2.0;                 // シグナルの描画オフセット (pips)
input int    InpTouchBreakUpCode    = 221;                 // タッチブレイク買いのシンボルコード
input int    InpTouchBreakDownCode  = 222;                 // タッチブレイク売りのシンボルコード
input int    InpTouchReboundUpCode  = 233;                 // タッチひげ反発買いのシンボルコード
input int    InpTouchReboundDownCode= 234;                 // タッチひげ反発売りのシンボルコード
input int    InpZoneReboundBuyCode  = 231;                 // ゾーン内反発 (買い) のシンボルコード
input int    InpZoneReboundSellCode = 232;                 // ゾーン内反発 (売り) のシンボルコード
input int    InpVReversalBuyCode    = 233;                 // V字回復 (買い) のシンボルコード
input int    InpVReversalSellCode   = 234;                 // V字回復 (売り) のシンボルコード
input int    InpRetestBuyCode       = 110;                 // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode      = 111;                 // ブレイク＆リテスト (売り) のシンボルコード

// ==================================================================
// --- グローバル変数 (完全版) ---
// ==================================================================

// --- from ZoneEntryEA ---
double   g_pip;
Line     allLines[];
PositionInfo g_managedPositions[];
int      h_macd_exec, h_macd_mid, h_macd_long, h_atr;
datetime lastBar[2];
datetime lastArrowTime = 0;
bool     g_isDrawingMode = false;
string   g_buttonName           = "DrawManualLineButton";
string   g_clearButtonName      = "ClearSignalsButton";
string   g_clearLinesButtonName = "ClearLinesButton";
string   g_panelPrefix          = "InfoPanel_";
double   s1, r1, s2, r2, s3, r3, pivot;

// --- from ZephyrSplitEA ---
PositionGroup buyGroup;
PositionGroup sellGroup;
SplitData     splitPositions[];
int           zigzagHandle;
double        zonalFinalTPLine_Buy, zonalFinalTPLine_Sell;
bool          isBuyTPManuallyMoved = false, isSellTPManuallyMoved = false;

// --- 共通 ---
datetime lastTradeTime;

// ==================================================================
// --- 関数のプロトタイプ宣言 ---
// ==================================================================
// --- 初期化・終了・メインループ ---
int  OnInit();
void OnDeinit(const int reason);
void OnTick();
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);

// --- エントリーロジック関連 (ZoneEntry) ---
void CheckEntry();
void CheckLineSignals(Line &line);
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal);
bool CheckMACDDivergence(bool is_buy_signal, int macd_handle);
void PlaceOrder(bool isBuy, double price, double sl, double tp, string comment, int score);

// --- 決済ロジック関連 (Zephyr) ---
void ManagePositionGroups();
void UpdateZones();
void UpdateGroupSplitLines(PositionGroup &group);
void DeleteGroupSplitLines(PositionGroup &group);
void CheckExitForGroup(PositionGroup &group);
void CloseAllPositionsInGroup(PositionGroup &group);
bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose);
void SetBreakEvenForGroup(PositionGroup &group);
bool SetBreakEven(ulong ticket, double entryPrice);
void DetectNewEntrances();
void CheckExits();
void AddSplitData(ulong ticket);
bool ExecuteSplitExit(ulong ticket, double lot, SplitData &split, int splitIndex);
void ClosePosition(ulong ticket);

// --- UI・オブジェクト関連 ---
void ManageInfoPanel();
void ManageManualLines();
void UpdateLines();
void DrawPivotLine();
void CalculatePivot();
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string msg);
void DrawDivergenceSignal(datetime time, double price, color clr);
void UpdateButtonState();
void ClearSignalObjects();
void ClearManualLines();
void DrawManualTrendLine(double price, datetime time);
bool CreateApexButton(string name, int x, int y, int width, int height, string text, color clr);
void CreateManualLineButton();
void CreateClearButton();
void CreateClearLinesButton();
void InitGroup(PositionGroup &group, bool isBuy);

// --- ユーティリティ ---
bool IsNewBar(ENUM_TIMEFRAMES timeframe);
void AddPanelLine(string &lines[], const string text);
void SyncManagedPositions();

// ==================================================================
// --- 主要関数 (OnInit, OnDeinit, OnTick, OnChartEvent) ---
// ==================================================================

//+------------------------------------------------------------------+
//| エキスパート初期化関数: EAの初期設定とインジケータの準備        |
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

    if(InpPositionMode == MODE_AGGREGATE)
    {
        InitGroup(buyGroup, true);
        InitGroup(sellGroup, false);
    }
    else
    {
        ArrayResize(splitPositions, 0);
    }

    UpdateLines();
    if(InpUsePivotLines)
    {
        DrawPivotLine();
    }
    CreateManualLineButton();
    CreateClearButton();
    CreateClearLinesButton();
    
    if(InpEnableButtons)
    {
        CreateApexButton(BUTTON_BUY_CLOSE_ALL, 140, 50, 100, 20, "BUY 全決済", clrDodgerBlue);
        CreateApexButton(BUTTON_SELL_CLOSE_ALL, 140, 75, 100, 20, "SELL 全決済", clrTomato);
        CreateApexButton(BUTTON_ALL_CLOSE, 245, 50, 100, 20, "全決済", clrGray);
        CreateApexButton(BUTTON_RESET_BUY_TP, 245, 75, 100, 20, "BUY TPリセット", clrGoldenrod);
        CreateApexButton(BUTTON_RESET_SELL_TP, 245, 100, 100, 20, "SELL TPリセット", clrGoldenrod);
    }

    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);
    EventSetMillisecondTimer(100);

    Print("ApexFlowEA v1.0 初期化完了");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数: リソースの解放とオブジェクトの削除    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectsDeleteAll(0, g_buttonName);
    ObjectsDeleteAll(0, g_clearButtonName);
    ObjectsDeleteAll(0, g_clearLinesButtonName);
    ObjectsDeleteAll(0, g_panelPrefix);
    ObjectsDeleteAll(0, "Pivot_");
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
//| エキスパートティック関数: 各ティックで実行されるメイン処理      |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewBar(InpPivotPeriod))
    {
        UpdateLines();
        if(InpUsePivotLines)
        {
            DrawPivotLine();
        }
    }

    if(IsNewBar(PERIOD_M5))
    {
        SyncManagedPositions();
        UpdateZones();
        if(InpPositionMode == MODE_AGGREGATE)
        {
            ManagePositionGroups();
            CheckExitForGroup(buyGroup);
            CheckExitForGroup(sellGroup);
        }
        else
        {
            DetectNewEntrances();
            CheckExits();
        }
        ManageInfoPanel();
        ManageManualLines();
        CheckEntry();
    }
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数: ボタンクリックやドラッグイベントを処理 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == g_buttonName)
        {
            g_isDrawingMode = !g_isDrawingMode;
            UpdateButtonState();
            return;
        }
        if(sparam == g_clearButtonName)
        {
            ClearSignalObjects();
            return;
        }
        if(sparam == g_clearLinesButtonName)
        {
            ClearManualLines();
            return;
        }
    }
    
    if(id == CHARTEVENT_CLICK && g_isDrawingMode)
    {
        int subWindow;
        datetime time;
        double price;
        if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, time, price))
        {
            if(subWindow == 0) DrawManualTrendLine(price, time);
        }
        return;
    }

    if(id == CHARTEVENT_OBJECT_DRAG)
    {
        bool isBuyLine = (sparam == "TPLine_Buy");
        bool isSellLine = (sparam == "TPLine_Sell");

        if(isBuyLine || isSellLine)
        {
            double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0);
            
            if(isBuyLine){
                if(!isBuyTPManuallyMoved || zonalFinalTPLine_Buy != newPrice)
                {
                    isBuyTPManuallyMoved = true;
                    zonalFinalTPLine_Buy = newPrice;
                    ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                    if(buyGroup.isActive)
                    {
                        buyGroup.stampedFinalTP = newPrice;
                        UpdateGroupSplitLines(buyGroup);
                    }
                }
            }
            else
            {
                if(!isSellTPManuallyMoved || zonalFinalTPLine_Sell != newPrice)
                {
                    isSellTPManuallyMoved = true;
                    zonalFinalTPLine_Sell = newPrice;
                    ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                    if(sellGroup.isActive)
                    {
                        sellGroup.stampedFinalTP = newPrice;
                        UpdateGroupSplitLines(sellGroup);
                    }
                }
            }
            ChartRedraw();
        }
    }

    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == BUTTON_BUY_CLOSE_ALL)
        {
            if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup);
            return;
        }
        if(sparam == BUTTON_SELL_CLOSE_ALL)
        {
            if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup);
            return;
        }
        if(sparam == BUTTON_ALL_CLOSE)
        {
            if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup);
            if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup);
            return;
        }
        if(sparam == BUTTON_RESET_BUY_TP)
        {
            isBuyTPManuallyMoved = false;
            UpdateZones();
            if(buyGroup.isActive)
            {
                buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
                UpdateGroupSplitLines(buyGroup);
            }
            ChartRedraw();
            return;
        }
        if(sparam == BUTTON_RESET_SELL_TP)
        {
            isSellTPManuallyMoved = false;
            UpdateZones();
            if(sellGroup.isActive)
            {
                sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
                UpdateGroupSplitLines(sellGroup);
            }
            ChartRedraw();
            return;
        }
    }
}

// ==================================================================
// --- ヘルパー関数群 ---
// ==================================================================

//+------------------------------------------------------------------+
//| チャート上にカスタムボタンを作成                             |
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
    return true;
}

//+------------------------------------------------------------------+
//| 手動ライン描画用のボタンを作成                               |
//+------------------------------------------------------------------+
void CreateManualLineButton()
{
    CreateApexButton(g_buttonName, 10, 50, 120, 20, "手動ライン描画 OFF", C'220,220,220');
}

//+------------------------------------------------------------------+
//| シグナルオブジェクト消去用のボタンを作成                     |
//+------------------------------------------------------------------+
void CreateClearButton()
{
    CreateApexButton(g_clearButtonName, 10, 75, 120, 20, "シグナル消去", C'255,228,225');
}

//+------------------------------------------------------------------+
//| 手動ライン消去用のボタンを作成                               |
//+------------------------------------------------------------------+
void CreateClearLinesButton()
{
    CreateApexButton(g_clearLinesButtonName, 10, 100, 120, 20, "手動ライン消去", C'225,240,255');
}

//+------------------------------------------------------------------+
//| 情報パネルにテキスト行を追加                                 |
//+------------------------------------------------------------------+
void AddPanelLine(string &lines[], const string text)
{
    int size = ArraySize(lines);
    ArrayResize(lines, size + 1);
    lines[size] = text;
}

//+------------------------------------------------------------------+
//| 管理中のポジションを現在の状態に同期                         |
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
//| 情報パネルを表示・更新                                       |
//+------------------------------------------------------------------+
void ManageInfoPanel()
{
    if(!InpShowInfoPanel)
    {
        ObjectsDeleteAll(0, g_panelPrefix);
        return;
    }
    string panel_lines[];
    AddPanelLine(panel_lines, "▶ ApexFlowEA v1.0");
    AddPanelLine(panel_lines, " Magic: " + (string)InpMagicNumber);
    AddPanelLine(panel_lines, " Spread: " + (string)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) + " points");
    AddPanelLine(panel_lines, "──────────────────────");
    ScoreComponentInfo buy_info  = CalculateMACDScore(true);
    ScoreComponentInfo sell_info = CalculateMACDScore(false);
    AddPanelLine(panel_lines, "--- Score Details ---");
    AddPanelLine(panel_lines, "             [ Buy / Sell ]");
    AddPanelLine(panel_lines, "Divergence:  [ " + (string)(buy_info.divergence ? "✔" : "-") + " / " + (string)(sell_info.divergence ? "✔" : "-") + " ]");
    string zero_buy  = (string)(buy_info.mid_zeroline ? "✔" : "-") + "/" + (string)(buy_info.long_zeroline ? "✔" : "-");
    string zero_sell = (string)(sell_info.mid_zeroline ? "✔" : "-") + "/" + (string)(sell_info.long_zeroline ? "✔" : "-");
    AddPanelLine(panel_lines, "Zero(M/L):   [ " + zero_buy + " / " + zero_sell + " ]");
    string angle_buy = (string)(buy_info.exec_angle ? "✔" : "-") + "/" + (string)(buy_info.mid_angle ? "✔" : "-");
    string angle_sell= (string)(sell_info.exec_angle ? "✔" : "-") + "/" + (string)(sell_info.mid_angle ? "✔" : "-");
    AddPanelLine(panel_lines, "Angle(E/M):  [ " + angle_buy + " / " + angle_sell + " ]");
    string hist_buy = (string)(buy_info.exec_hist ? "✔" : "-") + "/" + (string)(buy_info.mid_hist_sync ? "✔" : "-");
    string hist_sell= (string)(sell_info.exec_hist ? "✔" : "-") + "/" + (string)(sell_info.mid_hist_sync ? "✔" : "-");
    AddPanelLine(panel_lines, "Hist(E/M):   [ " + hist_buy + " / " + hist_sell + " ]");
    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, "Forecast: Buy " + (string)buy_info.total_score + " / Sell " + (string)sell_info.total_score);
    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, "Buy Group: " + (string)buyGroup.positionCount + " pos, " + DoubleToString(buyGroup.totalLotSize, 2) + " lots");
    AddPanelLine(panel_lines, "Sell Group: " + (string)sellGroup.positionCount + " pos, " + DoubleToString(sellGroup.totalLotSize, 2) + " lots");
    
    int line_height = 12;
    for(int i = 0; i < ArraySize(panel_lines); i++)
    {
        string obj_name = g_panelPrefix + (string)i;
        int y_pos = p_panel_y_offset + (i * line_height);
        if(ObjectFind(0, obj_name) < 0)
        {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, p_panel_x_offset);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetString(0, obj_name, OBJPROP_FONT, "Lucida Console");
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
        }
        ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y_pos);
        ObjectSetString(0, obj_name, OBJPROP_TEXT, panel_lines[i]);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrLightGray);
    }
    for(int i = ArraySize(panel_lines); i < 30; i++)
    {
        string obj_name = g_panelPrefix + (string)i;
        if(ObjectFind(0, obj_name) >= 0) ObjectDelete(0, obj_name);
        else break;
    }
}

//+------------------------------------------------------------------+
//| MACD指標に基づく取引スコアを計算                             |
//+------------------------------------------------------------------+
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal)
{
    ScoreComponentInfo info;
    ZeroMemory(info);
    double exec_main[], exec_signal[];
    double mid_main[], mid_signal[];
    double long_main[];
    ArraySetAsSeries(exec_main, true); ArraySetAsSeries(exec_signal, true);
    ArraySetAsSeries(mid_main, true); ArraySetAsSeries(mid_signal, true);
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
//| MACDのダイバージェンスを検出                                 |
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
        for(int i = 1; i < check_bars - 1; i++) {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low) {
                if(p1_idx == -1) { p1_idx = i; }
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        if(p1_idx > 0 && p2_idx > 0) {
            if(rates[p1_idx].low < rates[p2_idx].low && macd_main[p1_idx] > macd_main[p2_idx]) {
                double price = rates[p1_idx].low - InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBullishDivColor);
                return true;
            }
        }
    }
    else
    {
        for(int i = 1; i < check_bars - 1; i++) {
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high) {
                if(p1_idx == -1) { p1_idx = i; }
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        if(p1_idx > 0 && p2_idx > 0) {
            if(rates[p1_idx].high > rates[p2_idx].high && macd_main[p1_idx] < macd_main[p2_idx]) {
                double price = rates[p1_idx].high + InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBearishDivColor);
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| エントリーシグナルを検出し、取引条件を評価                   |
//+------------------------------------------------------------------+
void CheckEntry()
{
    UpdateLines();
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
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
        if(currentTime - objTime > InpDotTimeout) continue;
        if(StringFind(name, "_Buy") > 0) hasBuySignal = true;
        if(StringFind(name, "_Sell") > 0) hasSellSignal = true;
    }
    if(hasBuySignal || hasSellSignal)
    {
        if(InpEnableTimeFilter) {
            MqlDateTime time;
            TimeCurrent(time);
            int current_hour = time.hour;
            bool isOutsideHours = false;
            if(InpTradingHourStart > InpTradingHourEnd) {
                if(current_hour < InpTradingHourStart && current_hour >= InpTradingHourEnd) isOutsideHours = true;
            } else {
                if(current_hour < InpTradingHourStart || current_hour >= InpTradingHourEnd) isOutsideHours = true;
            }
            if(isOutsideHours) return;
        }
        if(InpEnableVolatilityFilter) {
            double atr_buffer[];
            int atr_period_long = 100;
            if(CopyBuffer(h_atr, 0, 0, atr_period_long, atr_buffer) == atr_period_long) {
                double avg_atr = 0;
                for(int j = 0; j < atr_period_long; j++) avg_atr += atr_buffer[j];
                avg_atr /= atr_period_long;
                if(atr_buffer[0] > avg_atr * InpAtrMaxRatio) return;
            }
        }
        if(TimeCurrent() > lastTradeTime + 5)
        {
            MqlTick tick;
            if(!SymbolInfoTick(_Symbol, tick)) return;
            if(hasBuySignal && buyGroup.positionCount < InpMaxPositions)
            {
                ScoreComponentInfo info = CalculateMACDScore(true);
                if(info.total_score >= InpScore_Standard) PlaceOrder(true, tick.ask, 0, 0, "Buy", info.total_score);
            }
            if(hasSellSignal && sellGroup.positionCount < InpMaxPositions)
            {
                ScoreComponentInfo info = CalculateMACDScore(false);
                if(info.total_score >= InpScore_Standard) PlaceOrder(false, tick.bid, 0, 0, "Sell", info.total_score);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ピボットラインと手動ラインを更新                             |
//+------------------------------------------------------------------+
void UpdateLines()
{
    ArrayFree(allLines);
    if(InpUsePivotLines)
    {
        CalculatePivot();
        double supports[] = {s1, s2, s3};
        color support_colors[] = {(color)CLR_S1, (color)CLR_S2, (color)CLR_S3};
        for(int i = 0; i < 3; i++)
        {
            if(i > 0 && !InpShowS2R2) continue;
            if(i > 1 && !InpShowS3R3) continue;
            Line s_line;
            s_line.name = "S" + IntegerToString(i + 1);
            s_line.price = supports[i];
            s_line.type = LINE_TYPE_SUPPORT;
            s_line.signalColor = support_colors[i];
            int new_size = ArraySize(allLines) + 1;
            ArrayResize(allLines, new_size);
            allLines[new_size - 1] = s_line;
        }
        double resistances[] = {r1, r2, r3};
        color resist_colors[] = {(color)CLR_R1, (color)CLR_R2, (color)CLR_R3};
        for(int i = 0; i < 3; i++)
        {
            if(i > 0 && !InpShowS2R2) continue;
            if(i > 1 && !InpShowS3R3) continue;
            Line r_line;
            r_line.name = "R" + IntegerToString(i + 1);
            r_line.price = resistances[i];
            r_line.type = LINE_TYPE_RESISTANCE;
            r_line.signalColor = resist_colors[i];
            int new_size = ArraySize(allLines) + 1;
            ArrayResize(allLines, new_size);
            allLines[new_size - 1] = r_line;
        }
    }
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
            int new_size = ArraySize(allLines) + 1;
            ArrayResize(allLines, new_size);
            allLines[new_size - 1] = m_line;
        }
    }
}

//+------------------------------------------------------------------+
//| ラインに対するシグナルを検出                                 |
//+------------------------------------------------------------------+
void CheckLineSignals(Line &line)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, PERIOD_M5, 0, 2, rates) < 2) return;
    datetime currentTime = rates[0].time;
    datetime prevBarTime = rates[1].time;
    double offset = InpSignalOffsetPips * g_pip;
    if(InpEntryMode == TOUCH_MODE)
    {
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(!line.isBrokeUp && rates[1].open < line.price && rates[1].close >= line.price)
            {
                if(!InpAllowOuterTouch) CreateSignalObject(InpArrowPrefix + "TouchBreak_Buy_" + line.name, prevBarTime, rates[1].low - offset, line.signalColor, InpTouchBreakUpCode, "");
                line.isBrokeUp = true;
            }
            if(!line.isBrokeUp && rates[1].open <= line.price && rates[1].high >= line.price && rates[1].close <= line.price && rates[1].low < line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Sell_" + line.name, prevBarTime, line.price + offset, line.signalColor, InpTouchReboundDownCode, "");
            }
        }
        else
        {
            if(!line.isBrokeDown && rates[1].open > line.price && rates[1].close <= line.price)
            {
                if(!InpAllowOuterTouch) CreateSignalObject(InpArrowPrefix + "TouchBreak_Sell_" + line.name, prevBarTime, rates[1].high + offset, line.signalColor, InpTouchBreakDownCode, "");
                line.isBrokeDown = true;
            }
            if(!line.isBrokeDown && rates[1].open >= line.price && rates[1].low <= line.price && rates[1].close >= line.price && rates[1].high > line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Buy_" + line.name, prevBarTime, line.price - offset, line.signalColor, InpTouchReboundUpCode, "");
            }
        }
    }
    else if(InpEntryMode == ZONE_MODE)
    {
        double zone_lower = line.price - InpZonePips * g_pip;
        double zone_upper = line.price + InpZonePips * g_pip;
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(rates[0].close >= line.price && rates[0].close < zone_upper) line.isInZone = true;
            else if(rates[0].close >= zone_upper || rates[0].close < line.price) line.isInZone = false;
            if(line.isInZone && rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "ZoneRebound_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpZoneReboundSellCode, "");
                line.isInZone = false;
            }
            if(rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "VReversal_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpVReversalSellCode, "");
            }
            if(InpBreakMode)
            {
                if(rates[0].close > zone_upper) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].high >= line.price && rates[0].close < line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpRetestSellCode, "");
                    line.waitForRetest = false;
                }
            }
        }
        else
        {
            if(rates[0].close <= line.price && rates[0].close > zone_lower) line.isInZone = true;
            else if(rates[0].close <= zone_lower || rates[0].close > line.price) line.isInZone = false;
            if(line.isInZone && rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "ZoneRebound_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpZoneReboundBuyCode, "");
                line.isInZone = false;
            }
            if(rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "VReversal_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpVReversalBuyCode, "");
            }
            if(InpBreakMode)
            {
                if(rates[0].close < zone_lower) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].low <= line.price && rates[0].close > line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpRetestBuyCode, "");
                    line.waitForRetest = false;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 新しいバーの発生を検出                                       |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    int index = (timeframe == PERIOD_M5) ? 0 : 1;
    datetime currentTime = iTime(_Symbol, timeframe, 0);
    if(currentTime != lastBar[index])
    {
        lastBar[index] = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| ピボットポイントを計算                                       |
//+------------------------------------------------------------------+
void CalculatePivot()
{
    double h = iHigh(_Symbol, InpPivotPeriod, 1);
    double l = iLow(_Symbol, InpPivotPeriod, 1);
    double c = iClose(_Symbol, InpPivotPeriod, 1);
    pivot = (h + l + c) / 3.0;
    s1 = 2.0 * pivot - h;
    r1 = 2.0 * pivot - l;
    if(InpShowS2R2) { s2 = s1 - (r1 - s1); r2 = r1 + (r1 - s1); }
    if(InpShowS3R3) { s3 = s2 - (r2 - s2); r3 = r2 + (r2 - s2); }
}

//+------------------------------------------------------------------+
//| ピボットラインをチャート上に描画 (再延長バグ修正版)              |
//+------------------------------------------------------------------+
void DrawPivotLine()
{
    // 1. 新しいピボット期間の開始時間を取得
    datetime new_start_time = iTime(_Symbol, InpPivotPeriod, 0);

    // 2. 既存のピボットラインを検索し、「延長中」の古いラインだけを確定させる
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(name, "Pivot_") == 0)
        {
            // ★★★ このラインがまだ延長中(Ray)かを確認する条件を追加 ★★★
            if(ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) == true)
            {
                // 延長線をオフにし、終点を現在の期間の開始時間に設定してラインを確定
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, name, OBJPROP_TIME, 1, new_start_time);
            }
        }
    }

    // 3. 新しいピボットラインを描画
    string ts = TimeToString(new_start_time, TIME_DATE | TIME_MINUTES);
    StringReplace(ts, ":", "_"); StringReplace(ts, ".", "_");
    
    string names[] = {"S1", "R1", "S2", "R2", "S3", "R3"};
    double prices[] = {s1, r1, s2, r2, s3, r3};
    color colors[] = {(color)CLR_S1, (color)CLR_R1, (color)CLR_S2, (color)CLR_R2, (color)CLR_S3, (color)CLR_R3};

    for(int i = 0; i < 6; i++)
    {
        if(i >= 2 && !InpShowS2R2) continue;
        if(i >= 4 && !InpShowS3R3) continue;
        
        string name = "Pivot_" + names[i] + "_" + ts;
        
        // 同じ名前のオブジェクトがなければ新規作成
        if(ObjectFind(0, name) < 0)
        {
            datetime end_time = new_start_time + PeriodSeconds(InpPivotPeriod);
            if(ObjectCreate(0, name, OBJ_TREND, 0, new_start_time, prices[i], end_time, prices[i]))
            {
                ObjectSetInteger(0, name, OBJPROP_COLOR, colors[i]);
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); // 新しいラインは延長する
                ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 新規注文を送信                                               |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, double sl, double tp, string comment, int score)
{
    MqlTradeRequest req = {};
    MqlTradeResult res = {};
    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = InpLotSize;
    req.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price = NormalizeDouble(price, _Digits);
    req.magic = InpMagicNumber;
    req.comment = comment + " (" + (string)score + ")";
    if(!OrderSend(req, res)) Print("OrderSend error ", GetLastError());
    else {
        if(res.deal > 0 && HistoryDealSelect(res.deal))
        {
            long ticket = HistoryDealGetInteger(res.deal, DEAL_POSITION_ID);
            if(PositionSelectByTicket(ticket))
            {
                PositionInfo newPos;
                newPos.ticket = ticket;
                newPos.score = score;
                newPos.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                newPos.lotSize = PositionGetDouble(POSITION_VOLUME);
                newPos.isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                newPos.openTime = (datetime)PositionGetInteger(POSITION_TIME);
                int size = ArraySize(g_managedPositions);
                ArrayResize(g_managedPositions, size + 1);
                g_managedPositions[size] = newPos;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 手動ライン描画ボタンの状態を更新                             |
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
//| シグナルオブジェクトを全て削除                               |
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
//| 手動描画ラインを全て削除                                     |
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
//| 手動でトレンドラインを描画                                   |
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
//| 手動ラインの状態を監視し、ブレイクを検出                    |
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
        bool is_broken = false;
        if(StringFind(text, "Resistance") >= 0 && rates[1].close > price) is_broken = true;
        else if(StringFind(text, "Support") >= 0 && rates[1].close < price) is_broken = true;
        if(is_broken)
        {
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, rates[1].time);
            ObjectSetString(0, name, OBJPROP_TEXT, text + "-Broken");
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
        }
    }
}

//+------------------------------------------------------------------+
//| シグナルオブジェクトをチャートに描画                         |
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
        }
    }
}

//+------------------------------------------------------------------+
//| ダイバージェンスシグナルをチャートに描画                     |
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
//| ポジショングループを初期化                                   |
//+------------------------------------------------------------------+
void InitGroup(PositionGroup &group, bool isBuy)
{
    group.isBuy = isBuy;
    group.isActive = false;
    group.averageEntryPrice = 0;
    group.totalLotSize = 0;
    group.initialTotalLotSize = 0;
    group.splitsDone = 0;
    group.openTime = 0;
    group.stampedFinalTP = 0;
    group.averageScore = 0;
    group.highestScore = 0;
    group.positionCount = 0;
    ArrayResize(group.positionTickets, 0);
    if(InpSplitCount > 0)
    {
        ArrayResize(group.splitPrices, InpSplitCount);
        ArrayResize(group.splitLineNames, InpSplitCount);
        ArrayResize(group.splitLineTimes, InpSplitCount);
        for(int i = 0; i < InpSplitCount; i++)
        {
            group.splitLineNames[i] = "SplitLine_" + (isBuy ? "BUY" : "SELL") + "_" + (string)i;
            group.splitLineTimes[i] = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| ポジショングループの状態を更新                               |
//+------------------------------------------------------------------+
void ManagePositionGroups()
{
    InitGroup(buyGroup, true);
    InitGroup(sellGroup, false);
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
            for(int j = 0; j < ArraySize(g_managedPositions); j++) {
                if(g_managedPositions[j].ticket == ticket) {
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
        buyGroup.averageEntryPrice = buyWeightedSum / buyGroup.totalLotSize;
        if(buyGroup.totalLotSize > 0) buyGroup.averageScore = buyTotalScoreLot / buyGroup.totalLotSize;
        buyGroup.positionCount = ArraySize(buyGroup.positionTickets);
    }
    if(sellGroup.isActive)
    {
        sellGroup.averageEntryPrice = sellWeightedSum / sellGroup.totalLotSize;
        if(sellGroup.totalLotSize > 0) sellGroup.averageScore = sellTotalScoreLot / sellGroup.totalLotSize;
        sellGroup.positionCount = ArraySize(sellGroup.positionTickets);
    }
}

//+------------------------------------------------------------------+
//| ZigZagに基づくTPラインを更新                                 |
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
            newBuyTP = entryPrice + (originalDiff * InpHighSchoreTpRratio);
        }
        if(newBuyTP > 0 && MathAbs(newBuyTP - zonalFinalTPLine_Buy) > g_pip)
        {
            zonalFinalTPLine_Buy = newBuyTP;
            string name = "TPLine_Buy";
            if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
            ObjectMove(0, name, 0, 0, zonalFinalTPLine_Buy);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
            if(buyGroup.isActive) UpdateGroupSplitLines(buyGroup);
        }
    }
    if(!isSellTPManuallyMoved)
    {
        double newSellTP = (levelLow < DBL_MAX) ? levelLow : 0;
        if(sellGroup.isActive && sellGroup.highestScore >= InpScore_High && newSellTP > 0)
        {
            double entryPrice = sellGroup.averageEntryPrice;
            double originalDiff = entryPrice - newSellTP;
            newSellTP = entryPrice - (originalDiff * InpHighSchoreTpRratio);
        }
        if(newSellTP > 0 && MathAbs(newSellTP - zonalFinalTPLine_Sell) > g_pip)
        {
            zonalFinalTPLine_Sell = newSellTP;
            string name = "TPLine_Sell";
            if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
            ObjectMove(0, name, 0, 0, zonalFinalTPLine_Sell);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrMediumPurple);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
            if(sellGroup.isActive) UpdateGroupSplitLines(sellGroup);
        }
    }
}

//+------------------------------------------------------------------+
//| ポジショングループの分割決済ラインを更新                     |
//+------------------------------------------------------------------+
void UpdateGroupSplitLines(PositionGroup &group)
{
    string prefix = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_";
    ObjectsDeleteAll(0, prefix);
    if(!group.isActive || InpSplitCount <= 0) return;
    double tpPrice = group.stampedFinalTP;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) tpPrice = group.averageEntryPrice + (group.isBuy ? 1000 : -1000) * g_pip;
    double step = MathAbs(tpPrice - group.averageEntryPrice) / InpSplitCount;
    for(int i = 0; i < InpSplitCount; i++)
    {
        group.splitPrices[i] = group.averageEntryPrice + (group.isBuy ? 1 : -1) * step * (i + 1);
        string name = group.splitLineNames[i];
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, group.splitPrices[i]);
        ObjectSetInteger(0, name, OBJPROP_COLOR, group.isBuy ? clrGoldenrod : clrPurple);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    }
}

//+------------------------------------------------------------------+
//| ポジショングループの決済条件をチェック                       |
//+------------------------------------------------------------------+
void CheckExitForGroup(PositionGroup &group)
{
    if(!group.isActive || group.splitsDone >= InpSplitCount) return;
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    double currentPrice = group.isBuy ? tick.bid : tick.ask;
    for(int i = group.splitsDone; i < InpSplitCount; i++)
    {
        double targetPrice = group.splitPrices[i];
        bool shouldExit = false;
        if(group.isBuy && currentPrice >= targetPrice) shouldExit = true;
        else if(!group.isBuy && currentPrice <= targetPrice) shouldExit = true;
        if(shouldExit)
        {
            if(ExecuteGroupSplitExit(group, i)) group.splitsDone++;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| ポジショングループの分割決済を実行                               |
//+------------------------------------------------------------------+
bool ExecuteGroupSplitExit(PositionGroup &group, int splitIndex)
{
    // この関数はCheckExitForGroupから呼び出される想定だったが、
    // 現在の実装ではロット計算ロジックがCheckExitForGroupにあるため、
    // こちらの関数は直接使用しない。代わりにExecuteGroupSplitExit(group, lot)を実装する。
    // 互換性のために残すが、ここでは何もしない。
    return false;
}

//+------------------------------------------------------------------+
//| ポジショングループの分割決済を実行 (ロット指定版)                 |
//| この関数が実質的な決済処理を行う                             |
//+------------------------------------------------------------------+
bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose)
{
    int ticketCount = ArraySize(group.positionTickets);
    if (ticketCount == 0) return false;
    
    SortablePosition positionsToSort[];
    ArrayResize(positionsToSort, ticketCount);

    for (int i = 0; i < ticketCount; i++) {
        if (PositionSelectByTicket(group.positionTickets[i])) {
            positionsToSort[i].ticket = group.positionTickets[i];
            positionsToSort[i].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        }
    }
    
    if (InpExitLogic != EXIT_FIFO)
    {
        for (int i = 0; i < ticketCount - 1; i++) {
            for (int j = 0; j < ticketCount - i - 1; j++) {
                bool shouldSwap = false;
                if (InpExitLogic == EXIT_UNFAVORABLE) {
                    if ((group.isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice) || 
                        (!group.isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice)) {
                        shouldSwap = true;
                    }
                } else { // EXIT_FAVORABLE
                    if ((group.isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice) || 
                        (!group.isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice)) {
                        shouldSwap = true;
                    }
                }
                if (shouldSwap) {
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
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.type_filling = ORDER_FILLING_IOC;

        if (remainingLotToClose >= posVolume)
        {
            request.volume = posVolume;
            if(OrderSend(request, tradeResult)) {
                remainingLotToClose -= posVolume;
                result = true;
            }
        }
        else
        {
            if (remainingLotToClose > 0) {
                request.volume = remainingLotToClose;
                if(OrderSend(request, tradeResult)) {
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
//| ポジショングループの全ポジションを決済                       |
//+------------------------------------------------------------------+
void CloseAllPositionsInGroup(PositionGroup &group)
{
    for(int i = ArraySize(group.positionTickets) - 1; i >= 0; i--)
    {
        ulong ticket = group.positionTickets[i];
        if(PositionSelectByTicket(ticket))
        {
            MqlTradeRequest req = {};
            MqlTradeResult res = {};
            req.action = TRADE_ACTION_DEAL;
            req.position = ticket;
            req.symbol = _Symbol;
            req.volume = PositionGetDouble(POSITION_VOLUME);
            req.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            req.magic = InpMagicNumber;
            if(!OrderSend(req, res))
            {
                Print("Close Position error: ", GetLastError());
            }
        }
    }
    InitGroup(group, group.isBuy);
}

//+------------------------------------------------------------------+
//| 新しいエントリーシグナルを検出                                   |
//+------------------------------------------------------------------+
void DetectNewEntrances()
{
    // INDIVIDUALモード用のロジック
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
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
                if(!exists)
                {
                    AddSplitData(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ポジションの決済条件をチェック                                   |
//+------------------------------------------------------------------+
void CheckExits()
{
    // INDIVIDUALモード用のロジック
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    for(int i = ArraySize(splitPositions) - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(splitPositions[i].ticket))
        {
            // ポジションが存在しない場合はリストから削除
            for(int j=0; j<ArraySize(splitPositions[i].splitLineNames); j++)
            {
                ObjectDelete(0, splitPositions[i].splitLineNames[j]);
            }
            ArrayRemove(splitPositions, i, 1);
            continue;
        }
        
        if(splitPositions[i].splitsDone >= InpSplitCount) continue;

        double currentPrice = splitPositions[i].isBuy ? bid : ask;
        double nextSplitPrice = splitPositions[i].splitPrices[splitPositions[i].splitsDone];
        
        if (nextSplitPrice <= 0) continue;

        double priceBuffer = InpExitBufferPips * g_pip;
        bool splitPriceReached = (splitPositions[i].isBuy && currentPrice >= (nextSplitPrice - priceBuffer)) || 
                                 (!splitPositions[i].isBuy && currentPrice <= (nextSplitPrice + priceBuffer));
        
        if(splitPriceReached && splitPositions[i].splitLineTimes[splitPositions[i].splitsDone] == 0)
        {
            double remainingLot = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
            if (remainingLot < minLot) continue;

            if (splitPositions[i].splitsDone == InpSplitCount - 1)
            {
                ClosePosition(splitPositions[i].ticket);
            }
            else
            {
                double splitLot = NormalizeDouble(splitPositions[i].lotSize / InpSplitCount, 2);
                if(splitLot < minLot) splitLot = minLot;
                if(splitLot > remainingLot) splitLot = remainingLot;

                if(ExecuteSplitExit(splitPositions[i].ticket, splitLot, splitPositions[i], splitPositions[i].splitsDone))
                {
                    splitPositions[i].splitsDone++;
                    if(InpBreakEvenAfterSplits > 0 && splitPositions[i].splitsDone == InpBreakEvenAfterSplits)
                    {
                        SetBreakEven(splitPositions[i].ticket, splitPositions[i].entryPrice);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 指定されたポジションのSLを設定 (ブレークイーブン)                  |
//+------------------------------------------------------------------+
bool SetBreakEven(ulong ticket, double entryPrice)
{
    MqlTradeRequest req;
    MqlTradeResult res;
    if(PositionSelectByTicket(ticket))
    {
        req.action = TRADE_ACTION_SLTP;
        req.position = ticket;
        req.symbol = _Symbol;
        req.sl = NormalizeDouble(entryPrice, _Digits);
        req.tp = PositionGetDouble(POSITION_TP);
        return OrderSend(req, res);
    }
    return false;
}

//+------------------------------------------------------------------+
//| 新規ポジションを分割決済の管理対象に追加                         |
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

    // このポジションのスコアをg_managedPositionsから探す
    newSplit.score = 0; // デフォルトスコア
    for(int i = 0; i < ArraySize(g_managedPositions); i++)
    {
        if(g_managedPositions[i].ticket == ticket)
        {
            newSplit.score = g_managedPositions[i].score;
            break;
        }
    }
    
    // TPをスタンプ
    newSplit.stampedFinalTP = newSplit.isBuy ? zonalFinalTPLine_Buy : zonalFinalTPLine_Sell;

    double tpPrice = newSplit.stampedFinalTP;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) {
        tpPrice = newSplit.isBuy ? newSplit.entryPrice + 1000 * g_pip : newSplit.entryPrice - 1000 * g_pip;
    }

    // INDIVIDUALモードでも高スコアの場合はTPを動的に調整
    if(newSplit.score >= InpScore_High && tpPrice > 0)
    {
        double originalDiff = MathAbs(tpPrice - newSplit.entryPrice);
        tpPrice = newSplit.entryPrice + (newSplit.isBuy ? 1 : -1) * (originalDiff * InpHighSchoreTpRratio);
    }

    double priceDiff = MathAbs(tpPrice - newSplit.entryPrice);
    if(InpSplitCount > 0)
    {
        ArrayResize(newSplit.splitPrices, InpSplitCount);
        ArrayResize(newSplit.splitLineNames, InpSplitCount);
        ArrayResize(newSplit.splitLineTimes, InpSplitCount);
        double step = priceDiff / InpSplitCount;

        for(int i = 0; i < InpSplitCount; i++)
        {
            newSplit.splitPrices[i] = newSplit.isBuy ? newSplit.entryPrice + step * (i + 1) :
                                                       newSplit.entryPrice - step * (i + 1);
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
//| 個別ポジションの分割決済を実行                                   |
//+------------------------------------------------------------------+
bool ExecuteSplitExit(ulong ticket, double lot, SplitData &split, int splitIndex)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    if(!PositionSelectByTicket(ticket)) return false;

    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = lot;
    request.type = split.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = split.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.type_filling = ORDER_FILLING_IOC;

    if(!OrderSend(request, result)) 
    {
        PrintFormat("ExecuteSplitExit 失敗: %d", GetLastError());
        return false;
    }

    // 決済したラインを過去のものとして描画しなおす
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
//| 指定されたチケットのポジションを決済                             |
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
        
        if(!OrderSend(req, res))
        {
            PrintFormat("ポジション #%d の決済に失敗しました。エラー: %d", ticket, GetLastError());
        }
    }
}
