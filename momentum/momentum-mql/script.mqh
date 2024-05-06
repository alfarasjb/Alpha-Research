


/*
   This file contains a script for a generic Momentum strategy.  
   
   DISCLAIMER: This script does not guarantee future profits, and is 
   created for demonstration purposes only. Do not use this script 
   with live funds. 
*/

#include <utilities/Utilities.mqh> 
#include <utilities/TradeOps.mqh> 

enum TradeSignal { Long, Short, None }; 

input int      InpMagic       = 111111; // Magic Number
input int      InpSpreadPeriod            = 10;
input double   InpSpreadThreshold         = 2; 


class CMomentumTrade : CTradeOps {
private:
      int      spread_period_; 
      double   spread_upper_threshold_, spread_lower_threshold_; 
      
      TradeSignal    Signal(); 
      double         SpreadValue(); 
      int            SendOrder(TradeSignal signal); 
      
      
public:
      CMomentumTrade(); 
      ~CMomentumTrade() {}
      
      void           Stage();
}; 


CMomentumTrade::CMomentumTrade()
   : CTradeOps(Symbol(), InpMagic)
   , spread_period_ (InpSpreadPeriod)
   , spread_upper_threshold_ (InpSpreadThreshold)
   , spread_lower_threshold_ (-InpSpreadThreshold) {}
   

double         CMomentumTrade::SpreadValue() {
   return iCustom(NULL,PERIOD_CURRENT, "\\b63\\statistics\\z_score",spread_period_,0,0,1); 
}

TradeSignal    CMomentumTrade::Signal() {
   double spread_value = SpreadValue(); 
   if (spread_value <= spread_lower_threshold_) return Short; 
   if (spread_value >= spread_upper_threshold_) return Long; 
   return None; 
}

int            CMomentumTrade::SendOrder(TradeSignal signal) {
   ENUM_ORDER_TYPE order_type; 
   double entry_price;
   switch(signal) {
      case Long:
         order_type  = ORDER_TYPE_BUY; 
         entry_price = UTIL_PRICE_ASK();
         OP_OrdersCloseBatchOrderType(ORDER_TYPE_SELL); 
         break; 
      case Short:
         order_type  = ORDER_TYPE_SELL;
         entry_price = UTIL_PRICE_BID(); 
         OP_OrdersCloseBatchOrderType(ORDER_TYPE_BUY); 
         break; 
      case None:
         return -1; 
      default:
         return -1; 
   }
   return OP_OrderOpen(Symbol(), order_type, UTIL_SYMBOL_MINLOT(), entry_price, 0, 0, NULL); 
}

void           CMomentumTrade::Stage() {
   OP_OrdersCloseAll(); 
   
   TradeSignal signal = Signal(); 
   
   if (signal == None) {
      return; 
   }
   SendOrder(signal); 
}

CMomentumTrade momentum;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   if (UTIL_IS_NEW_CANDLE()) {
      momentum.Stage();
   }
   
  }
//+------------------------------------------------------------------+


