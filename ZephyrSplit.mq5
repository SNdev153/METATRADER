#property copyright "Your Name"
#property link      "https://www.mql5.com"
#property version   "2.74" // バージョンを更新
#property description "手動TPラインが意図せず上書きされる不具合を修正した最終版"

//--- Enum Definitions
enum ENUM_EXIT_LOGIC {
    EXIT_FIFO,         // 先入れ先出し (従来通り)
    EXIT_UNFAVORABLE,  // 不利なポジションから決済 (推奨)
    EXIT_FAVORABLE     // 有利なポジションから決済 (利益確定優先)
};

enum ENUM_TP_MODE {
    MODE_ZIGZAG,
    MODE_PIPS_ADJUST
};

enum ENUM_POSITION_MODE {
    MODE_AGGREGATE, // 集約モード (平均単価)
    MODE_INDIVIDUAL // 個別モード (ポジションごと)
};

//--- Input Parameters
input ENUM_POSITION_MODE InpPositionMode = MODE_AGGREGATE; // ポジション管理モード
input ENUM_EXIT_LOGIC InpExitLogic = EXIT_UNFAVORABLE; // 分割決済のロジック
input int    InpMaxPositionsPerSide  = 3;         // 同方向の最大ポジション数
input int    InpSplitCount         = 5;         // 分割決済の回数
input double InpExitBufferPips     = 1.0;       // 決済バッファ (Pips)。価格がTPラインのこのPips数手前に来たら決済する。
input bool   InpEnableButtons      = true;      // ボタン表示を有効にする
input long   InpMagicNumber        = 789012;    // Zephyrテストポジションのマジックナンバー
input long   InpTargetMagic        = 123456;    // 外部ポジションのマジックナンバー（例：ZoneEntryEA）
input bool   InpUseTestEntry       = true;      // テストエントリーを有効にする（買い/売り）
input double InpTestEntryLotSize   = 0.1;       // テストエントリーのロットサイズ
input double InpZigzagDepthLevel2  = 50.0;      // ZigZagのレベル2の深さ（USD）
input double InpZigzagDepthLevel3  = 200.0;     // ZigZagのレベル3の深さ（USD）
input ENUM_TP_MODE InpTPLineMode   = MODE_ZIGZAG;// TPラインのモード
input bool   InpEnableKeyboard     = false;     // キーボードショートカットを有効にする
input double InpTPProximityPips    = 1000.0;    // TPライン近接時のエントリー停止Pips (例: 100pips = 1000)
input double InpMinProfitYen       = 1000.0;    // 最終TP決済時の最低利益額（円、損失側の場合のみ）
input int    InpBreakEvenAfterSplits = 2;       // 分割決済後にブレイクイーブン設定する回数（0=無効）
input bool   InpDebugMode          = false;     // デバッグモード（詳細ログ出力）

// --- [1] INDIVIDUAL MODE DATA ---
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
};
SplitData splitPositions[];

// --- [2] AGGREGATE MODE DATA ---
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
};
PositionGroup buyGroup;
PositionGroup sellGroup;

// --- ポジションをソートするための構造体 ---
struct SortablePosition {
    ulong  ticket;
    double openPrice;
};

//--- Global Variables
double prevBuyTotalLots = 0;
double prevSellTotalLots = 0;
int    prevPositionsTotal = 0;
double zonalFinalTPLine_Buy, zonalFinalTPLine_Sell;
int    zigzagHandle;
bool   isHedgingAllowed = true;
bool   skipUpdateSplitLines = false;
bool   isDragging = false;
string selectedLine = "";
datetime lastClickTime = 0;
bool   isBuyTPManuallyMoved = false;
bool   isSellTPManuallyMoved = false;

//--- Button Names
#define BUTTON_BUY_CLOSE_ALL  "Button_BuyCloseAll"
#define BUTTON_SELL_CLOSE_ALL "Button_SellCloseAll"
#define BUTTON_ALL_CLOSE      "Button_AllClose"
#define BUTTON_RESET_BUY_TP   "Button_ResetBuyTP"
#define BUTTON_RESET_SELL_TP  "Button_ResetSellTP"


// ===================================================================
// --- AGGREGATE MODE FUNCTIONS ---
// ===================================================================

void InitGroup(PositionGroup &group, bool isBuy) {
    group.isBuy = isBuy;
    group.isActive = false;
    group.averageEntryPrice = 0;
    group.totalLotSize = 0;
    group.initialTotalLotSize = 0;
    group.splitsDone = 0;
    group.openTime = 0;
    group.stampedFinalTP = 0; 
    ArrayResize(group.positionTickets, 0);
    ArrayResize(group.splitPrices, InpSplitCount);
    ArrayResize(group.splitLineNames, InpSplitCount);
    ArrayResize(group.splitLineTimes, InpSplitCount);
    for(int i = 0; i < InpSplitCount; i++) {
        group.splitLineNames[i] = "SplitLine_" + (isBuy ? "BUY" : "SELL") + "_" + IntegerToString(i);
        group.splitLineTimes[i] = 0;
    }
}

void ManagePositionGroups() {
    int totalPositions = PositionsTotal();
    
    if (totalPositions == prevPositionsTotal && totalPositions > 0) return;

    // ★ 修正点: InitGroupでリセットされる前に、現在のTP価格を一時的に保存する
    double preservedBuyTP = buyGroup.stampedFinalTP;
    double preservedSellTP = sellGroup.stampedFinalTP;

    InitGroup(buyGroup, true);
    InitGroup(sellGroup, false);

    // ★ 修正点: InitGroupでリセットされた後、保存しておいたTP価格を書き戻す
    buyGroup.stampedFinalTP = preservedBuyTP;
    sellGroup.stampedFinalTP = preservedSellTP;
    
    double buyWeightedSum = 0;
    double sellWeightedSum = 0;
    
    for(int i = totalPositions - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if(magic == InpMagicNumber || magic == InpTargetMagic) {
                double price = PositionGetDouble(POSITION_PRICE_OPEN);
                double volume = PositionGetDouble(POSITION_VOLUME);
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    buyGroup.isActive = true;
                    buyGroup.totalLotSize += volume;
                    buyWeightedSum += price * volume;
                    if(buyGroup.openTime == 0 || openTime < buyGroup.openTime) buyGroup.openTime = openTime;
                    int size = ArraySize(buyGroup.positionTickets);
                    ArrayResize(buyGroup.positionTickets, size + 1);
                    buyGroup.positionTickets[size] = ticket;
                } else { // SELL
                    sellGroup.isActive = true;
                    sellGroup.totalLotSize += volume;
                    sellWeightedSum += price * volume;
                    if(sellGroup.openTime == 0 || openTime < sellGroup.openTime) sellGroup.openTime = openTime;
                    int size = ArraySize(sellGroup.positionTickets);
                    ArrayResize(sellGroup.positionTickets, size + 1);
                    sellGroup.positionTickets[size] = ticket;
                }
            }
        }
    }
    
    if(buyGroup.isActive) {
        if (buyGroup.totalLotSize > 0) buyGroup.averageEntryPrice = buyWeightedSum / buyGroup.totalLotSize;
        
        if(buyGroup.totalLotSize > prevBuyTotalLots) {
            Print("[GROUP] 買いグループ更新: ポジション数=", ArraySize(buyGroup.positionTickets), ", 合計Lot=", buyGroup.totalLotSize);
            
            if (!isBuyTPManuallyMoved) {
                buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
                Print("[GROUP] 買いグループの決済目標を自動刻印しました: ", buyGroup.stampedFinalTP);
            } else {
                Print("[GROUP] 手動設定済みの買いTPを維持します: ", buyGroup.stampedFinalTP);
            }

            if (buyGroup.totalLotSize > buyGroup.initialTotalLotSize) {
                 buyGroup.initialTotalLotSize = buyGroup.totalLotSize;
                 buyGroup.splitsDone = 0;
                 for(int k=0; k<InpSplitCount; k++) buyGroup.splitLineTimes[k] = 0;
                 Print("[GROUP] 買いグループにポジションが追加されたため、分割決済状況をリセットします。");
            }
            UpdateGroupSplitLines(buyGroup);
        }
    } else if (prevBuyTotalLots > 0) {
        Print("[GROUP] 買いグループの全ポジションが決済されました。");
        DeleteGroupSplitLines(buyGroup);
        isBuyTPManuallyMoved = false;
    }

    if(sellGroup.isActive) {
        if(sellGroup.totalLotSize > 0) sellGroup.averageEntryPrice = sellWeightedSum / sellGroup.totalLotSize;
        
        if(sellGroup.totalLotSize > prevSellTotalLots) {
            Print("[GROUP] 売りグループ更新: ポジション数=", ArraySize(sellGroup.positionTickets), ", 合計Lot=", sellGroup.totalLotSize);
            
            if (!isSellTPManuallyMoved) {
                sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
                Print("[GROUP] 売りグループの決済目標を自動刻印しました: ", sellGroup.stampedFinalTP);
            } else {
                Print("[GROUP] 手動設定済みの売りTPを維持します: ", sellGroup.stampedFinalTP);
            }
            
            if (sellGroup.totalLotSize > sellGroup.initialTotalLotSize) {
                sellGroup.initialTotalLotSize = sellGroup.totalLotSize;
                sellGroup.splitsDone = 0;
                for(int k=0; k<InpSplitCount; k++) sellGroup.splitLineTimes[k] = 0;
                Print("[GROUP] 売りグループにポジションが追加されたため、分割決済状況をリセットします。");
            }
            UpdateGroupSplitLines(sellGroup);
        }
    } else if (prevSellTotalLots > 0) {
        Print("[GROUP] 売りグループの全ポジションが決済されました。");
        DeleteGroupSplitLines(sellGroup);
        isSellTPManuallyMoved = false;
    }

    prevPositionsTotal = totalPositions;
    prevBuyTotalLots = buyGroup.totalLotSize;
    prevSellTotalLots = sellGroup.totalLotSize;
}

void DeleteGroupSplitLines(PositionGroup &group) {
    string prefix = "SplitLine_" + (group.isBuy ? "BUY" : "SELL") + "_";
    ObjectsDeleteAll(0, prefix);
}

void UpdateGroupSplitLines(PositionGroup &group) {
    DeleteGroupSplitLines(group);
    if(!group.isActive) return;

    double tpPrice = group.stampedFinalTP;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) {
       if(InpDebugMode) Print("[WARN] グループの刻印済みTP価格が無効です。分割ラインは更新されません。");
       return;
    }

    double priceDiff = MathAbs(tpPrice - group.averageEntryPrice);
    double step = priceDiff / InpSplitCount;
    
    for(int i = 0; i < InpSplitCount; i++) {
        if (group.splitLineTimes[i] > 0) continue;
        
        group.splitPrices[i] = group.isBuy ? group.averageEntryPrice + step * (i + 1) :
                                             group.averageEntryPrice - step * (i + 1);
        string lineName = group.splitLineNames[i];
        ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, group.splitPrices[i]);
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, group.isBuy ? clrGoldenrod : clrPurple);
        ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetString(0, lineName, OBJPROP_TEXT, "Split #" + IntegerToString(i + 1));
        ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 5);
    }
}

void CheckExitForGroup(PositionGroup &group) {
    if (!group.isActive || group.splitsDone >= InpSplitCount) return;

    double currentPrice = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double nextSplitPrice = group.splitPrices[group.splitsDone];

    if (nextSplitPrice <= 0) return;
    if (TimeCurrent() - group.openTime < 5) return;

    double priceBuffer = InpExitBufferPips * _Point;
    bool splitPriceReached = (group.isBuy && currentPrice >= (nextSplitPrice - priceBuffer)) || 
                             (!group.isBuy && currentPrice <= (nextSplitPrice + priceBuffer));

    if (splitPriceReached && group.splitLineTimes[group.splitsDone] == 0) {
        if (group.splitsDone == InpSplitCount - 1) {
            Print("[EXIT] 最終分割(TP)到達。グループの全ポジションを決済します。TP=", nextSplitPrice);
            CloseAllPositionsInGroup(group);
            
            group.splitLineTimes[group.splitsDone] = TimeCurrent();
            group.splitsDone++;
            if (group.isBuy) {
                if (!isBuyTPManuallyMoved) { /* 何もしない */ }
            } else {
                if (!isSellTPManuallyMoved) { /* 何もしない */ }
            }
        } 
        else {
            double splitLot = NormalizeDouble(group.initialTotalLotSize / InpSplitCount, 2);
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(splitLot < minLot) splitLot = minLot;

            if(ExecuteGroupSplitExit(group, splitLot)) {
                group.splitLineTimes[group.splitsDone] = TimeCurrent();
                string lineName = group.splitLineNames[group.splitsDone];
                if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
                ObjectCreate(0, lineName, OBJ_TREND, 0, group.openTime, nextSplitPrice, TimeCurrent(), nextSplitPrice);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, group.isBuy ? clrLightGoldenrod : clrLightBlue);
                ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 5);

                group.splitsDone++;
                
                if (InpBreakEvenAfterSplits > 0 && group.splitsDone == InpBreakEvenAfterSplits) {
                    SetBreakEvenForGroup(group);
                }
            }
        }
    }
}

void CloseAllPositionsInGroup(PositionGroup &group) {
    ulong ticketsToClose[];
    ArrayCopy(ticketsToClose, group.positionTickets);
    for(int i = 0; i < ArraySize(ticketsToClose); i++) {
        ClosePosition(ticketsToClose[i]);
    }
}

bool ExecuteGroupSplitExit(PositionGroup &group, double lotToClose)
{
    if (InpExitLogic == EXIT_FIFO)
    {
        double remainingLotToClose = lotToClose;
        bool result = false;
        for (int i = 0; i < ArraySize(group.positionTickets); i++) {
            ulong ticket = group.positionTickets[i];
            if (!PositionSelectByTicket(ticket)) continue;
            
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            MqlTradeRequest request = {};
            MqlTradeResult tradeResult = {};
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.type_filling = ORDER_FILLING_IOC;

            if (remainingLotToClose >= posVolume) {
                request.volume = posVolume;
                if(OrderSend(request, tradeResult)) {
                    remainingLotToClose -= posVolume;
                    result = true;
                }
            } else {
                if (remainingLotToClose > 0.00001) {
                    request.volume = remainingLotToClose;
                    if(OrderSend(request, tradeResult)) {
                        remainingLotToClose = 0;
                        result = true;
                    }
                }
            }
            if (remainingLotToClose <= 0.00001) break;
        }
        return result;
    }

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

    bool isBuy = group.isBuy;
    for (int i = 0; i < ticketCount - 1; i++) {
        for (int j = 0; j < ticketCount - i - 1; j++) {
            bool shouldSwap = false;
            if (InpExitLogic == EXIT_UNFAVORABLE) {
                if ((isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice) ||
                    (!isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice)) {
                    shouldSwap = true;
                }
            }
            else { // EXIT_FAVORABLE
                if ((isBuy && positionsToSort[j].openPrice > positionsToSort[j+1].openPrice) ||
                    (!isBuy && positionsToSort[j].openPrice < positionsToSort[j+1].openPrice)) {
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

    double remainingLotToClose = lotToClose;
    bool result = false;
    for (int i = 0; i < ticketCount; i++) {
        ulong ticket = positionsToSort[i].ticket;
        if (!PositionSelectByTicket(ticket)) continue;

        double posVolume = PositionGetDouble(POSITION_VOLUME);
        MqlTradeRequest request = {};
        MqlTradeResult tradeResult = {};
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.type = group.isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = group.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.type_filling = ORDER_FILLING_IOC;

        if (remainingLotToClose >= posVolume) {
            request.volume = posVolume;
            if(OrderSend(request, tradeResult)) {
                remainingLotToClose -= posVolume;
                result = true;
            }
        } else {
            if (remainingLotToClose > 0.00001) {
                request.volume = remainingLotToClose;
                if(OrderSend(request, tradeResult)) {
                    remainingLotToClose = 0;
                    result = true;
                }
            }
        }
        if (remainingLotToClose <= 0.00001) break;
    }
    
    if (result) {
        string modeStr = (InpExitLogic == EXIT_UNFAVORABLE) ? "不利なポジションから" : "有利なポジションから";
        PrintFormat("[EXIT] %sのロジックで %.2f ロットの分割決済を実行しました。", modeStr, lotToClose);
    }
    return result;
}

void SetBreakEvenForGroup(PositionGroup &group) {
    for(int i = 0; i < ArraySize(group.positionTickets); i++) {
        if(PositionSelectByTicket(group.positionTickets[i])) {
            SetBreakEven(group.positionTickets[i], group.averageEntryPrice);
        }
    }
}

// ===================================================================
// --- INDIVIDUAL MODE FUNCTIONS ---
// ===================================================================

bool HasPosition(bool isBuy) {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetTicket(i)) {
            if( (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber || PositionGetInteger(POSITION_MAGIC) == InpTargetMagic) &&
                PositionGetInteger(POSITION_TYPE) == (isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL) ) {
                return true;
            }
        }
    }
    return false;
}

void UpdateSplitLines() {
    for(int i = 0; i < ArraySize(splitPositions); i++) {
        if(!PositionSelectByTicket(splitPositions[i].ticket)) continue;
        
        double tpPrice = splitPositions[i].stampedFinalTP;
        if(tpPrice <= 0 || tpPrice == DBL_MAX) continue;

        double priceDiff = MathAbs(tpPrice - splitPositions[i].entryPrice);
        double step = priceDiff / InpSplitCount;

        for(int j = splitPositions[i].splitsDone; j < InpSplitCount; j++) {
            double newSplitPrice = splitPositions[i].isBuy ? splitPositions[i].entryPrice + step * (j + 1) :
                                                             splitPositions[i].entryPrice - step * (j + 1);
            if(MathAbs(newSplitPrice - splitPositions[i].splitPrices[j]) > _Point) {
                splitPositions[i].splitPrices[j] = newSplitPrice;
                if (ObjectFind(0, splitPositions[i].splitLineNames[j]) >= 0) {
                    ObjectMove(0, splitPositions[i].splitLineNames[j], 0, 0, newSplitPrice);
                }
            }
        }
    }
}

void DetectNewEntrances() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if(magic == InpMagicNumber || magic == InpTargetMagic) {
                bool exists = false;
                for(int j = 0; j < ArraySize(splitPositions); j++) {
                    if(splitPositions[j].ticket == ticket) {
                        exists = true;
                        break;
                    }
                }
                if(!exists) AddSplitData(ticket);
            }
        }
    }
}

void AddSplitData(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    SplitData newSplit;
    newSplit.ticket = ticket;
    newSplit.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    newSplit.lotSize = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
    newSplit.isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
    newSplit.splitsDone = 0;
    newSplit.openTime = (datetime)PositionGetInteger(POSITION_TIME);
    
    newSplit.stampedFinalTP = newSplit.isBuy ? zonalFinalTPLine_Buy : zonalFinalTPLine_Sell;
    Print("[INDIVIDUAL] ポジション ", ticket, " の決済目標を刻印しました: ", newSplit.stampedFinalTP);

    double tpPrice = newSplit.stampedFinalTP;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) {
       if(InpDebugMode) Print("[WARN] ポジション ", ticket, " の刻印済みTP価格が無効です。");
       tpPrice = newSplit.isBuy ? newSplit.entryPrice + 1000 * _Point : newSplit.entryPrice - 1000 * _Point;
    }

    double priceDiff = MathAbs(tpPrice - newSplit.entryPrice);
    ArrayResize(newSplit.splitPrices, InpSplitCount);
    ArrayResize(newSplit.splitLineNames, InpSplitCount);
    ArrayResize(newSplit.splitLineTimes, InpSplitCount);
    double step = priceDiff / InpSplitCount;

    for(int i = 0; i < InpSplitCount; i++) {
        newSplit.splitPrices[i] = newSplit.isBuy ? newSplit.entryPrice + step * (i + 1) :
                                                   newSplit.entryPrice - step * (i + 1);
        string lineName = "SplitLine_" + IntegerToString(ticket) + "_" + IntegerToString(i);
        newSplit.splitLineNames[i] = lineName;
        newSplit.splitLineTimes[i] = 0;
        ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, newSplit.splitPrices[i]);
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, newSplit.isBuy ? clrGoldenrod : clrPurple);
        ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 5);
    }

    int size = ArraySize(splitPositions);
    ArrayResize(splitPositions, size + 1);
    splitPositions[size] = newSplit;
}

void DeleteSplitLines(SplitData &split) {
    for(int i = 0; i < ArraySize(split.splitLineNames); i++) {
        if(ObjectFind(0, split.splitLineNames[i]) >= 0) ObjectDelete(0, split.splitLineNames[i]);
    }
}

bool ExecuteSplitExit(ulong ticket, double lot, SplitData &split, int splitIndex) {
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

    if(!OrderSend(request, result)) return false;

    string lineName = split.splitLineNames[splitIndex];
    double splitPrice = split.splitPrices[splitIndex];
    split.splitLineTimes[splitIndex] = TimeCurrent();
    if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
    ObjectCreate(0, lineName, OBJ_TREND, 0, split.openTime, splitPrice, TimeCurrent(), splitPrice);
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, split.isBuy ? clrLightGoldenrod : clrLightBlue);
    ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 5);
    
    return true;
}

void CheckExits() {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    for(int i = ArraySize(splitPositions) - 1; i >= 0; i--) {
        if(!PositionSelectByTicket(splitPositions[i].ticket)) {
            DeleteSplitLines(splitPositions[i]);
            ArrayRemove(splitPositions, i, 1);
            continue;
        }
        
        if(splitPositions[i].splitsDone >= InpSplitCount) continue;

        double currentPrice = splitPositions[i].isBuy ? bid : ask;
        double nextSplitPrice = splitPositions[i].splitPrices[splitPositions[i].splitsDone];
        
        if (nextSplitPrice <= 0) continue;

        double priceBuffer = InpExitBufferPips * _Point;
        bool splitPriceReached = (splitPositions[i].isBuy && currentPrice >= (nextSplitPrice - priceBuffer)) || 
                                 (!splitPositions[i].isBuy && currentPrice <= (nextSplitPrice + priceBuffer));
        
        if(splitPriceReached && splitPositions[i].splitLineTimes[splitPositions[i].splitsDone] == 0) {
            double remainingLot = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
            if (remainingLot <= 0.0) continue;

            if (splitPositions[i].splitsDone == InpSplitCount - 1) {
                Print("[EXIT] 最終分割(TP)到達。ポジション ", splitPositions[i].ticket, " を決済します。");
                bool wasBuy = splitPositions[i].isBuy;
                ClosePosition(splitPositions[i].ticket);
                if (wasBuy) {
                    if (!isBuyTPManuallyMoved) { /* 何もしない */ }
                } else {
                    if (!isSellTPManuallyMoved) { /* 何もしない */ }
                }
            }
            else {
                double splitLot = NormalizeDouble(splitPositions[i].lotSize / InpSplitCount, 2);
                if(splitLot < minLot) splitLot = minLot;
                if(splitLot > remainingLot) splitLot = remainingLot;

                if(ExecuteSplitExit(splitPositions[i].ticket, splitLot, splitPositions[i], splitPositions[i].splitsDone)) {
                    splitPositions[i].splitsDone++;
                    if(InpBreakEvenAfterSplits > 0 && splitPositions[i].splitsDone == InpBreakEvenAfterSplits) {
                        SetBreakEven(splitPositions[i].ticket, splitPositions[i].entryPrice);
                    }
                }
            }
        }
    }
}

// ===================================================================
// --- COMMON AND EVENT HANDLER FUNCTIONS ---
// ===================================================================

int OnInit() {
    long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    isHedgingAllowed = marginMode == 2;
    
    string modeText = (InpPositionMode == MODE_AGGREGATE) ? "集約モード" : "個別モード";
    PrintFormat("[INIT] ポジション管理モード: %s", modeText);

    zigzagHandle = iCustom(_Symbol, _Period, "ZigZag", 12, 5, 3);
    if(zigzagHandle == INVALID_HANDLE) {
        Print("[ERROR] ZigZagインジケーターの初期化に失敗");
        return(INIT_FAILED);
    }
    
    if (InpPositionMode == MODE_AGGREGATE) {
        InitGroup(buyGroup, true);
        InitGroup(sellGroup, false);
    } else {
        ArrayResize(splitPositions, 0);
    }
    
    if(InpEnableButtons) {
        CreateButton(BUTTON_BUY_CLOSE_ALL, 10, 50, 100, 25, "BUY全決済", clrDodgerBlue);
        CreateButton(BUTTON_SELL_CLOSE_ALL, 115, 50, 100, 25, "SELL全決済", clrTomato);
        CreateButton(BUTTON_ALL_CLOSE, 220, 50, 100, 25, "全決済", clrGray);
        CreateButton(BUTTON_RESET_BUY_TP, 325, 50, 100, 25, "BUY TPリセット", clrGoldenrod);
        CreateButton(BUTTON_RESET_SELL_TP, 430, 50, 100, 25, "SELL TPリセット", clrGoldenrod);
    }

    if(ObjectFind(0, "TPLine_Buy") >= 0) {
        zonalFinalTPLine_Buy = ObjectGetDouble(0, "TPLine_Buy", OBJPROP_PRICE);
        isBuyTPManuallyMoved = true;
        Print("[INIT] 既存の買いTPラインを検出: 価格=", zonalFinalTPLine_Buy);
    }
    if(ObjectFind(0, "TPLine_Sell") >= 0) {
        zonalFinalTPLine_Sell = ObjectGetDouble(0, "TPLine_Sell", OBJPROP_PRICE);
        isSellTPManuallyMoved = true;
        Print("[INIT] 既存の売りTPラインを検出: 価格=", zonalFinalTPLine_Sell);
    }

    UpdateZones();
    if (InpPositionMode == MODE_AGGREGATE) ManagePositionGroups(); else DetectNewEntrances();
    
    EventSetMillisecondTimer(100);
    Print("[INIT] 初期化完了");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    IndicatorRelease(zigzagHandle);
    
    if (InpPositionMode == MODE_AGGREGATE) {
        ObjectsDeleteAll(0, "SplitLine_BUY_");
        ObjectsDeleteAll(0, "SplitLine_SELL_");
    } else {
        ObjectsDeleteAll(0, "SplitLine_"); 
    }
    
    if(InpEnableButtons) {
        ObjectDelete(0, BUTTON_BUY_CLOSE_ALL);
        ObjectDelete(0, BUTTON_SELL_CLOSE_ALL);
        ObjectDelete(0, BUTTON_ALL_CLOSE);
        ObjectDelete(0, BUTTON_RESET_BUY_TP);
        ObjectDelete(0, BUTTON_RESET_SELL_TP);
    }
    EventKillTimer();
    Print("[DEINIT] EA終了: 理由=", reason);
}

void OnTick() {
    UpdateZones();

    if (InpPositionMode == MODE_AGGREGATE) {
        ManagePositionGroups();
        CheckExitForGroup(buyGroup);
        CheckExitForGroup(sellGroup);
    } else { // MODE_INDIVIDUAL
        DetectNewEntrances();
        CheckExits();
    }

    if (InpUseTestEntry) {
        if (InpPositionMode == MODE_AGGREGATE) {
            if (ArraySize(buyGroup.positionTickets) < InpMaxPositionsPerSide) {
                PlaceTestEntry(true);
            }
            if (ArraySize(sellGroup.positionTickets) < InpMaxPositionsPerSide) {
                PlaceTestEntry(false);
            }
        } 
        else {
            bool hasBuyPos = HasPosition(true);
            if (!hasBuyPos) {
                PlaceTestEntry(true);
            }
            bool hasSellPos = HasPosition(false);
            if (!hasSellPos) {
                PlaceTestEntry(false);
            }
        }
    }
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_DRAG) {
        bool isBuyLine = (sparam == "TPLine_Buy");
        bool isSellLine = (sparam == "TPLine_Sell");

        if (isBuyLine || isSellLine) {
            double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0);
            
            if(isBuyLine){
                if (!isBuyTPManuallyMoved || zonalFinalTPLine_Buy != newPrice) {
                    isBuyTPManuallyMoved = true; 
                    zonalFinalTPLine_Buy = newPrice;
                    ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                    Print("[MANUAL] 買いTPラインが手動で移動されました: ", newPrice);
                }
            } else { // isSellLine
                if (!isSellTPManuallyMoved || zonalFinalTPLine_Sell != newPrice) {
                    isSellTPManuallyMoved = true;
                    zonalFinalTPLine_Sell = newPrice;
                    ObjectSetInteger(0, sparam, OBJPROP_STYLE, STYLE_SOLID);
                    Print("[MANUAL] 売りTPラインが手動で移動されました: ", newPrice);
                }
            }
            
            if (InpPositionMode == MODE_AGGREGATE) {
                if (isBuyLine && buyGroup.isActive) {
                    buyGroup.stampedFinalTP = newPrice;
                    UpdateGroupSplitLines(buyGroup);
                } else if (isSellLine && sellGroup.isActive) {
                    sellGroup.stampedFinalTP = newPrice;
                    UpdateGroupSplitLines(sellGroup);
                }
            } else { // MODE_INDIVIDUAL
                for (int i=0; i < ArraySize(splitPositions); i++) {
                    if ((isBuyLine && splitPositions[i].isBuy) || (isSellLine && !splitPositions[i].isBuy)) {
                        splitPositions[i].stampedFinalTP = newPrice;
                    }
                }
                UpdateSplitLines();
            }
            ChartRedraw();
        }
    }

    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == BUTTON_BUY_CLOSE_ALL) {
            Print("[BUTTON] BUY全決済ボタンが押されました。");
            if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup); else Print("対象の買いポジションがありません。");
            return;
        }
        if(sparam == BUTTON_SELL_CLOSE_ALL) {
            Print("[BUTTON] SELL全決済ボタンが押されました。");
            if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup); else Print("対象の売りポジションがありません。");
            return;
        }
        if(sparam == BUTTON_ALL_CLOSE) {
            Print("[BUTTON] 全決済ボタンが押されました。");
            if(buyGroup.isActive) CloseAllPositionsInGroup(buyGroup);
            if(sellGroup.isActive) CloseAllPositionsInGroup(sellGroup);
            if(!buyGroup.isActive && !sellGroup.isActive) Print("対象のポジションがありません。");
            return;
        }
        if(sparam == BUTTON_RESET_BUY_TP) {
            Print("[BUTTON] BUY TPリセットボタンが押されました。");
            isBuyTPManuallyMoved = false; 
            UpdateZones(); 
            if(buyGroup.isActive) {
                buyGroup.stampedFinalTP = zonalFinalTPLine_Buy;
                Print("[RESET] 買いグループの決済目標をリセットしました: ", buyGroup.stampedFinalTP);
                UpdateGroupSplitLines(buyGroup);
            }
            ChartRedraw();
            return;
        }
        if(sparam == BUTTON_RESET_SELL_TP) {
            Print("[BUTTON] SELL TPリセットボタンが押されました。");
            isSellTPManuallyMoved = false;
            UpdateZones();
            if(sellGroup.isActive) {
                sellGroup.stampedFinalTP = zonalFinalTPLine_Sell;
                Print("[RESET] 売りグループの決済目標をリセットしました: ", sellGroup.stampedFinalTP);
                UpdateGroupSplitLines(sellGroup);
            }
            ChartRedraw();
            return;
        }
    }
}

void ClosePosition(ulong ticket) {
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    if(!PositionSelectByTicket(ticket)) return;
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.type_filling = ORDER_FILLING_IOC;
    
    if(!OrderSend(request, result)) {
        PrintFormat("ERROR: Failed to close position #%d. Error %d", ticket, GetLastError());
    }
}

bool SetBreakEven(ulong ticket, double entryPrice) {
    if(!PositionSelectByTicket(ticket)) return false;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = NormalizeDouble(entryPrice, _Digits);
    request.tp = PositionGetDouble(POSITION_TP);
    
    return OrderSend(request, result);
}

double GetLastEntryPrice(const PositionGroup &group) {
    if (!group.isActive || ArraySize(group.positionTickets) == 0) {
        return 0.0;
    }

    double lastPrice = 0.0;
    datetime lastTime = 0;

    for (int i = 0; i < ArraySize(group.positionTickets); i++) {
        if (PositionSelectByTicket(group.positionTickets[i])) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if (openTime > lastTime || lastTime == 0) {
                lastTime = openTime;
                lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            }
        }
    }
    return lastPrice;
}

void ProcessEntryLogicForGroup(PositionGroup &group, bool isBuy) {
    double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool canPlaceOrder = false;

    if (!group.isActive) {
        PrintFormat("[ENTRY] %s方向: 最初のポジションのエントリー条件をチェック", isBuy ? "BUY" : "SELL");
        canPlaceOrder = true;
    }
    else {
        double lastEntryPrice = GetLastEntryPrice(group);
        if (lastEntryPrice <= 0) {
            if(InpDebugMode) PrintFormat("[ENTRY] %s方向: 最終エントリー価格を取得できず中止", isBuy ? "BUY" : "SELL");
            return;
        }

        double entryInterval = InpTPProximityPips * _Point;
        double priceDiff = MathAbs(currentPrice - lastEntryPrice);

        PrintFormat("[ENTRY] %s方向 ナンピンチェック: Curr:%.5f, Last:%.5f, Diff:%.1f pips, Interval:%.1f pips",
                    isBuy ? "BUY" : "SELL", currentPrice, lastEntryPrice, priceDiff / _Point, entryInterval / _Point);

        if (priceDiff >= entryInterval) {
            canPlaceOrder = true;
        }
    }

    if (canPlaceOrder) {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.volume = NormalizeDouble(InpTestEntryLotSize, 2);
        request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.price = currentPrice;
        request.magic = InpMagicNumber;
        request.comment = "Test Entry";
        request.type_filling = ORDER_FILLING_IOC;

        if(!OrderSend(request, result)) {
            PrintFormat("[ERROR] テストエントリー失敗: %s, Error=%d", isBuy ? "BUY" : "SELL", GetLastError());
        } else {
            PrintFormat("[ENTRY] テストエントリー成功: %s, Ticket=%d", isBuy ? "BUY" : "SELL", result.deal);
        }
    }
}

void PlaceTestEntry(bool isBuy) {
    double tpPrice = isBuy ? zonalFinalTPLine_Buy : zonalFinalTPLine_Sell;
    if(tpPrice <= 0 || tpPrice == DBL_MAX) {
        if(InpDebugMode) PrintFormat("[ENTRY] %s方向: TPライン未設定のためエントリーをスキップ", isBuy ? "BUY" : "SELL");
        return;
    }
    
    double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double distanceToTP_pips = MathAbs(currentPrice - tpPrice) / _Point;
    if(distanceToTP_pips <= InpTPProximityPips) {
        if(InpDebugMode) PrintFormat("[ENTRY] %s方向: エントリー中止（TP近接）。距離=%.1f pips", isBuy ? "BUY" : "SELL", distanceToTP_pips);
        return;
    }

    if (isBuy) {
        ProcessEntryLogicForGroup(buyGroup, true);
    } else {
        ProcessEntryLogicForGroup(sellGroup, false);
    }
}

void UpdateZones() {
    double zigzag[];
    ArraySetAsSeries(zigzag, true);
    if(CopyBuffer(zigzagHandle, 0, 0, 100, zigzag) <= 0) {
        return;
    }

    double level3High = 0, level3Low = DBL_MAX;
    for(int i = 0; i < 100; i++) {
        if(zigzag[i] > 0) {
            if(zigzag[i] > level3High) level3High = zigzag[i];
            if(zigzag[i] < level3Low) level3Low = zigzag[i];
        }
    }

    if(!isBuyTPManuallyMoved) {
        double newBuyTP = 0;
        ENUM_LINE_STYLE lineStyle = STYLE_DOT;

        if(level3High > 0) {
            newBuyTP = level3High;
            lineStyle = STYLE_SOLID;
        } 
        else {
            const int tracking_period = 15;
            int high_idx = iHighest(_Symbol, _Period, MODE_HIGH, tracking_period, 1);
            if(high_idx != -1) {
                newBuyTP = iHigh(_Symbol, _Period, high_idx);
            }
        }

        if (newBuyTP > 0 && MathAbs(newBuyTP - zonalFinalTPLine_Buy) > _Point) {
            zonalFinalTPLine_Buy = newBuyTP;
            
            string lineName = "TPLine_Buy";
            if(ObjectFind(0, lineName) < 0) {
                ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, zonalFinalTPLine_Buy);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrGold);
                ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            } else {
                ObjectMove(0, lineName, 0, 0, zonalFinalTPLine_Buy);
            }
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, lineStyle);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false); 
            ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 10);
            
            if (buyGroup.isActive) UpdateGroupSplitLines(buyGroup);
        }
    }

    if(!isSellTPManuallyMoved) {
        double newSellTP = 0;
        ENUM_LINE_STYLE lineStyle = STYLE_DOT;

        if(level3Low < DBL_MAX) {
            newSellTP = level3Low;
            lineStyle = STYLE_SOLID;
        } else {
            const int tracking_period = 15;
            int low_idx = iLowest(_Symbol, _Period, MODE_LOW, tracking_period, 1);
            if(low_idx != -1) {
                newSellTP = iLow(_Symbol, _Period, low_idx);
            }
        }
        
        if (newSellTP > 0 && MathAbs(newSellTP - zonalFinalTPLine_Sell) > _Point) {
            zonalFinalTPLine_Sell = newSellTP;
            
            string lineName = "TPLine_Sell";
            if(ObjectFind(0, lineName) < 0) {
                ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, zonalFinalTPLine_Sell);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrMediumPurple);
                ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            } else {
                ObjectMove(0, lineName, 0, 0, zonalFinalTPLine_Sell);
            }
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, lineStyle);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false); 
            ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 10);

            if (sellGroup.isActive) UpdateGroupSplitLines(sellGroup);
        }
    }
}


bool CreateButton(string name, int x, int y, int width, int height, string text, color clr) {
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STATE, false);
    return true;
}

double GetProfitInJPY(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return 0.0;
    double profit = PositionGetDouble(POSITION_PROFIT);
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    if(accountCurrency == "JPY") return profit;

    string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    if(profitCurrency == "JPY") return profit;

    string conversionPair = profitCurrency + "JPY";
    double conversionRate = SymbolInfoDouble(conversionPair, SYMBOL_BID);

    if(conversionRate <= 0) {
        if(profitCurrency == "USD") {
            conversionRate = SymbolInfoDouble("USDJPY", SYMBOL_BID);
        } else {
            string profitToUsdPair = profitCurrency + "USD";
            double profitToUsdRate = SymbolInfoDouble(profitToUsdPair, SYMBOL_BID);
            
            string usdToProfitPair = "USD" + profitCurrency;
            double usdToProfitRate = SymbolInfoDouble(usdToProfitPair, SYMBOL_BID);

            double usdJpyRate = SymbolInfoDouble("USDJPY", SYMBOL_BID);
            
            if(usdJpyRate > 0) {
                if(profitToUsdRate > 0) conversionRate = profitToUsdRate * usdJpyRate;
                else if (usdToProfitRate > 0) conversionRate = (1.0 / usdToProfitRate) * usdJpyRate;
            }
        }
    }
    if(conversionRate > 0) return profit * conversionRate;
    return profit;
}