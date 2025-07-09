//+------------------------------------------------------------------+
//| ZoneEntryEA.mq5 - v3.00 (Scoring System Base)                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "3.00"

// --- ラインカラー定数
#define CLR_S1 2970272
#define CLR_R1 13434880
#define CLR_S2 36095
#define CLR_R2 16748574
#define CLR_S3 42495
#define CLR_R3 15453831

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
    // 各項目の検知フラグ
    bool divergence;
    bool exec_angle;
    bool mid_angle;
    bool exec_hist;
    bool mid_hist_sync;
    bool mid_zeroline;
    bool long_zeroline;
    
    // 合計スコア
    int total_score;
};

//--- 入力パラメータ
input group "=== エントリーロジック設定 ===";
input bool      InpUsePivotLines    = true;     // ピボットラインを使用する
enum ENTRY_MODE { TOUCH_MODE, ZONE_MODE };
input ENTRY_MODE InpEntryMode        = ZONE_MODE;// エントリーモード
input bool      InpBreakMode        = true;     // ブレイクモード
input bool      InpRoleReversalMode = false;    // ロールリバーサルモード（未実装）
input double    InpZonePips         = 50.0;     // ゾーン幅 (pips)

input group "=== UI設定 ===";
input bool      InpShowInfoPanel = true;       // 情報パネルを表示する
input int       p_panel_x_offset = 10;         // パネルX位置
input int       p_panel_y_offset = 130;        // パネルY位置

input group "=== 取引設定 ===";
input double    InpLotSize      = 0.1;         // ロットサイズ
input int       InpMaxPositions = 1;           // 同方向の最大ポジション数
input double    InpSLPips       = 0.0;         // SL距離 (pips, 0=設定しない)
input double    InpTPPips       = 0.0;         // TP距離 (pips, 0=設定しない)
input int       InpMagicNumber  = 123456;      // マジックナンバー
input int       InpDotTimeout   = 600;         // ドット/矢印有効期限 (秒)

input group "=== トレード管理設定 ===";
input bool   InpEnableTrailingStop = true;     // トレーリングストップを有効にするか
input double InpTrailingStop_High  = 50.0;     // トレーリング幅 (高スコア用, pips)
input double InpTrailingStop_Std   = 20.0;     // トレーリング幅 (標準スコア用, pips)
input bool   InpEnableBreakEven    = true;     // ブレークイーブンを有効にするか
input double InpBreakEvenTrigger   = 30.0;     // ブレークイーブン発動利益 (pips)
input double InpBreakEvenProfit    = 2.0;      // ブレークイーブン時の固定利益 (pips)

input group "--- 動的フィルター設定 ---";
input bool   InpEnableVolatilityFilter = true; // ボラティリティフィルターを有効にするか
input double InpAtrMaxRatio           = 1.5;   // エントリーを許可する最大ATR倍率
input bool   InpEnableTimeFilter      = true;  // 取引時間フィルターを有効にするか
input int    InpTradingHourStart      = 15;    // 取引開始時間 (サーバー時間)
input int    InpTradingHourEnd        = 25;    // 取引終了時間 (サーバー時間, 25 = 翌午前1時)

input group "--- ダイバージェンスの可視化設定 ---";
input bool   InpShowDivergenceSignals = true;               // ダイバージェンスサインを表示するか
input string InpDivSignalPrefix      = "DivSignal_";       // サインのオブジェクト名プレフィックス
input color  InpBullishDivColor      = clrDeepSkyBlue;     // 強気ダイバージェンスの色
input color  InpBearishDivColor      = clrHotPink;         // 弱気ダイバージェンスの色
input int    InpDivSymbolCode        = 159;                // サインのシンボルコード (159 = ●)
input int    InpDivSymbolSize        = 8;                  // サインの大きさ
input double InpDivSymbolOffsetPips  = 15.0;               // サインの描画オフセット (Pips)

input group "=== MACDスコアリング設定 ===";
input int    InpScore_Standard      = 4;      // 標準エントリーの最低スコア
input int    InpScore_High          = 6;      // ロットアップエントリーの最低スコア
input double InpLotMultiplier_High  = 1.5;    // ロットアップ時のロット倍率

input group "--- 執行足MACD (トリガー) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Exec    = PERIOD_CURRENT; // 時間足 (PERIOD_CURRENT=チャートの時間足)
input int             InpMACD_Fast_Exec  = 12;            // Fast EMA
input int             InpMACD_Slow_Exec  = 26;            // Slow EMA
input int             InpMACD_Signal_Exec = 9;            // Signal SMA

input group "--- 中期足MACD (コンテキスト) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Mid    = PERIOD_H1;      // 時間足
input int             InpMACD_Fast_Mid  = 12;            // Fast EMA
input int             InpMACD_Slow_Mid  = 26;            // Slow EMA
input int             InpMACD_Signal_Mid = 9;            // Signal SMA

input group "--- 長期足MACD (コンファメーション) ---";
input ENUM_TIMEFRAMES InpMACD_TF_Long    = PERIOD_H4;     // 時間足
input int             InpMACD_Fast_Long  = 12;            // Fast EMA
input int             InpMACD_Slow_Long  = 26;            // Slow EMA
input int             InpMACD_Signal_Long = 9;            // Signal SMA

input group "=== ピボットライン設定 ===";
input ENUM_TIMEFRAMES InpPivotPeriod   = PERIOD_H1;   // ピボット時間足
input bool            InpShowS2R2      = true;        // S2/R2ラインを表示
input bool            InpShowS3R3      = true;        // S3/R3ラインを表示
input bool            InpAllowOuterTouch = false;     // ライン外側からのタッチ/ブレイク検知を許可

input group "=== 手動ライン設定 ===";
input color           p_ManualSupport_Color = clrDodgerBlue; // 手動サポートラインの色
input color           p_ManualResist_Color  = clrTomato;    // 手動レジスタンスラインの色
input ENUM_LINE_STYLE p_ManualLine_Style    = STYLE_DOT;    // 手動ラインのスタイル
input int             p_ManualLine_Width    = 2;            // 手動ラインの太さ

input group "=== オブジェクトとシグナルの外観 ===";
input string InpLinePrefix_Pivot   = "Pivot_";        // ピボットラインプレフィックス
input string InpDotPrefix          = "Dot_";          // ドットプレフィックス
input string InpArrowPrefix        = "Trigger_";      // 矢印プレフィックス
input int    InpSignalWidth        = 2;               // シグナルの太さ
input int    InpSignalFontSize     = 10;              // シグナルの大きさ
input double InpSignalOffsetPips   = 2.0;             // シグナルの描画オフセット (Pips)
input int    InpTouchBreakUpCode   = 221;             // タッチブレイク買いのシンボルコード
input int    InpTouchBreakDownCode = 222;             // タッチブレイク売りのシンボルコード
input int    InpTouchReboundUpCode = 233;             // タッチひげ反発買いのシンボルコード
input int    InpTouchReboundDownCode = 234;           // タッチひげ反発売りのシンボルコード
input int    InpZoneReboundBuyCode = 231;             // ゾーン内反発 (買い) のシンボルコード
input int    InpZoneReboundSellCode= 232;             // ゾーン内反発 (売り) のシンボルコード
input int    InpVReversalBuyCode   = 233;             // V字回復 (買い) のシンボルコード
input int    InpVReversalSellCode  = 234;             // V字回復 (売り) のシンボルコード
input int    InpRetestBuyCode      = 110;             // ブレイク＆リテスト (買い) のシンボルコード
input int    InpRetestSellCode     = 111;             // ブレイク＆リテスト (売り) のシンボルコード

//--- グローバル変数
double   s1, r1, s2, r2, s3, r3, pivot;
datetime lastTradeTime;
datetime lastBar[2];
datetime lastArrowTime     = 0;
string   g_buttonName       = "DrawManualLineButton";
string   g_clearButtonName  = "ClearSignalsButton";
string   g_clearLinesButtonName = "ClearLinesButton";
string   g_panelPrefix      = "InfoPanel_";
bool     g_isDrawingMode    = false;
Line     allLines[];
double   g_pip; // ★ Pipサイズを格納するグローバル変数を追加
int h_macd_exec; // 執行足MACDハンドル
int h_macd_mid;  // 中期足MACDハンドル
int h_macd_long; // 長期足MACDハンドル
int h_atr;

// EAが管理するポジションの情報を格納する配列
PositionInfo g_managedPositions[];

//--- ヘルパー関数のプロトタイプ宣言
void UpdateLines();
void CheckLineSignals(Line &line);
void DrawPivotLine();
void CalculatePivot();
void CheckEntry();
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string print_msg);
void PlaceOrder(bool isBuy, double price, double slPrice, double tpPrice, string comment);
bool IsNewBar(ENUM_TIMEFRAMES timeframe);
int  CountOpenPositions(long direction);
void CreateButton();
void CreateClearButton();
void CreateClearLinesButton();
void UpdateButtonState();
void ClearSignalObjects();
void ClearManualLines();
void DrawManualTrendLine(double price, datetime time);
void ManageManualLines();
void ManageInfoPanel();
void AddPanelLine(string &lines[], const string text);

//+------------------------------------------------------------------+
//| エキスパート初期化関数                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    // Pipサイズを計算してグローバル変数に格納
    g_pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pow(10, _Digits % 2);
    
    //--- MACDトリオのハンドルを生成
    // 執行足
    h_macd_exec = iMACD(_Symbol, InpMACD_TF_Exec, InpMACD_Fast_Exec, InpMACD_Slow_Exec, InpMACD_Signal_Exec, PRICE_CLOSE);
    // 中期足
    h_macd_mid = iMACD(_Symbol, InpMACD_TF_Mid, InpMACD_Fast_Mid, InpMACD_Slow_Mid, InpMACD_Signal_Mid, PRICE_CLOSE);
    // 長期足
    h_macd_long = iMACD(_Symbol, InpMACD_TF_Long, InpMACD_Fast_Long, InpMACD_Slow_Long, InpMACD_Signal_Long, PRICE_CLOSE);
    // ★ ATRハンドルを生成
    h_atr = iATR(_Symbol, InpMACD_TF_Exec, 14); // ATR期間は一旦14で固定
    
    //--- ハンドル生成の成否をチェック
    if(h_macd_exec == INVALID_HANDLE || h_macd_mid == INVALID_HANDLE || h_macd_long == INVALID_HANDLE)
    {
        Print("MACDインジケータハンドルの作成に失敗しました。");
        return(INIT_FAILED);
    }

    //--- 変数初期化
    lastBar[0] = 0;
    lastBar[1] = 0;
    lastTradeTime = 0;

    //--- オブジェクト初期化
    UpdateLines();
    if(InpUsePivotLines)
    {
        DrawPivotLine();
    }
    CreateButton();
    CreateClearButton();
    CreateClearLinesButton();
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1, true);

    Print("ZoneEntryEA v3.00 (Scoring System Base) 初期化完了");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパート終了処理関数                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- オブジェクト削除
    ObjectDelete(0, g_buttonName);
    ObjectDelete(0, g_clearButtonName);
    ObjectDelete(0, g_clearLinesButtonName);
    ObjectsDeleteAll(0, g_panelPrefix);
    ObjectsDeleteAll(0, 0, -1, InpLinePrefix_Pivot);
    ObjectsDeleteAll(0, 0, -1, InpDotPrefix);
    ObjectsDeleteAll(0, 0, -1, InpArrowPrefix);

    //--- ハンドル解放
    IndicatorRelease(h_macd_exec);
    IndicatorRelease(h_macd_mid);
    IndicatorRelease(h_macd_long);
    // ★ ATRハンドルを解放
    IndicatorRelease(h_atr);

    PrintFormat("ZoneEntryEA v3.00 (Scoring System Base) 終了: 理由=%d", reason);
}

//+------------------------------------------------------------------+
//| エキスパートティック関数                                           |
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

    // ★ 新しいバーのタイミングで全ての管理を実行
    if(IsNewBar(PERIOD_M5))
    {
        SyncManagedPositions(); 
        ManageOpenTrades(); // ★ 保有ポジション管理の呼び出しを追加
        ManageInfoPanel();
        ManageManualLines();
        CheckEntry();
    }
}

//+------------------------------------------------------------------+
//| 保有中のトレードを管理する（トレーリングストップ、ブレークイーブン） |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    if(!InpEnableTrailingStop && !InpEnableBreakEven) return;

    for(int i = 0; i < ArraySize(g_managedPositions); i++)
    {
        PositionInfo pos_info = g_managedPositions[i];
        if(!PositionSelectByTicket(pos_info.ticket)) continue;

        long   pos_type      = PositionGetInteger(POSITION_TYPE);
        double open_price    = PositionGetDouble(POSITION_PRICE_OPEN);
        double current_sl    = PositionGetDouble(POSITION_SL);
        double current_tp    = PositionGetDouble(POSITION_TP);
        double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // --- 1. ブレークイーブン処理 ---
        if(InpEnableBreakEven)
        {
            bool is_be_set = (pos_type == POSITION_TYPE_BUY && current_sl >= open_price) || (pos_type == POSITION_TYPE_SELL && current_sl <= open_price && current_sl != 0);
            if(!is_be_set)
            {
                double trigger_price = (pos_type == POSITION_TYPE_BUY) ? open_price + InpBreakEvenTrigger * g_pip : open_price - InpBreakEvenTrigger * g_pip;
                
                if((pos_type == POSITION_TYPE_BUY && current_price > trigger_price) || (pos_type == POSITION_TYPE_SELL && current_price < trigger_price))
                {
                    double new_sl = open_price + ((pos_type == POSITION_TYPE_BUY ? 1 : -1) * InpBreakEvenProfit * g_pip);
                    
                    // ★★★ ここから修正 ★★★
                    MqlTradeRequest request = {}; MqlTradeResult  result  = {};
                    request.action   = TRADE_ACTION_SLTP;
                    request.position = pos_info.ticket;
                    request.sl      = NormalizeDouble(new_sl, _Digits);
                    request.tp      = current_tp;
                    
                    if(OrderSend(request, result))
                    {
                        PrintFormat("Ticket %d: ブレークイーブン発動. New SL: %.5f", pos_info.ticket, new_sl);
                        continue; // ブレークイーブンを実行したら、このポジションの今回の処理は終わり
                    }
                    else
                    {
                        PrintFormat("Ticket %d: ブレークイーブンSLの変更に失敗. Error: %d", pos_info.ticket, result.retcode);
                    }
                    // ★★★ ここまで修正 ★★★
                }
            }
        }
        
        // --- 2. トレーリングストップ処理 (ブレークイーブンが発動しなかった場合のみ実行される) ---
        if(InpEnableTrailingStop)
        {
            double trailing_pips = (pos_info.score >= InpScore_High) ? InpTrailingStop_High : InpTrailingStop_Std;
            double new_sl = current_sl;
            
            if(pos_type == POSITION_TYPE_BUY)
            {
                double potential_new_sl = current_price - trailing_pips * g_pip;
                if(potential_new_sl > new_sl) new_sl = potential_new_sl;
            }
            else // POSITION_TYPE_SELL
            {
                double potential_new_sl = current_price + trailing_pips * g_pip;
                if(potential_new_sl < new_sl || new_sl == 0) new_sl = potential_new_sl;
            }

            if(new_sl != current_sl)
            {
                MqlTradeRequest request = {}; MqlTradeResult  result  = {};
                request.action   = TRADE_ACTION_SLTP;
                request.position = pos_info.ticket;
                request.sl      = NormalizeDouble(new_sl, _Digits);
                request.tp      = current_tp;
                
                if(!OrderSend(request, result))
                {
                    PrintFormat("Ticket %d: トレーリングSLの変更に失敗. Error: %d", pos_info.ticket, result.retcode);
                }
                else
                {
                    PrintFormat("Ticket %d: トレーリングSLを変更しました. New SL: %.5f", pos_info.ticket, new_sl);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 管理ポジションリストと実際のポジションを同期する                  |
//+------------------------------------------------------------------+
void SyncManagedPositions()
{
    // 配列を逆からループして、安全に要素を削除できるようにする
    for(int i = ArraySize(g_managedPositions) - 1; i >= 0; i--)
    {
        // PositionSelectByTicketで、そのチケットのポジションが存在するか確認
        if(!PositionSelectByTicket(g_managedPositions[i].ticket))
        {
            // 存在しない = 決済済み
            PrintFormat("決済済みポジションを管理リストから削除. Ticket: %d", g_managedPositions[i].ticket);
            // 配列から削除
            ArrayRemove(g_managedPositions, i, 1);
        }
    }
}

//+------------------------------------------------------------------+
//| 情報パネルの管理 (作成と更新)                                    |
//+------------------------------------------------------------------+
void ManageInfoPanel()
{
    if(!InpShowInfoPanel)
    {
        ObjectsDeleteAll(0, g_panelPrefix);
        return;
    }

    string panel_lines[];

    AddPanelLine(panel_lines, "▶ " + MQL5InfoString(MQL5_PROGRAM_NAME) + " v3.1");
    AddPanelLine(panel_lines, " Magic: " + (string)InpMagicNumber);
    AddPanelLine(panel_lines, " Spread: " + (string)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) + " points");
    
    AddPanelLine(panel_lines, "──────────────────────");
    
    //--- スコア詳細表示 ---
    ScoreComponentInfo buy_info  = CalculateMACDScore(true);
    ScoreComponentInfo sell_info = CalculateMACDScore(false);

    AddPanelLine(panel_lines, "--- Score Details ---");
    AddPanelLine(panel_lines, "          [ Buy / Sell ]");
    AddPanelLine(panel_lines, "Divergence:  [ " + (buy_info.divergence ? "✔" : "-") + " / " + (sell_info.divergence ? "✔" : "-") + " ]");
    
    string zero_buy  = (buy_info.mid_zeroline ? "✔" : "-") + "/" + (buy_info.long_zeroline ? "✔" : "-");
    string zero_sell = (sell_info.mid_zeroline ? "✔" : "-") + "/" + (sell_info.long_zeroline ? "✔" : "-");
    AddPanelLine(panel_lines, "Zero(M/L):   [ " + zero_buy + " / " + zero_sell + " ]");
    
    string angle_buy = (buy_info.exec_angle ? "✔" : "-") + "/" + (buy_info.mid_angle ? "✔" : "-");
    string angle_sell= (sell_info.exec_angle ? "✔" : "-") + "/" + (sell_info.mid_angle ? "✔" : "-");
    AddPanelLine(panel_lines, "Angle(E/M):  [ " + angle_buy + " / " + angle_sell + " ]");
    
    string hist_buy = (buy_info.exec_hist ? "✔" : "-") + "/" + (buy_info.mid_hist_sync ? "✔" : "-");
    string hist_sell= (sell_info.exec_hist ? "✔" : "-") + "/" + (sell_info.mid_hist_sync ? "✔" : "-");
    AddPanelLine(panel_lines, "Hist(E/M):   [ " + hist_buy + " / " + hist_sell + " ]");

    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, "Forecast: Buy " + (string)buy_info.total_score + " / Sell " + (string)sell_info.total_score);
    
    //--- ポジション情報 ---
    int    buy_positions  = 0;
    int    sell_positions = 0;
    double total_profit   = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                buy_positions++;
            else
                sell_positions++;
            total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
    }
    string profit_str   = DoubleToString(total_profit, 2);
    color  profit_color = (total_profit >= 0) ? clrLimeGreen : clrTomato;

    AddPanelLine(panel_lines, "──────────────────────");
    AddPanelLine(panel_lines, " Positions: Buy " + (string)buy_positions + " / Sell " + (string)sell_positions);
    AddPanelLine(panel_lines, " P/L: " + profit_str);

    // ★★★ ここからが前回欠けていた描画ループ ★★★
    int line_height = 12;
    for(int i = 0; i < ArraySize(panel_lines); i++)
    {
        string obj_name = g_panelPrefix + (string)i;
        int    y_pos    = p_panel_y_offset + (i * line_height);

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

        if(StringFind(panel_lines[i], "Forecast:") >= 0)
        {
            color forecast_color = clrLightGray;
            if (buy_info.total_score >= InpScore_Standard && buy_info.total_score > sell_info.total_score) forecast_color = clrPaleGreen;
            if (sell_info.total_score >= InpScore_Standard && sell_info.total_score > buy_info.total_score) forecast_color = clrLightPink;
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, forecast_color);
        }
        else if(StringFind(panel_lines[i], "P/L:") >= 0)
        {
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, profit_color);
        }
        else
        {
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrLightGray);
        }
    }

    // 不要な行を削除するループ
    for(int i = ArraySize(panel_lines); i < 30; i++) // チェックする最大行数を少し増やす
    {
        string obj_name = g_panelPrefix + (string)i;
        if(ObjectFind(0, obj_name) >= 0)
            ObjectDelete(0, obj_name);
        else
            break;
    }
    // ★★★ ここまで ★★★
}

//+------------------------------------------------------------------+
//| パネル行追加用のヘルパー関数                                       |
//+------------------------------------------------------------------+
void AddPanelLine(string &lines[], const string text)
{
    int size = ArraySize(lines);
    ArrayResize(lines, size + 1);
    lines[size] = text;
}

//+------------------------------------------------------------------+
//| MACDのスコアを計算する関数 (戻り値をScoreComponentInfoに変更)     |
//+------------------------------------------------------------------+
ScoreComponentInfo CalculateMACDScore(bool is_buy_signal)
{
    ScoreComponentInfo info;
    // 構造体をゼロクリア（全てのフラグをfalse、スコアを0に）
    ZeroMemory(info);

    //--- バッファの準備
    double exec_main[], exec_signal[];
    double mid_main[], mid_signal[];
    double long_main[];
    ArraySetAsSeries(exec_main, true); ArraySetAsSeries(exec_signal, true);
    ArraySetAsSeries(mid_main, true); ArraySetAsSeries(mid_signal, true);
    ArraySetAsSeries(long_main, true);

    //--- データコピー (中期足のシグナルラインも追加)
    if(CopyBuffer(h_macd_exec, 0, 0, 30, exec_main) < 30 || CopyBuffer(h_macd_exec, 1, 0, 30, exec_signal) < 30) return info;
    if(CopyBuffer(h_macd_mid, 0, 0, 4, mid_main) < 4 || CopyBuffer(h_macd_mid, 1, 0, 1, mid_signal) < 1) return info;
    if(CopyBuffer(h_macd_long, 0, 0, 1, long_main) < 1) return info;

    //--- スコアリング開始 ---
    if(is_buy_signal)
    {
        // 【反転性】
        if(CheckMACDDivergence(true, h_macd_exec)) info.divergence = true;

        // 【方向性】
        if(mid_main[0] > 0)  info.mid_zeroline = true;
        if(long_main[0] > 0) info.long_zeroline = true;
        
        // 【勢い】
        if(exec_main[0] - exec_main[3] > 0) info.exec_angle = true; // 簡易的な角度チェック
        if(mid_main[0] - mid_main[3] > 0)   info.mid_angle = true;
        
        // 【持続性】
        double h0=exec_main[0]-exec_signal[0], h1=exec_main[1]-exec_signal[1], h2=exec_main[2]-exec_signal[2];
        if(h0 > h1 && h1 > 0 && h2 > 0) info.exec_hist = true;
        if(mid_main[0] - mid_signal[0] > 0) info.mid_hist_sync = true;
    }
    else // is_sell_signal
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
    
    //--- フラグに基づいて合計スコアを計算 ---
    if(info.divergence)    info.total_score += 3;
    if(info.mid_zeroline)  info.total_score += 2;
    if(info.long_zeroline) info.total_score += 3;
    if(info.exec_angle)    info.total_score += 1;
    if(info.mid_angle)     info.total_score += 2;
    if(info.exec_hist)     info.total_score += 1;
    if(info.mid_hist_sync) info.total_score += 1;

    return info;
}

//+------------------------------------------------------------------+
//| MACDダイバージェンスを判定するヘルパー関数 (描画機能付き)          |
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

    if(is_buy_signal) // 強気のダイバージェンス（買い）を探す
    {
        for(int i = 1; i < check_bars - 1; i++)
        {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
            {
                if(p1_idx == -1) { p1_idx = i; }
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].low < rates[p2_idx].low && macd_main[p1_idx] > macd_main[p2_idx])
            {
                // ★★★ ここで描画関数を呼び出す ★★★
                double price = rates[p1_idx].low - InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBullishDivColor);
                PrintFormat("%s %s: 強気のMACDダイバージェンスを検出", _Symbol, EnumToString(InpMACD_TF_Exec));
                return true;
            }
        }
    }
    else // 弱気のダイバージェンス（売り）を探す
    {
        for(int i = 1; i < check_bars - 1; i++)
        {
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
            {
                if(p1_idx == -1) { p1_idx = i; }
                else { p2_idx = p1_idx; p1_idx = i; break; }
            }
        }
        
        if(p1_idx > 0 && p2_idx > 0)
        {
            if(rates[p1_idx].high > rates[p2_idx].high && macd_main[p1_idx] < macd_main[p2_idx])
            {
                // ★★★ ここで描画関数を呼び出す ★★★
                double price = rates[p1_idx].high + InpDivSymbolOffsetPips * g_pip;
                DrawDivergenceSignal(rates[p1_idx].time, price, InpBearishDivColor);
                PrintFormat("%s %s: 弱気のMACDダイバージェンスを検出", _Symbol, EnumToString(InpMACD_TF_Exec));
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| エントリー条件チェック                                             |
//+------------------------------------------------------------------+
void CheckEntry()
{
    // 1. 先にシグナルオブジェクトをチャートに描画する
    for(int i = 0; i < ArraySize(allLines); i++)
    {
        CheckLineSignals(allLines[i]);
    }

    // 2. 描画されたシグナル（矢印）があるか確認する
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, PERIOD_M5, 0, 1, rates) < 1) return;
    datetime currentTime = rates[0].time;

    bool hasBuySignal  = false;
    bool hasSellSignal = false;

    for(int i = ObjectsTotal(0, -1, OBJ_ARROW) - 1; i >= 0; i--)
    {
        string   name    = ObjectName(0, i, -1, OBJ_ARROW);
        datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
        if(currentTime - objTime > InpDotTimeout) continue;
        if(StringFind(name, "_Buy") > 0) hasBuySignal = true;
        if(StringFind(name, "_Sell") > 0) hasSellSignal = true;
    }

    // --- 3. シグナルが発生した場合にのみ、フィルターとエントリー判断を行う ---
    if(hasBuySignal || hasSellSignal)
    {
        // 3-1. 時間フィルター
        if(InpEnableTimeFilter)
        {
            MqlDateTime time;
            TimeCurrent(time);
            int current_hour = time.hour;
            bool isOutsideHours = false;

            if(InpTradingHourStart > InpTradingHourEnd)
            {
                if(current_hour < InpTradingHourStart && current_hour >= InpTradingHourEnd) isOutsideHours = true;
            }
            else
            {
                if(current_hour < InpTradingHourStart || current_hour >= InpTradingHourEnd) isOutsideHours = true;
            }
            
            if(isOutsideHours)
            {
                PrintFormat("時間フィルター: 発生したシグナルをスキップしました (現在時刻 %d時)", current_hour);
                return;
            }
        }

        // 3-2. ボラティリティフィルター
        if(InpEnableVolatilityFilter)
        {
            double atr_buffer[];
            int atr_period_long = 100;
            if(CopyBuffer(h_atr, 0, 0, atr_period_long, atr_buffer) == atr_period_long)
            {
                double avg_atr = 0;
                for(int i = 0; i < atr_period_long; i++) avg_atr += atr_buffer[i];
                avg_atr /= atr_period_long;

                if(atr_buffer[0] > avg_atr * InpAtrMaxRatio)
                {
                    Print("ボラティリティフィルター: 発生したシグナルをスキップしました (ATR急騰)");
                    return;
                }
            }
        }

        // 3-3. フィルターを通過した場合、スコアリングとエントリー実行
        if(TimeCurrent() > lastTradeTime + 5)
        {
            MqlTick current_tick;
            if(!SymbolInfoTick(_Symbol, current_tick)) return;

            if(hasBuySignal && CountOpenPositions(POSITION_TYPE_BUY) < InpMaxPositions)
            {
                // ★★★ ここからが修正箇所 ★★★
                ScoreComponentInfo info = CalculateMACDScore(true);
                int score = info.total_score;
                // ★★★ ここまで ★★★
                PrintFormat("買いシグナル発生。MACDスコア: %d", score);

                string comment = "";
                if(score >= InpScore_High)
                {
                    comment = "High Score Buy (" + (string)score + ")";
                    PlaceOrder(true, current_tick.ask, 0, 0, comment, score);
                }
                else if(score >= InpScore_Standard)
                {
                    comment = "Standard Score Buy (" + (string)score + ")";
                    PlaceOrder(true, current_tick.ask, 0, 0, comment, score);
                }
            }

            if(hasSellSignal && CountOpenPositions(POSITION_TYPE_SELL) < InpMaxPositions)
            {
                // ★★★ ここからが修正箇所 ★★★
                ScoreComponentInfo info = CalculateMACDScore(false);
                int score = info.total_score;
                // ★★★ ここまで ★★★
                PrintFormat("売りシグナル発生。MACDスコア: %d", score);
                
                string comment = "";
                if(score >= InpScore_High)
                {
                    comment = "High Score Sell (" + (string)score + ")";
                    PlaceOrder(false, current_tick.bid, 0, 0, comment, score);
                }
                else if(score >= InpScore_Standard)
                {
                    comment = "Standard Score Sell (" + (string)score + ")";
                    PlaceOrder(false, current_tick.bid, 0, 0, comment, score);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ライン情報を更新する関数                                          |
//+------------------------------------------------------------------+
void UpdateLines()
{
    ArrayFree(allLines);

    if(InpUsePivotLines)
    {
        CalculatePivot();

        double supports[]       = {s1, s2, s3};
        color  support_colors[] = {(color)CLR_S1, (color)CLR_S2, (color)CLR_S3};
        for(int i = 0; i < 3; i++)
        {
            if(i > 0 && !InpShowS2R2) continue;
            if(i > 1 && !InpShowS3R3) continue;

            Line s_line;
            s_line.name          = "S" + IntegerToString(i + 1);
            s_line.price         = supports[i];
            s_line.type          = LINE_TYPE_SUPPORT;
            s_line.signalColor   = support_colors[i];
            s_line.isBrokeUp     = false;
            s_line.isBrokeDown   = false;
            s_line.waitForRetest = false;
            s_line.isInZone      = false;

            int new_size = ArraySize(allLines) + 1;
            ArrayResize(allLines, new_size);
            allLines[new_size - 1] = s_line;
        }

        double resistances[]    = {r1, r2, r3};
        color  resist_colors[]  = {(color)CLR_R1, (color)CLR_R2, (color)CLR_R3};
        for(int i = 0; i < 3; i++)
        {
            if(i > 0 && !InpShowS2R2) continue;
            if(i > 1 && !InpShowS3R3) continue;

            Line r_line;
            r_line.name          = "R" + IntegerToString(i + 1);
            r_line.price         = resistances[i];
            r_line.type          = LINE_TYPE_RESISTANCE;
            r_line.signalColor   = resist_colors[i];
            r_line.isBrokeUp     = false;
            r_line.isBrokeDown   = false;
            r_line.waitForRetest = false;
            r_line.isInZone      = false;

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
            if(StringFind(objName, "ManualTrend_") != 0)
                continue;

            string obj_text = ObjectGetString(0, objName, OBJPROP_TEXT);
            if(StringFind(obj_text, "-Broken") >= 0)
            {
                continue;
            }

            Line m_line;
            m_line.name        = "Manual_" + StringSubstr(objName, StringFind(objName, "_", 0) + 1);
            m_line.price       = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
            m_line.signalColor = (color)ObjectGetInteger(0, objName, OBJPROP_COLOR);
            m_line.type        = (m_line.price > tick.ask) ? LINE_TYPE_RESISTANCE : LINE_TYPE_SUPPORT;
            m_line.isBrokeUp   = false;
            m_line.isBrokeDown = false;
            m_line.waitForRetest = false;
            m_line.isInZone      = false;

            int new_size = ArraySize(allLines) + 1;
            ArrayResize(allLines, new_size);
            allLines[new_size - 1] = m_line;
        }
    }
}

//+------------------------------------------------------------------+
//| ラインごとのシグナル検知を行う関数                                |
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
                if(!InpAllowOuterTouch)
                    CreateSignalObject(InpArrowPrefix + "TouchBreak_Buy_" + line.name, prevBarTime, rates[1].low - offset, line.signalColor, InpTouchBreakUpCode, line.name + " タッチブレイク(買い)");
                line.isBrokeUp = true;
            }
            if(!line.isBrokeUp && rates[1].open <= line.price && rates[1].high >= line.price && rates[1].close <= line.price && rates[1].low < line.price)
            {
                CreateSignalObject(InpDotPrefix + "TouchRebound_Sell_" + line.name, prevBarTime, line.price + offset, line.signalColor, InpTouchReboundDownCode, line.name + " タッチ反発(売り)");
            }
        }
        else // LINE_TYPE_SUPPORT
        {
            if(!line.isBrokeDown && rates[1].open > line.price && rates[1].close <= line.price)
            {
                if(!InpAllowOuterTouch)
                    CreateSignalObject(InpArrowPrefix + "TouchBreak_Sell_" + line.name, prevBarTime, rates[1].high + offset, line.signalColor, InpTouchBreakDownCode, line.name + " タッチブレイク(売り)");
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
        double zone_lower = line.price - InpZonePips * g_pip;
        double zone_upper = line.price + InpZonePips * g_pip;
        if(line.type == LINE_TYPE_RESISTANCE)
        {
            if(rates[0].close >= line.price && rates[0].close < zone_upper) line.isInZone = true;
            else if(rates[0].close >= zone_upper || rates[0].close < line.price) line.isInZone = false;

            if(line.isInZone && rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "ZoneRebound_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpZoneReboundSellCode, line.name + " ゾーン内反発(売り)");
                line.isInZone = false;
            }
            if(rates[1].close > line.price && rates[0].close <= line.price)
            {
                CreateSignalObject(InpDotPrefix + "VReversal_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpVReversalSellCode, line.name + " V字回復(売り)");
            }
            if(InpBreakMode)
            {
                if(rates[0].close > zone_upper) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].high >= line.price && rates[0].close < line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Sell_" + line.name, currentTime, line.price + offset, line.signalColor, InpRetestSellCode, line.name + " B&R(売り)");
                    line.waitForRetest = false;
                }
            }
        }
        else // LINE_TYPE_SUPPORT
        {
            if(rates[0].close <= line.price && rates[0].close > zone_lower) line.isInZone = true;
            else if(rates[0].close <= zone_lower || rates[0].close > line.price) line.isInZone = false;

            if(line.isInZone && rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "ZoneRebound_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpZoneReboundBuyCode, line.name + " ゾーン内反発(買い)");
                line.isInZone = false;
            }
            if(rates[1].close < line.price && rates[0].close >= line.price)
            {
                CreateSignalObject(InpDotPrefix + "VReversal_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpVReversalBuyCode, line.name + " V字回復(買い)");
            }
            if(InpBreakMode)
            {
                if(rates[0].close < zone_lower) line.waitForRetest = true;
                if(line.waitForRetest && rates[0].low <= line.price && rates[0].close > line.price)
                {
                    CreateSignalObject(InpArrowPrefix + "Retest_Buy_" + line.name, currentTime, line.price - offset, line.signalColor, InpRetestBuyCode, line.name + " B&R(買い)");
                    line.waitForRetest = false;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| チャートイベント処理関数                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_buttonName)
    {
        g_isDrawingMode = !g_isDrawingMode;
        UpdateButtonState();
        return;
    }

    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_clearButtonName)
    {
        ClearSignalObjects();
        return;
    }

    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_clearLinesButtonName)
    {
        ClearManualLines();
        return;
    }

    if(id == CHARTEVENT_CLICK && g_isDrawingMode)
    {
        long btn_x = ObjectGetInteger(0, g_buttonName, OBJPROP_XDISTANCE);
        long btn_y = ObjectGetInteger(0, g_buttonName, OBJPROP_YDISTANCE);
        long btn_w = ObjectGetInteger(0, g_buttonName, OBJPROP_XSIZE);
        long btn_h = ObjectGetInteger(0, g_buttonName, OBJPROP_YSIZE);
        if(lparam >= btn_x && lparam <= (btn_x + btn_w) && (long)dparam >= btn_y && (long)dparam <= (btn_y + btn_h))
        {
            return;
        }

        int      subWindow;
        datetime time;
        double   price;
        if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, time, price))
        {
            if(subWindow == 0)
            {
                DrawManualTrendLine(price, time);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 新しいバーのチェック                                               |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    int      index         = (timeframe == PERIOD_M5) ? 0 : 1;
    datetime currentTime = iTime(_Symbol, timeframe, 0);
    if(currentTime != lastBar[index])
    {
        lastBar[index] = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| ピボット計算                                                     |
//+------------------------------------------------------------------+
void CalculatePivot()
{
    double high  = iHigh(_Symbol, InpPivotPeriod, 1);
    double low   = iLow(_Symbol, InpPivotPeriod, 1);
    double close = iClose(_Symbol, InpPivotPeriod, 1);
    pivot = (high + low + close) / 3.0;
    s1    = 2.0 * pivot - high;
    r1    = 2.0 * pivot - low;
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
//| ピボットライン描画                                               |
//+------------------------------------------------------------------+
void DrawPivotLine()
{
    datetime currentPeriodStart = iTime(_Symbol, InpPivotPeriod, 0);
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string   objName       = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(objName, InpLinePrefix_Pivot) != 0) continue;
        datetime lineStartTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
        if(lineStartTime < currentPeriodStart)
        {
            if((bool)ObjectGetInteger(0, objName, OBJPROP_RAY_RIGHT) == false) continue;
            ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, currentPeriodStart);
        }
    }
    string   timeStamp    = TimeToString(currentPeriodStart, TIME_DATE | TIME_MINUTES);
    StringReplace(timeStamp, ":", "_");
    StringReplace(timeStamp, ".", "_");
    datetime endPointTime = currentPeriodStart + PeriodSeconds(InpPivotPeriod);
    string   lineNameS1   = InpLinePrefix_Pivot + "S1_" + DoubleToString(s1, _Digits) + "_" + timeStamp;
    if(ObjectFind(0, lineNameS1) < 0) { if(ObjectCreate(0, lineNameS1, OBJ_TREND, 0, currentPeriodStart, s1, endPointTime, s1)) { ObjectSetInteger(0, lineNameS1, OBJPROP_COLOR, (color)CLR_S1); ObjectSetInteger(0, lineNameS1, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameS1, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameS1, OBJPROP_RAY_RIGHT, true); } }
    string   lineNameR1   = InpLinePrefix_Pivot + "R1_" + DoubleToString(r1, _Digits) + "_" + timeStamp;
    if(ObjectFind(0, lineNameR1) < 0) { if(ObjectCreate(0, lineNameR1, OBJ_TREND, 0, currentPeriodStart, r1, endPointTime, r1)) { ObjectSetInteger(0, lineNameR1, OBJPROP_COLOR, (color)CLR_R1); ObjectSetInteger(0, lineNameR1, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameR1, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameR1, OBJPROP_RAY_RIGHT, true); } }
    if(InpShowS2R2)
    {
        string lineNameS2 = InpLinePrefix_Pivot + "S2_" + DoubleToString(s2, _Digits) + "_" + timeStamp;
        if(ObjectFind(0, lineNameS2) < 0) { if(ObjectCreate(0, lineNameS2, OBJ_TREND, 0, currentPeriodStart, s2, endPointTime, s2)) { ObjectSetInteger(0, lineNameS2, OBJPROP_COLOR, (color)CLR_S2); ObjectSetInteger(0, lineNameS2, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameS2, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameS2, OBJPROP_RAY_RIGHT, true); } }
        string lineNameR2 = InpLinePrefix_Pivot + "R2_" + DoubleToString(r2, _Digits) + "_" + timeStamp;
        if(ObjectFind(0, lineNameR2) < 0) { if(ObjectCreate(0, lineNameR2, OBJ_TREND, 0, currentPeriodStart, r2, endPointTime, r2)) { ObjectSetInteger(0, lineNameR2, OBJPROP_COLOR, (color)CLR_R2); ObjectSetInteger(0, lineNameR2, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameR2, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameR2, OBJPROP_RAY_RIGHT, true); } }
    }
    if(InpShowS3R3)
    {
        string lineNameS3 = InpLinePrefix_Pivot + "S3_" + DoubleToString(s3, _Digits) + "_" + timeStamp;
        if(ObjectFind(0, lineNameS3) < 0) { if(ObjectCreate(0, lineNameS3, OBJ_TREND, 0, currentPeriodStart, s3, endPointTime, s3)) { ObjectSetInteger(0, lineNameS3, OBJPROP_COLOR, (color)CLR_S3); ObjectSetInteger(0, lineNameS3, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameS3, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameS3, OBJPROP_RAY_RIGHT, true); } }
        string lineNameR3 = InpLinePrefix_Pivot + "R3_" + DoubleToString(r3, _Digits) + "_" + timeStamp;
        if(ObjectFind(0, lineNameR3) < 0) { if(ObjectCreate(0, lineNameR3, OBJ_TREND, 0, currentPeriodStart, r3, endPointTime, r3)) { ObjectSetInteger(0, lineNameR3, OBJPROP_COLOR, (color)CLR_R3); ObjectSetInteger(0, lineNameR3, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, lineNameR3, OBJPROP_WIDTH, 1); ObjectSetInteger(0, lineNameR3, OBJPROP_RAY_RIGHT, true); } }
    }
}

//+------------------------------------------------------------------+
//| 手動ラインの管理（足ごとに延長、ブレイクで停止）                 |
//+------------------------------------------------------------------+
void ManageManualLines()
{
    MqlRates rates[];
    if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;

    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, OBJ_TREND);

        if(StringFind(objName, "ManualTrend_") != 0) continue;

        string obj_text = ObjectGetString(0, objName, OBJPROP_TEXT);
        if(StringFind(obj_text, "-Broken") >= 0) continue;

        double line_price = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
        bool   is_broken  = false;

        string line_role = ObjectGetString(0, objName, OBJPROP_TEXT);

        if(StringFind(line_role, "Resistance") >= 0 && rates[1].close > line_price)
        {
            is_broken = true;
        }
        else if(StringFind(line_role, "Support") >= 0 && rates[1].close < line_price)
        {
            is_broken = true;
        }

        if(is_broken)
        {
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, rates[1].time);
            ObjectSetString(0, objName, OBJPROP_TEXT, obj_text + "-Broken");
        }
        else
        {
            datetime new_end_time = rates[0].time + PeriodSeconds(_Period);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, new_end_time);
        }
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 保有ポジション数をカウントする関数                                |
//+------------------------------------------------------------------+
int CountOpenPositions(long direction)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            if(PositionGetInteger(POSITION_TYPE) == direction)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| シグナルオブジェクト作成                                          |
//+------------------------------------------------------------------+
void CreateSignalObject(string name, datetime dt, double price, color clr, int code, string print_msg)
{
    string unique_name = name + "_" + TimeToString(dt, TIME_MINUTES|TIME_SECONDS);
    if(ObjectFind(0, unique_name) < 0 && (TimeCurrent() - lastArrowTime) > 5)
    {
        if(ObjectCreate(0, unique_name, OBJ_ARROW, 0, dt, price))
        {
            ObjectSetInteger(0, unique_name, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, unique_name, OBJPROP_ARROWCODE, code);
            ObjectSetInteger(0, unique_name, OBJPROP_WIDTH, InpSignalWidth);
            ObjectSetString(0, unique_name, OBJPROP_FONT, "Wingdings");
            ObjectSetInteger(0, unique_name, OBJPROP_FONTSIZE, InpSignalFontSize);
            PrintFormat("%s: %s", print_msg, unique_name);
            lastArrowTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| ダイバージェンスサインを描画する                                  |
//+------------------------------------------------------------------+
void DrawDivergenceSignal(datetime time, double price, color clr)
{
    // 設定が無効なら描画しない
    if(!InpShowDivergenceSignals) return;

    string obj_name = InpDivSignalPrefix + TimeToString(time, TIME_DATE|TIME_MINUTES);
    
    // 既に存在する場合は描画しない
    if(ObjectFind(0, obj_name) >= 0) return;

    if(ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price))
    {
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, InpDivSymbolCode);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, InpDivSymbolSize);
    }
}

//+------------------------------------------------------------------+
//| 注文発行                                                         |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double price, double slPrice, double tpPrice, string comment, int score)
{
    MqlTradeRequest request = {};
    MqlTradeResult  result  = {};
    
    request.action   = TRADE_ACTION_DEAL;
    request.symbol   = _Symbol;
    request.volume   = InpLotSize;
    request.type     = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price    = NormalizeDouble(price, _Digits);
    request.magic    = InpMagicNumber;
    request.comment  = comment;
    
    // --- SL/TP設定ロジックを一旦削除 ---
    // 将来、動的SL/TPを実装する際に、ここに新しいロジックを追加します。
    // request.sl = slPrice;
    // request.tp = tpPrice;

    if(!OrderSend(request, result))
    {
        PrintFormat("エントリー失敗: %d, Comment: %s", result.retcode, comment);
    }
    else
    {
        PrintFormat("エントリー成功: %s", comment);
        lastTradeTime = TimeCurrent();
        
        if(result.deal > 0)
        {
            if(PositionSelectByTicket(result.order))
            {
                PositionInfo newPos;
                newPos.ticket = PositionGetInteger(POSITION_TICKET);
                newPos.score = score;
                
                int size = ArraySize(g_managedPositions);
                ArrayResize(g_managedPositions, size + 1);
                g_managedPositions[size] = newPos;
                
                PrintFormat("新規ポジションを管理リストに追加. Ticket: %d, Score: %d", newPos.ticket, newPos.score);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ボタンを作成する関数                                              |
//+------------------------------------------------------------------+
void CreateButton()
{
    ObjectCreate(0, g_buttonName, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, g_buttonName, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, g_buttonName, OBJPROP_YDISTANCE, 50);
    ObjectSetInteger(0, g_buttonName, OBJPROP_XSIZE, 120);
    ObjectSetInteger(0, g_buttonName, OBJPROP_YSIZE, 20);
    ObjectSetString(0, g_buttonName, OBJPROP_TEXT, "手動ライン描画 OFF");
    ObjectSetInteger(0, g_buttonName, OBJPROP_BGCOLOR, C'220,220,220');
    ObjectSetInteger(0, g_buttonName, OBJPROP_STATE, false);
    ObjectSetInteger(0, g_buttonName, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| シグナル消去ボタンを作成する関数                                  |
//+------------------------------------------------------------------+
void CreateClearButton()
{
    ObjectCreate(0, g_clearButtonName, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_YDISTANCE, 75);
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_XSIZE, 120);
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_YSIZE, 20);
    ObjectSetString(0, g_clearButtonName, OBJPROP_TEXT, "シグナル消去");
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_BGCOLOR, C'255,228,225');
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_STATE, false);
    ObjectSetInteger(0, g_clearButtonName, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| 手動ライン消去ボタンを作成する関数                                |
//+------------------------------------------------------------------+
void CreateClearLinesButton()
{
    ObjectCreate(0, g_clearLinesButtonName, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_YDISTANCE, 100);
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_XSIZE, 120);
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_YSIZE, 20);
    ObjectSetString(0, g_clearLinesButtonName, OBJPROP_TEXT, "手動ライン消去");
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_BGCOLOR, C'225,240,255');
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_STATE, false);
    ObjectSetInteger(0, g_clearLinesButtonName, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| ボタンの表示状態を更新する関数                                    |
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
//| シグナルオブジェクトを消去する関数                                |
//+------------------------------------------------------------------+
void ClearSignalObjects()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, -1);
        if(StringFind(objName, InpDotPrefix) == 0 || StringFind(objName, InpArrowPrefix) == 0)
        {
            ObjectDelete(0, objName);
        }
    }
    ChartRedraw();
    Print("シグナルオブジェクトを消去しました。");
}

//+------------------------------------------------------------------+
//| 手動ラインを消去する関数                                          |
//+------------------------------------------------------------------+
void ClearManualLines()
{
    for(int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, OBJ_TREND);
        if(StringFind(objName, "ManualTrend_") == 0)
        {
            ObjectDelete(0, objName);
        }
    }
    UpdateLines();
    ChartRedraw();
    Print("手動ラインを消去しました。");
}

//+------------------------------------------------------------------+
//| 手動のトレンドラインを描画する関数                                |
//+------------------------------------------------------------------+
void DrawManualTrendLine(double price, datetime time)
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;

    color  line_color;
    string line_role_text;

    if(price < tick.ask)
    {
        line_color     = p_ManualSupport_Color;
        line_role_text = "Support";
    }
    else
    {
        line_color     = p_ManualResist_Color;
        line_role_text = "Resistance";
    }

    string lineName = "ManualTrend_" + TimeToString(TimeCurrent(), TIME_SECONDS);

    datetime time1 = time;
    datetime time2 = time + PeriodSeconds(_Period);

    if(ObjectCreate(0, lineName, OBJ_TREND, 0, time1, price, time2, price))
    {
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, line_color);
        ObjectSetString(0, lineName, OBJPROP_TEXT, line_role_text);
        ObjectSetInteger(0, lineName, OBJPROP_STYLE, p_ManualLine_Style);
        ObjectSetInteger(0, lineName, OBJPROP_WIDTH, p_ManualLine_Width);
        ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);

        string tooltip_text = StringFormat("%s Line (Price: %.*f)", line_role_text, _Digits, price);
        ObjectSetString(0, lineName, OBJPROP_TOOLTIP, tooltip_text);

        UpdateLines();
        ManageManualLines();
    }
}