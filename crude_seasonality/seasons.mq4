//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Jay Benedict Alfaras"
#property version   "1.00"
#property strict


#include <B63/Generic.mqh>


int xti_signals []= {1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, 1};
int brent_signals [] = {1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1};
int nat_gas_signals [] = {-1, -1, 1, 1, 1, 1, -1, -1, 1, 1, 1, 1};
int au_signals[] = {1, 1, 1, 1, -1, 1, -1, -1, -1, 1, -1, 1};
int nz_signals[] = {-1, 1, -1, 1, -1, 1, -1, -1, 1, 1, 1, 1};
float sl_percentage = 1;
float tp_percentage = 5;



input int         InpMagic    = 232323;
input float       InpRiskAmt  = 50;

int         stored_balance = 100000;

struct SSignals{
   int signals_main[];
   
   void update_signals(int &inp_signals[]){
      ArrayFree(signals_main);
      ArrayResize(signals_main, ArraySize(inp_signals));
      for (int i = 0; i < ArraySize(inp_signals); i++){
         signals_main[i] = inp_signals[i];
      }
   }
   
   SSignals(){
      ArrayFree(signals_main);
   } 
};

struct STradeParams{
   double volume;
   float sl_price;
   float tp_price;
   float open_price;
   int bias;
   
   void update_trade_params(float inp_vol, float inp_sl, float inp_tp, float inp_open_price){
      volume = inp_vol;
      sl_price = inp_sl;
      tp_price = inp_tp;
      open_price = inp_open_price;
      bias = get_signal();
   }
   
   STradeParams(){
      update_trade_params(0, 0, 0, 0);
   }
};

struct SDayParams{
   float upper_limit;
   float lower_limit;
   float day_open_price;
   float target_lower;
   float target_upper;
   
   float sell_sl;
   float buy_sl;
   
   void update_day_params(){
      day_open_price = iOpen(Symbol(), PERIOD_D1, 0);
      upper_limit = day_open_price * (1 + (sl_percentage / 100));
      lower_limit = day_open_price * (1 - (sl_percentage / 100));
      
      sell_sl = upper_limit * (1 + (sl_percentage / 100));
      buy_sl = lower_limit * (1 - (sl_percentage / 100));
      
      target_lower = day_open_price * (1 - (tp_percentage / 100));
      target_upper = day_open_price * (1 + (tp_percentage / 100));
   }
   
   SDayParams(){
      update_day_params();
   }
};

STradeParams s_trade_params;
SDayParams s_day_params;
SSignals s_signals;

int OnInit()
  {
//---
   
   select_signal();
   calculate_volume();
   get_signal();
//---
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
//---
   
  }
void OnTick()
  {
//---
   if (IsNewCandle()){
      process();
   }
  }
  
  
void process(){
   //close_all_orders();
   //if (TimeDayOfWeek(TimeCurrent()) == 5){close_all_orders();}
   close_all_orders();
   delete_all_orders();
   s_trade_params.bias = get_signal();
   calculate_volume();
   
   PrintFormat("Signal: %i, Volume: %f, SL: %f", s_trade_params.bias, s_trade_params.volume, s_trade_params.sl_price);
   
   send_order();

   
}

void select_signal(){
   
   if (Symbol() == "XTIUSD"){
      s_signals.update_signals(xti_signals);
   }
   else if (Symbol() == "XBRUSD"){
      s_signals.update_signals(brent_signals);
   }
   else if (Symbol() == "XNGUSD"){
      s_signals.update_signals(nat_gas_signals);
   }
}

int get_signal(){
   // gets signal from signals list based on month
   int month = TimeMonth(TimeCurrent());
   int signal_index = month - 1;
   if (ArraySize(s_signals.signals_main) == 0){
      return 0;
   }
   //int bias = xti_signals[signal_index];
   int bias = s_signals.signals_main[signal_index];
   return bias;
}

int get_reference_price(){
   return 0;
}

int get_entry_window(){
   return 0;
}



float calculate_volume(){
   //internally calculate volume 
   s_day_params.update_day_params();
   int contract_size = MarketInfo(Symbol(), MODE_LOTSIZE);
   float volume = (InpRiskAmt / (s_day_params.day_open_price * (sl_percentage / 100) * contract_size));
   
   float sl = 0;
   float tp = 0;
   float open_price = 0;
   switch(s_trade_params.bias){
      case 1:
         sl = s_day_params.buy_sl;
         tp = s_day_params.target_upper;
         open_price = s_day_params.lower_limit;
         break;
      case -1:
         sl = s_day_params.sell_sl;
         tp = s_day_params.target_lower;
         open_price = s_day_params.upper_limit;
         break;
      default:
         break;
   }
   
   s_trade_params.update_trade_params(volume, sl, tp, open_price);
   return 0;
}


void send_order(){
   ENUM_ORDER_TYPE order_type = s_trade_params.bias == 1 ? OP_BUYLIMIT : OP_SELLLIMIT;
   PrintFormat("Signal: %i, Volume: %f, SL: %f, TP: %f, OpenPrice: %f, DayOpen: %f", s_trade_params.bias, s_trade_params.volume, s_trade_params.sl_price, s_trade_params.tp_price, s_trade_params.open_price, s_day_params.day_open_price);
   float minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   float volume = minLot > s_trade_params.volume ? minLot : s_trade_params.volume;

   float order_price = s_trade_params.bias == 1 ? Bid : Ask;   
   //int order_price = NormalizeDouble(s_trade_params.open_price, 2);
   
   double threshold = 5;
   double drawdown_factor = 1 - (threshold / 100);
   float account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (account_balance > stored_balance) stored_balance = account_balance; 
   
   float drawdown_limit = stored_balance * drawdown_factor;
   Print("factor: ", drawdown_limit);
   
   
   
   float vol = account_balance > drawdown_limit ? 5 : 5;
   
   int ticket = OrderSend(Symbol(), order_type, vol, NormalizeDouble(order_price, 2), 3, s_trade_params.sl_price, s_trade_params.tp_price, NULL, InpMagic, 0, clrNONE);
   Print("Order Sent: ", ticket);
   
   // MODIFY TRAIL
   // NOT WORKING
   //modify_all_sl(s_trade_params.sl_price);
}

void modify_all_sl(float trail_stop){
   for (int i = 0; i < OrdersTotal(); i++){
      int t = OrderSelect(0, SELECT_BY_POS, MODE_TRADES);
      if (OrderProfit() < 0) { continue; }
      int m = OrderModify(OrderTicket(), OrderOpenPrice(), trail_stop, OrderTakeProfit(), 0, clrNONE);
      if (m) { Print("Order Modified: ", OrderTicket()); }
   }
}

void close_all_orders(){
   /*
   Closing Conditions:
   1. losing trade
   2. friday (close all regardless of profit size)
   
   */
   for (int i = 0; i < OrdersTotal(); i++){
      int t = OrderSelect(0, SELECT_BY_POS, MODE_TRADES);
      if (OrderProfit() < 0){ continue; } // ignore if mid-week and trade is in profit
      int c = OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrNONE);
      if (c){ Print("Closed: ", OrderTicket()); }
   }
}

void delete_all_orders(){
   
   for (int i = 0; i < OrdersTotal(); i++){
      
      int t = OrderSelect(0, SELECT_BY_POS, MODE_TRADES);
      if (OrderType() == OP_BUY || OrderType() == OP_SELL){
         continue;
      }
      int c = OrderDelete(OrderTicket(), clrNONE);
      if (c){
         Print("Deleted: ", OrderTicket());
      }
   }
}

bool open_positions(){
   //iterate through order pool, find any trades with matching date, symbol, and magic number

   return False;
}

bool orders_opened_today(){
   //iterate through history, find any trades with matching date, symbol, and magic number

   return False;
}

/*
TODO
1. order type based on signal
2. reference price: daily open
3. entry window? 
4. order limit per day
5. stop loss percentage from daily open price
6. calculate volume using price delta

ON INTERVAL: 
1. check for open orders
2. check if order has been opened today
3. 
*/