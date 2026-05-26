//+------------------------------------------------------------------+
//|                                         PendingOrderWrapper.mqh  |
//|                    MQL5 Reusable Stops-Level Pending Order Wrapper|
//|                                                      Version 1.0 |
//+------------------------------------------------------------------+
#ifndef __PENDING_ORDER_WRAPPER_MQH__
#define __PENDING_ORDER_WRAPPER_MQH__

#include <Trade\Trade.mqh>

class CPendingOrderWrapper
{
private:
   CTrade            m_trade;

public:
                     CPendingOrderWrapper();
                    ~CPendingOrderWrapper() {}

   void              SetMagicNumber(int magic) { m_trade.SetExpertMagicNumber(magic); }

   // Core method to execute/wrap Buy Pending Orders
   bool              BuyPending(double volume, double entryPrice, string symbol, double sl, double tp, 
                                ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, datetime expiration = 0, 
                                string comment = "");

   // Core method to execute/wrap Sell Pending Orders
   bool              SellPending(double volume, double entryPrice, string symbol, double sl, double tp, 
                                 ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, datetime expiration = 0, 
                                 string comment = "");
};

CPendingOrderWrapper::CPendingOrderWrapper() {}

//+------------------------------------------------------------------+
//| Wrap Buy Pending Stop Order request dynamically                 |
//+------------------------------------------------------------------+
bool CPendingOrderWrapper::BuyPending(double volume, double entryPrice, string symbol, double sl, double tp, 
                                      ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel <= 0) stopsLevel = 2 * spread;
   double minDistance = stopsLevel * point;

   // Mode A: Market Order (too close to Ask price)
   if(MathAbs(entryPrice - ask) < minDistance)
   {
      double marketSL = (sl > 0) ? NormalizeDouble(ask - MathAbs(entryPrice - sl), digits) : 0;
      if(marketSL > 0 && ask - marketSL < minDistance)
         marketSL = NormalizeDouble(ask - minDistance, digits);

      double marketTP = (tp > 0) ? NormalizeDouble(ask + MathAbs(tp - entryPrice), digits) : 0;
      if(marketTP > 0 && marketTP - ask < minDistance)
         marketTP = NormalizeDouble(ask + minDistance, digits);

      PrintFormat("[Wrapper] MARKET BUY executed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", ask, marketSL, marketTP, stopsLevel);
      return m_trade.Buy(volume, symbol, 0.0, marketSL, marketTP, comment + "_mkt");
   }
   // Mode B: Limit Order (price has run past entryPrice)
   else if(ask >= entryPrice + minDistance)
   {
      double limitSL = sl;
      if(limitSL > 0 && entryPrice - limitSL < minDistance)
         limitSL = NormalizeDouble(entryPrice - minDistance, digits);

      double limitTP = tp;
      if(limitTP > 0 && limitTP - entryPrice < minDistance)
         limitTP = NormalizeDouble(entryPrice + minDistance, digits);

      PrintFormat("[Wrapper] BUY LIMIT placed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", entryPrice, limitSL, limitTP, stopsLevel);
      return m_trade.BuyLimit(volume, entryPrice, symbol, limitSL, limitTP, type_time, expiration, comment + "_lim");
   }
   // Mode C: Stop Order (normal, ask <= entryPrice - minDistance)
   else
   {
      double stopSL = sl;
      if(stopSL > 0 && entryPrice - stopSL < minDistance)
         stopSL = NormalizeDouble(entryPrice - minDistance, digits);

      double stopTP = tp;
      if(stopTP > 0 && stopTP - entryPrice < minDistance)
         stopTP = NormalizeDouble(entryPrice + minDistance, digits);

      PrintFormat("[Wrapper] BUY STOP placed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", entryPrice, stopSL, stopTP, type_time, expiration, comment);
      return m_trade.BuyStop(volume, entryPrice, symbol, stopSL, stopTP, type_time, expiration, comment);
   }
}

//+------------------------------------------------------------------+
//| Wrap Sell Pending Stop Order request dynamically                |
//+------------------------------------------------------------------+
bool CPendingOrderWrapper::SellPending(double volume, double entryPrice, string symbol, double sl, double tp, 
                                       ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel <= 0) stopsLevel = 2 * spread;
   double minDistance = stopsLevel * point;

   // Mode A: Market Order (too close to Bid price)
   if(MathAbs(entryPrice - bid) < minDistance)
   {
      double marketSL = (sl > 0) ? NormalizeDouble(bid + MathAbs(sl - entryPrice), digits) : 0;
      if(marketSL > 0 && marketSL - bid < minDistance)
         marketSL = NormalizeDouble(bid + minDistance, digits);

      double marketTP = (tp > 0) ? NormalizeDouble(bid - MathAbs(entryPrice - tp), digits) : 0;
      if(marketTP > 0 && bid - marketTP < minDistance)
         marketTP = NormalizeDouble(bid - minDistance, digits);

      PrintFormat("[Wrapper] MARKET SELL executed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", bid, marketSL, marketTP, stopsLevel);
      return m_trade.Sell(volume, symbol, 0.0, marketSL, marketTP, comment + "_mkt");
   }
   // Mode B: Limit Order (price has run past entryPrice)
   else if(bid <= entryPrice - minDistance)
   {
      double limitSL = sl;
      if(limitSL > 0 && limitSL - entryPrice < minDistance)
         limitSL = NormalizeDouble(entryPrice + minDistance, digits);

      double limitTP = tp;
      if(limitTP > 0 && entryPrice - limitTP < minDistance)
         limitTP = NormalizeDouble(entryPrice - minDistance, digits);

      PrintFormat("[Wrapper] SELL LIMIT placed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", entryPrice, limitSL, limitTP, type_time, expiration, comment + "_lim");
      return m_trade.SellLimit(volume, entryPrice, symbol, limitSL, limitTP, type_time, expiration, comment + "_lim");
   }
   // Mode C: Stop Order (normal, bid >= entryPrice + minDistance)
   else
   {
      double stopSL = sl;
      if(stopSL > 0 && stopSL - entryPrice < minDistance)
         stopSL = NormalizeDouble(entryPrice + minDistance, digits);

      double stopTP = tp;
      if(stopTP > 0 && entryPrice - stopTP < minDistance)
         stopTP = NormalizeDouble(entryPrice - minDistance, digits);

      PrintFormat("[Wrapper] SELL STOP placed at %.5f (SL: %.5f, TP: %.5f) [Stops Level: %d]", entryPrice, stopSL, stopTP, type_time, expiration, comment);
      return m_trade.SellStop(volume, entryPrice, symbol, stopSL, stopTP, type_time, expiration, comment);
   }
}

#endif // __PENDING_ORDER_WRAPPER_MQH__
