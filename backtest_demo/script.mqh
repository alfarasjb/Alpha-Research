
#define app_copyright "Copyright 2023, Jay Alfaras"
#define app_version "1.21"
#define app_description "A script for implementing a daily seasonal sytem"
#property strict


#include <B63/Generic.mqh>

#ifdef __MQL5__
#include <Trade/Trade.mqh>
CTrade Trade;
#endif 

enum Orders{
   Long = 0,
   Short = 1,
};

enum SpreadManagement{
   Interval = 0, 
   Recursive = 1,
   Ignore = 2,
};

enum TradeManagement{
   Breakeven = 0, 
   Trailing = 1,
   None = 2,
};


/*
INPUTS:
-------
// ===== RISK PROFILE ===== //
Optimized Hyperparameters from python backtest. Will be scaled accordingly based on 
input RISK AMOUNT and ALLOCATION.

Deposit: 
   Initial Deposit Conducted in main Python backtest.
   
Risk Percent:
   Optimized Risk Percent from Python Backtest.
   
Lot:
   Optimized Lot from Python Backtest
   
Hold Time:
   Optimized Hold Time from Python Backtest
   
Order Type:
   Order Type from Python Backtest
   
Timeframe:
   Timeframe from Python Backtest
   
Spread:
   Entry Window Mean Spread from Python Backtest
   
// ===== ENTRY WINDOW ===== // 
ENTRY WINDOW HOUR:
   Entry Time (Hour)
   
ENTRY WINDOW MINUTE: 
   Entry Time (Minute)
   
// ===== RISK MANAGEMENT ===== // 
RISK AMOUNT:
   Overall Aggregated Risk Amount (Overall loss if basket fails)
   
   User Defined. 
   
   Scales True Risk Amount from Risk Profile to match this. 
   
   Scales True Lot Size based on Risk Amount
   
ALLOCATION: 
   Percentage of overall RISK AMOUNT to allocate to this instrument. 
   
   Example: 
      Deposit - 100000 USD
      Risk Amount - 1000 USD (1% - specified by Risk Profile)
      Allocation - 0.3 (30% of total Risk Amount is allocated to this instrument)
      
      True Risk Amount - 1000 USD * 0.3 = 300 USD 

TRAIL INTERVAL:
   Minimum distance from market price to update trail stop. 
   
TRADE MANAGEMENT:
   Trade Management Option
      1. Breakeven -> Sets breakeven within trade window. Closes trade at deadline. 
      2. Trailing -> Updates trail stop until hit by market price. Manually closes trade if in floating loss.
      3. None -> Closes at deadline.
      
      
// ===== MISC ===== // 
SPREAD MANAGEMENT:
   Technique for handling bad spreads. 
      1. Interval -> If bad spread, enters on next timeframe interval
      2. Recursive -> If bad spread, executes a while loop with a delay specified by InpSpreadDelay (seconds)
            Breaks the loop if spread improves, and price is within initial bid-ask range set with entry window
            candle opening price. (Executing recursion causes problems)
      3. Ignore -> Does nothing. Halts trading for the day.
      
SPREAD DELAY:
   Delay in seconds to execute recursive loop. 

MAGIC NUMBER:
   Magic Number
   
// ===== LOGGING ===== //
CSV LOGGING:
   Enables/Disables CSV Logging
  
TERMINAL LOGGING:
   Enables/Disables Terminal Logging   
*/

// ========== INPUTS ========== //
input string            InpRiskProfile    = "========== RISK PROFILE =========="; // ========== RISK PROFILE ==========
input float             InpRPDeposit      = 100000; // RISK PROFILE: Deposit
input float             InpRPRiskPercent  = 1; // RISK PROFILE: Risk Percent
input float             InpRPLot          = 10; // RISK PROFILE: Lot
input int               InpRPHoldTime     = 5; // RISK PROFILE: Hold Time
input Orders            InpRPOrderType    = Long; // RISK PROFILE: Order Type
input ENUM_TIMEFRAMES   InpRPTimeframe    = PERIOD_M15; // RISK PROFILE: Timeframe
input float             InpRPSpread       = 10; // RISK PROFILE: Spread

input string            InpEntry          = "========== ENTRY WINDOW =========="; // ========== ENTRY WINDOW ==========
input int               InpEntryHour      = 1; // ENTRY WINDOW HOUR 
input int               InpEntryMin       = 0; // ENTRY WINDOW MINUTE

input string            InpRiskMgt        = "========== RISK MANAGEMENT =========="; // ========== RISK MANAGEMENT ==========
input float             InpRiskAmount     = 1000; // RISK AMOUNT - Scales lot to match risk amount (10 lots / 1000USD)
input float             InpAllocation     = 1; // ALLOCATION - Percentage of Total Risk
input TradeManagement   InpTradeMgt       = None; // TRADE MANAGEMENT - BE / Trail Stop
input float             InpTrailInterval  = 50; // TRAIL STOP INTERVAL - Trail Points Increment


input string            InpMisc           = "========== MISC =========="; // ========== MISC ==========
input SpreadManagement  InpSpreadMgt      = Recursive; // SPREAD MANAGEMENT
input float             InpSpreadDelay    = 1; // SPREAD DELAY (seconds)
input int               InpMagic          = 232323; // MAGIC NUMBER


input string            InpLog            = "========== LOGGING =========="; // ========== LOGGING ==========
input bool              InpLogging        = true; // CSV LOGGING - Enables/Disables Trade Logging
input bool              InpTerminalMsg    = true; // TERMINAL LOGGING - Enables/Disables Terminal Logging

// ========== INPUTS ========== //




struct RiskProfile{
   double RP_amount;
   float RP_lot;
   int RP_holdtime;
   Orders RP_order_type;
   ENUM_TIMEFRAMES RP_timeframe;
   float RP_spread;
   
   RiskProfile(){
      set_risk_profile();
   }
   
   void set_risk_profile(){
      RP_amount = (InpRPRiskPercent / 100) * InpRPDeposit;
      RP_lot = InpRPLot;
      RP_holdtime = InpRPHoldTime; //
      RP_order_type = InpRPOrderType;
      RP_timeframe = InpRPTimeframe;
      RP_spread = InpRPSpread;
   }
};


struct TradeParameters{
   /*
   Holds trade parameters. Entry price, sl, tick val, trade points.
   */
   float order_lot;
   double entry_price;
   double sl_price;
   double tick_value;
   double trade_points;
   double delayed_entry_reference;
   
   double true_risk;
   double true_lot;
   TradeParameters(){
      
      tick_value = tick_val();
      trade_points = trade_pts();
   }
   
   double calc_lot(){
   
      double risk_amount_scale_factor = InpRiskAmount / risk_profile.RP_amount;
      true_risk = InpAllocation * InpRiskAmount;
      
      double scaled_lot = risk_profile.RP_lot * InpAllocation * risk_amount_scale_factor;
      true_lot = scaled_lot;
 
      return scaled_lot;
   }
   
   void trade_params_long(string trade_type){
      // buy at ask, sell at bid
      
      if (trade_type == "market") entry_price = price_ask();
      if (trade_type == "pending") entry_price = last_candle_open();
      
      sl_price = entry_price - ((risk_profile.RP_amount) / (risk_profile.RP_lot * tick_value* (1/trade_points)));
      
   }
   
   void trade_params_short(string trade_type){
      // buy at ask, sell at bid
      
      if (trade_type == "market") entry_price = price_bid();
      if (trade_type == "pending") entry_price = last_candle_open();
      
      
      // THIS IS A BACKUP (Original, Working)
      ///sl_price = entry_price + ((InpRiskAmount) / (InpLot * tick_value * (1 / trade_points)));
      sl_price = entry_price + ((risk_profile.RP_amount) / (risk_profile.RP_lot * tick_value * (1 / trade_points)));
   }

   void get_trade_params(string trade_type){
      // trade type: pending or market
      switch (risk_profile.RP_order_type){
         case 0:
            trade_params_long(trade_type);
            break;
         case 1:
            trade_params_short(trade_type);
            break;
            
         default:
            break;
      }
   }
   

   
   double close_price(){
      double trade_close_price;
      switch (risk_profile.RP_order_type){
         case 0:
            trade_close_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            break;
         case 1: 
            trade_close_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            break;
         default:
            break;
      }
      return trade_close_price;
   }
   
   void set_delayed_entry(double price){
      logger(StringFormat("Last Open: %f", last_candle_open()));
      logger(StringFormat("Set Delayed Entry Reference Price: %f", price));
      delayed_entry_reference = price;
   }
   
   bool delayed_entry_valid(){
      // get order type, 
      // if buy, entry reference > Ask 
      // if sell, entry reference < Bid
      bool valid;
      switch (risk_profile.RP_order_type){
         case 0:
            // long 
            valid = delayed_entry_reference > price_ask() ? true : false;
            break;
         case 1:
            // short 
            valid = delayed_entry_reference < price_bid() ? true : false;
            break;
         default:
            valid = false;
            break;
      }
      if (valid) logger(StringFormat("Delayed Entry Valid: %i, Reference: %f, Entry: %f", valid, delayed_entry_reference, trade_params.entry_price));
      return valid;
   }
   
   
};

struct ActivePosition{
   /*
   Active Position object. Holds information to use for validating if trades exceeded deadlines. 
   */
   datetime pos_open_time;
   datetime pos_close_deadline;
   int pos_ticket;
   
};

struct TradesActive{
   datetime trade_open_datetime;
   datetime trade_close_datetime;
   long trade_ticket;
   
   int candle_counter;
   int orders_today;
   ActivePosition active_positions[];
   
   
   
   TradesActive(){
      candle_counter = 0;
      orders_today = 0;
   }
   
   void set_trade_open_datetime(datetime trade_datetime, long ticket){
      // call this if trade is opened successfully
      trade_open_datetime = trade_datetime;
      trade_ticket = ticket;
      set_trade_close_datetime();
   }
   
   void set_trade_close_datetime(){
      MqlDateTime trade_open_struct;
      MqlDateTime trade_close_struct; 
      
      datetime next = TimeCurrent() + (interval_current() * risk_profile.RP_holdtime);
      TimeToStruct(next, trade_close_struct);
      trade_close_struct.sec = 0;
      
      
      trade_close_datetime = StructToTime(trade_close_struct);
   }
   
   bool check_trade_deadline(datetime trade_open_time){
      // under construction
      datetime deadline = trade_open_time + (interval_current() * risk_profile.RP_holdtime);
      
      if(TimeCurrent() >= deadline) { return true; }
      return false;
   }
   
   void append_active_position(ActivePosition &active_pos){
      
      int arr_size = ArraySize(active_positions);
      ArrayResize(active_positions, arr_size + 1);
      active_positions[arr_size] = active_pos;
      logger(StringFormat("Updated active positions: %i, Ticket: %i", num_active_positions(), active_pos.pos_ticket));
   }
   
   int num_active_positions(){ return ArraySize(active_positions); }
   
   void clear_positions() { ArrayFree(active_positions);}
   
   bool trade_in_pool(int ticket){
      int arr_size = num_active_positions();
      
      for (int i = 0; i < arr_size; i++){
         if (ticket == active_positions[i].pos_ticket) { return true; }
      }
      return false;
   }
   
   void add_order_today(){
      // increment if an order is executed
      orders_today++;
   }
   
   void clear_orders_today(){
      // reset on new day
      orders_today = 0;
   }    

};


struct TradeLog{
   double order_open_price;
   datetime order_open_time;
   datetime order_target_close_time;
   double order_open_spread;
   
   double order_close_price;
   datetime order_close_time;
   double order_close_spread;
   
   long order_open_ticket;
   long order_close_ticket;
   
   void set_order_open_log_info(double open_price, datetime open_time, datetime target_close_time, long ticket){
      order_open_price = open_price;
      order_open_time = open_time;
      target_close_time = order_target_close_time;
      order_open_spread = market_spread();
      order_open_ticket = ticket;
   }
   
   void set_order_close_log_info(double close_price, datetime close_time, long ticket){
      order_close_price = close_price;
      order_close_time = close_time;
      order_close_spread = market_spread();
      order_close_ticket = ticket;
   }
};


struct TradeQueue{
   // scheduler
   
   datetime next_trade_open;
   datetime next_trade_close;
   
   datetime curr_trade_open;
   datetime curr_trade_close;
   
   /*
   run this on init, on loop
   checking schedule: 
   compare time current and input entry window. if tc > input, skip to next day
   */
   
   void set_next_trade_window(){
      MqlDateTime current;
      TimeToStruct(TimeCurrent(), current);
      
      current.hour = InpEntryHour;
      current.min = InpEntryMin;
      current.sec = 0;
      
      datetime entry = StructToTime(current);
      
      curr_trade_open = entry;
      next_trade_open = TimeCurrent() > entry ? entry + interval_day() : entry;
      
      curr_trade_close = window_close_time(curr_trade_open);
      next_trade_close = window_close_time(next_trade_open);
   }
   
   datetime window_close_time(datetime window_open_time){
      window_open_time = window_open_time + (interval_current() * risk_profile.RP_holdtime);
      return window_open_time;
   }
   
   bool IsTradeWindow(){
      if (TimeCurrent() >= curr_trade_open && TimeCurrent() < curr_trade_close) { return true; }
      return false;
   }
   
   bool IsNewDay(){
      if (TimeCurrent() < curr_trade_open){ return true; }
      return false;
   }
   
   
};

TradesActive trades_active;
TradeParameters trade_params;
TradeLog trade_log;
TradeQueue trade_queue;
RiskProfile risk_profile;

int OnInit()
  {
//---
   #ifdef __MQL5__
   Trade.SetExpertMagicNumber(InpMagic);
   #endif 
   risk_profile.set_risk_profile();
   //set_deadline();
   
   orders_ea();
   trade_queue.set_next_trade_window();
   create_comments();
   // add provision to check for open orders, in case ea gets deactivated
   //Print("trade_params.risk_amount: ", trade_params.risk_amount);
//---
   return(INIT_SUCCEEDED);

  }
  
  
  
void OnDeinit(const int reason)
  {
//---
   
  }
  
  
void OnTick()
  {
   if (IsNewCandle() && correct_period()){
      // check here for time interval 
      if (valid_trade_open()){
         // time is in between open and close time 
         if (send_order() == -1) { 
            // add recusrion here? 
            // store last open price, and use it as reference, for delayed entry
            //trade_params.set_delayed_entry(last_candle_open());
            
         }
            //send_limit_order();

      }
      else{
         if (TimeCurrent() >= trade_queue.curr_trade_close) { close_order(); }
       
      }
      // check order here. if order is active, increment
      
      trade_queue.set_next_trade_window();
      check_order_deadline();
      int positions_added = orders_ea();
      if (trade_queue.IsTradeWindow()){
         logger(StringFormat("Checked Order Pool. %i Positions Found.", positions_added));
         logger(StringFormat("%i Orders in Active List", trades_active.num_active_positions()));
      }
      
      if (trade_queue.IsNewDay()) { trades_active.clear_orders_today(); }
      modify_order();
      create_comments();
   }
  }
//+------------------------------------------------------------------+

bool correct_period(){
   if (Period() != risk_profile.RP_timeframe) {
      errors(StringFormat("INVALID TIMEFRAME. USE: %s", EnumToString(risk_profile.RP_timeframe)));
      return false;
   }
   return true;
}

void check_order_deadline(){
   /*
   Iterates through the active_positions list, and checks their deadlines. If deadline has passed, 
   trade is requested to close.
   
   Redundancy in case close_order() fails.
   */
   for (int i = 0; i < trades_active.num_active_positions(); i++){
      ActivePosition pos = trades_active.active_positions[i];
      if (pos.pos_close_deadline > TimeCurrent()){ continue; }
      // else, close this trade
      close_trade(pos.pos_ticket);
   }
}





bool update_csv(string log_type){
   // log type: order open, order close   
   if (!InpLogging) return false;
   logger(StringFormat("Update CSV: %s", log_type));
   string csv_message = "";
   /*
   TODO: open a csv file, and write
   */
   if (log_type == "open"){
      csv_message = TimeCurrent()+",open,"+trade_log.order_open_ticket+","+trade_log.order_open_price+","+trade_log.order_open_time+","+trades_active.trade_close_datetime+","+trade_log.order_open_spread;
   }
   if (log_type == "close"){
      csv_message = TimeCurrent()+",close,"+trade_log.order_close_ticket+","+trade_log.order_close_price+","+trade_log.order_open_time+","+TimeCurrent()+","+trade_log.order_close_spread;
   }
   if (write_to_csv(csv_message, log_type) == -1) {
         logger(StringFormat("Failed To Write to CSV. %i", GetLastError()));
         logger(StringFormat("MESSAGE: %s", csv_message));
         return false;
      };
   return true;
}

bool delayed_valid(){
   /*
   Checks if entry is delayed, and if valid. 
   */
   trade_params.get_trade_params("market");
   if (TimeCurrent() > trade_queue.curr_trade_open && !trade_params.delayed_entry_valid()) return 0;
   return 1;
}

int send_order(){
   // if bad spread, record the entry price (bid / ask), then enter later if still valid
   
   /*
   Potential Solutions / Ideas for handling bad spreads:
   1. Delay, recursive
      -> recursion method given an input delay. Calls the send_order function after the delay while checking the spread. 
      -> Does not check if price is optimal (entered exactly at entry window candle open price)
      -> Optional: Allow checking if price is optimal
   
   2. Interval
      -> If spread is bad, skips to next interval. 
      -> Checks if price is optimal (exactly, or better than candle open price)
      
   3. Ignore
      -> If spread is bad, halts trading for the day. 
   */
   
   
   ENUM_ORDER_TYPE order_type = ord_type();
   if (TimeCurrent() == trade_queue.curr_trade_open) trade_params.set_delayed_entry(delayed_entry_reference()); // sets the reference price to the entry window candle open price
   int delay = InpSpreadDelay * 1000; // Spread delay in seconds * 1000 milliseconds
   
   
   
   
   switch (InpSpreadMgt){
      case 0: // interval 
         if (market_spread() >= risk_profile.RP_spread) return -1;
         if (!delayed_valid()) return -1;
         break;
      case 1: // recursive
         while (market_spread() >= risk_profile.RP_spread || !delayed_valid()){
            Sleep(delay);
            if (TimeCurrent() >= trade_queue.curr_trade_close) return -1;
         }
         break;
         
      case 2: // ignore 
         if (TimeCurrent() > trade_queue.curr_trade_open) return -1;
         if (market_spread() >= risk_profile.RP_spread) return -1;
         break; 
      default: 
         break;
   }
   
   
   
   int ticket = order_open(Symbol(), order_type, trade_params.calc_lot(), trade_params.entry_price, trade_params.sl_price, 0);
   if (ticket == -1) logger(StringFormat("ORDER SEND FAILED. ERROR: %i", GetLastError()));
   trades_active.set_trade_open_datetime(TimeCurrent(), ticket);
   
   ActivePosition ea_pos;
   ea_pos.pos_ticket = ticket;
   ea_pos.pos_open_time = trades_active.trade_open_datetime;
   ea_pos.pos_close_deadline = trades_active.trade_close_datetime;
   trades_active.append_active_position(ea_pos);
   
   trades_active.add_order_today(); // adds an order today
   // trigger an order open log containing order open price, entry time, target close time, and spread at the time of the order
   trade_log.set_order_open_log_info(trade_params.entry_price, TimeCurrent(), trades_active.trade_close_datetime, ticket);
   if (!update_csv("open")) { logger("Failed to Write To CSV. Order: OPEN"); }
   return 1;
}

int send_limit_order(){
   trade_params.get_trade_params("pending");
   
   ENUM_ORDER_TYPE order_type = limit_ord_type();
   double entry_price = iOpen(Symbol(), PERIOD_CURRENT, 0);
   int ticket = order_open(Symbol(), order_type, trade_params.calc_lot(), trade_params.entry_price, trade_params.sl_price, 0);
   if (ticket == -1) logger("Trade Failed");
   trades_active.set_trade_open_datetime(TimeCurrent(), ticket);
   
   ActivePosition ea_pos;
   ea_pos.pos_ticket = ticket;
   ea_pos.pos_open_time = trades_active.trade_open_datetime;
   ea_pos.pos_close_deadline = trades_active.trade_close_datetime;
   trades_active.append_active_position(ea_pos);
   
   // trigger an order open log containing order open price, entry time, target close time, and spread at the time of the order
   trade_log.set_order_open_log_info(trade_params.entry_price, TimeCurrent(), trades_active.trade_close_datetime, ticket);
   if (!update_csv("open")) { logger("Failed to Write To CSV. Order: OPEN"); }
   return 1;
}

int close_order(){
   /*
   Main Close order method.
   */
   //Print("Attempting to close orders.");
   int open_positions = PosTotal();
   order_close_all();
   return 1;
}





int write_to_csv(string data_to_write, string log_type){
   string file = "arb\\"+account_server()+"\\"+Symbol()+"\\arb.csv";
   int handle = FileOpen(file, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON);
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, data_to_write);
   FileClose(handle);
   FileFlush(handle);
   return handle;
}


int orders_ea(){
   /*
   Periodically clears, and repopulates trades_active.active_positions array, with an 
   ActivePosition object, containing trade open time, close deadline, ticket.
   
   The active_positions array is then checked by check_deadline if a trade close has missed a deadline. 
   
   The loop iterates through all open positions in the trade pool, finds a matching symbol and magic number.    
   Gets that trade's open time, and sets a deadline, then appends to a list. 
   
   the active_positions list is then checked for trades that exceeded their deadlines. 
   

   if trades_found, and ea_positions == 0, that means there are no trades in order_pool,
   and no trades were added to the list. If num_active_positions >0, there are trades in the 
   internal pool. Do: clear the pool. 
   */

   int open_positions = PosTotal();
   
   //ArrayFree(trades_active.active_positions);
   int ea_positions = 0; // new trades found in pool that are not in internal trade pool
   int trades_found = 0; // trades found in pool that match magic and symbol
   
   for (int i = 0; i < open_positions; i++){
   
      if (trade_match(i)){
         trades_found++;
         int ticket = PosTicket();
         if (trades_active.trade_in_pool(ticket)) { continue; }
         
         ActivePosition ea_pos; 
         ea_pos.pos_open_time = PosOpenTime();
         ea_pos.pos_ticket = ticket;
         ea_pos.pos_close_deadline = ea_pos.pos_open_time + (interval_current() * risk_profile.RP_holdtime);
         trades_active.append_active_position(ea_pos);
         ea_positions++; 
      }
   }
   
   // checks: trades_found, ea_positions, trades_active. 
   /*
   trades_found > ea_positions: a trade is found, and already exists in the active_positions list
   trades_found == ea_positions: a trade is found, and added in the active_positions list
   trades_found == ea_positions == 0, and num_active_positions > 0: a trade was closed or stopped. if this happens, clear the list, and run again (recursion)
   */
   if (trades_found == 0 && ea_positions == 0 && trades_active.num_active_positions() > 0) { trades_active.clear_positions(); }
   return trades_found;
}


int logger(string message){
   if (!InpTerminalMsg) return -1;
   Print("LOGGER: ", message);
   return 1;
}

void errors(string error_message){
   Print("ERROR: ", error_message);
}

void create_comments(){
   double true_lot = trade_params.calc_lot();
   double true_risk = InpRiskAmount * InpAllocation;
   int ea_positions = ArraySize(trades_active.active_positions);
   Comment(
      "Symbol Tick Value: ", trade_params.tick_value, "\n",
      "Symbol Trade Points: ", trade_params.trade_points, "\n",
      "Risk Profile Lot: ", risk_profile.RP_lot, "\n",
      "Risk Profile Risk: ", risk_profile.RP_amount, "\n",
      "Risk Profile Hold Time: ", risk_profile.RP_holdtime, "\n",
      "Risk Profile Order Type: ", risk_profile.RP_order_type, "\n",
      "Risk Profile Timeframe: ", risk_profile.RP_timeframe, "\n",
      "True Lot: ", true_lot, "\n",
      "True Risk: ", trade_params.true_risk, "\n",
      "Allocation: ", InpAllocation, "\n",
      "EA Positions: ", trades_active.num_active_positions(), "\n",
      "Entry Hour: ", InpEntryHour, "\n",
      "Entry Minute: ", InpEntryMin, "\n",
      "Magic: ", InpMagic, "\n",
      "Last Recorded Time: ", TimeCurrent(), "\n",
      "Current Trade Entry: ", trade_queue.curr_trade_open, "\n",
      "Current Trade Close: ", trade_queue.curr_trade_close, "\n",
      "Next Trade Entry: ", trade_queue.next_trade_open, "\n",
      "Next Trade Close: ", trade_queue.next_trade_close, "\n",
      "Active Position Entry Time: ", trades_active.trade_open_datetime, "\n",
      "Active Position Close Time: ", trades_active.trade_close_datetime, "\n"
   );
}

// WRAPPERS
bool modify_order(){
   switch(InpTradeMgt){
      case 0: 
         // breakeven
         set_breakeven();
         break;
      case 1:
         // trailing stop 
         trail_stop();
         break;
      default: 
         break; 
         
   }
   return 1;
}


bool valid_trade_open(){
   /*
   Boolean function for checking trade validity based on: 
      1. Entry Window -> trade_queue.IsTradeWindow()
      2. Active Positions -> trades_active.num_active_positions()
      3. OrdersEA -> orders_ea() -> redundancy
      4. Orders Today -> trades_active.orders_today 
      
   Returns true if all conditions are satisfied (still in entry window, no active positions, no trades opened yet)
   Otherwise, returns false. 
   */
   if (trade_queue.IsTradeWindow() && trades_active.num_active_positions() == 0 && orders_ea() == 0 && trades_active.orders_today == 0) return true; 
   return false;
}

double delayed_entry_reference(){
   double last_open = iOpen(Symbol(), PERIOD_CURRENT, 0); 
   double reference = 0;
   double spread_factor = risk_profile.RP_spread * trade_params.trade_points;
   
   switch(risk_profile.RP_order_type){
      case 0:
         //long 
         reference = last_open + spread_factor;
         break;
      case 1: 
         // short 
         reference = last_open;
         break;
      default: 
         break;
   }
   return reference;
}

double last_candle_open() { return iOpen(Symbol(), PERIOD_CURRENT, 0); }
double last_candle_close() { return iClose(Symbol(), PERIOD_CURRENT, 0); }

double account_balance() { return AccountInfoDouble(ACCOUNT_BALANCE);}
string account_server() { return AccountInfoString(ACCOUNT_SERVER); }

int interval_current() { return PeriodSeconds(PERIOD_CURRENT); }
int interval_day() { return PeriodSeconds(PERIOD_D1); }

ENUM_ORDER_TYPE ord_type() {
   switch(risk_profile.RP_order_type){
      case 0:
         return ORDER_TYPE_BUY;
         break;
      case 1:
         return ORDER_TYPE_SELL;
         break;
         
      default:
         break;
   }
   return -1;
}

ENUM_ORDER_TYPE limit_ord_type(){
   switch(risk_profile.RP_order_type){
      case 0: 
         return ORDER_TYPE_BUY_LIMIT;
         break;
      case 1:
         return ORDER_TYPE_SELL_LIMIT;
         break;
      default:
         break;         
   }
   return -1;
   
}

int IsPending(ENUM_ORDER_TYPE ord_type){
   switch(ord_type){
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         return 0;
         break;
      
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
         return 1;
         break;
         
      default:
         break;
   }
   return -1;
}


int set_breakeven(){ 
   
   if (InpTradeMgt == Trailing) return 0;
   
   int active = trades_active.num_active_positions();
   for (int i = 0; i < active; i++){
      int ticket = trades_active.active_positions[i].pos_ticket;
      if (PosProfit() < 0) continue; 
      int s = order_select_by_ticket(ticket);
      int c = modify_sl(PosOpenPrice());
   }
   return 1;
}



int trail_stop(){
   int active = trades_active.num_active_positions();
   
   for (int i = 0; i < active; i++){
      int ticket = trades_active.active_positions[i].pos_ticket;
      int s = order_select_by_ticket(ticket); // IMPORTANT
      
      double trade_open_price = PosOpenPrice();      
      double last_open_price = last_candle_open();
      
      double diff = MathAbs(trade_open_price - last_open_price) / trade_params.trade_points;
      
      if (diff < InpTrailInterval) continue; 
      
      ENUM_ORDER_TYPE position_order_type = PosOrderType();
      
      double updated_sl = PosSL();
      double current_sl = updated_sl;
      
      int c = 0;
      double trail_factor = InpTrailInterval * trade_params.trade_points;
      switch(position_order_type){
         case 0:
            updated_sl = last_open_price - trail_factor;
            if (updated_sl < current_sl) continue;
            break;
         case 1:
            updated_sl = last_open_price + trail_factor;
            if (updated_sl > current_sl) continue;
            break;
         default:
            continue;
      }
      c = modify_sl(updated_sl);
      if (c) logger("Trail Stop Updated");
      
   }
   return 1;
}

#ifdef __MQL4__
double price_mean() {
   double mean = (price_ask() + price_bid()) / 2;
   return mean;
}

double tick_val() { return MarketInfo(Symbol(), MODE_TICKVALUE);}
double trade_pts() { return MarketInfo(Symbol(), MODE_POINT);}

double price_ask() { return Ask; }
double price_bid() { return Bid; }

double market_spread() { return MarketInfo(Symbol(), MODE_SPREAD); }

int PosTotal() { return OrdersTotal(); }
int PosTicket() { return OrderTicket(); }
double PosLots() { return OrderLots(); }
string PosSymbol() { return OrderSymbol(); }
int PosMagic() { return OrderMagicNumber(); }
int PosOpenTime() { return OrderOpenTime(); }
double PosOpenPrice() { return OrderOpenPrice(); }
double PosProfit() { return OrderProfit(); }
ENUM_ORDER_TYPE PosOrderType() { return OrderType(); }
double PosSL(){ return OrderStopLoss(); }
double PosTP(){ return OrderTakeProfit(); }

int order_close_all(){
   int open_positions = ArraySize(trades_active.active_positions);
   
   for (int i = 0; i < open_positions; i++){
      int ticket = trades_active.active_positions[i].pos_ticket;
      close_trade(ticket);
   }
   ArrayFree(trades_active.active_positions);
   return 1;
}


int close_trade(int ticket){
   int t = OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);
   
   ENUM_ORDER_TYPE ord_type = OrderType();
   int pending = IsPending(ord_type);
   int c = 0;
   switch(pending){
      case 0: 
         // market order
         c = OrderClose(OrderTicket(), PosLots(), trade_params.close_price(), 3, clrNONE);
         if (!c) { logger(StringFormat("ORDER CLOSE FAILED. TICKET: %i, ERROR: %i", ticket, GetLastError()));}
         break;
      case 1:
         //pending order - delete
         c = OrderDelete(OrderTicket(), clrNONE);
         if (!c) { logger(StringFormat("ORDER DELETE FAILED. TICKET; %i, ERROR: %i", ticket, GetLastError()));}
         break;
         
      case -1:
         return -1;
         break;
      default:
         break;     
   }
   trade_log.set_order_close_log_info(trade_params.close_price(), TimeCurrent(), PosTicket());
   
   if (!update_csv("close")) { logger("Failed to write to CSV. Order: CLOSE"); }
   if (c) { logger(StringFormat("Closed: %i", PosTicket())); }
   return 1;
}

int order_open(string symbol, ENUM_ORDER_TYPE order_type, double volume, double price, double sl, double tp){
   logger(StringFormat("Symbol: %s, Ord Type: %s, Vol: %f, Price: %f, SL: %f, TP: %f", symbol, EnumToString(order_type), volume, price, sl, tp));
   int ticket = OrderSend(Symbol(), order_type, trade_params.calc_lot(), trade_params.entry_price, 3, trade_params.sl_price, 0, (string)InpMagic, InpMagic, 0, clrNONE);
   return ticket;
}



bool trade_match(int index){
   int t = OrderSelect(index, SELECT_BY_POS, MODE_TRADES);
   if (PosMagic() != InpMagic) return false;
   if (PosSymbol() != Symbol()) return false;
   return true;
}


int order_select_by_ticket(int ticket){
   int s = OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);
   return s;
}

int modify_sl(double sl){
   // SELECT THE TICKET PLEASE
   int m = OrderModify(PosTicket(), PosOpenPrice(), sl, 0, 0, clrNONE);
   return m;
}

#endif 



#ifdef __MQL5__

double spread_new(){
   double diff = price_ask() - price_bid();
   double spread = diff / trade_pts();
   return spread;
}

double tick_val() { return SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);}
double trade_pts() { return SymbolInfoDouble(Symbol(), SYMBOL_POINT);}

double price_ask() { return SymbolInfoDouble(Symbol(), SYMBOL_ASK); }
double price_bid() { return SymbolInfoDouble(Symbol(), SYMBOL_BID); }

double market_spread() { return SymbolInfoInteger(Symbol(), SYMBOL_SPREAD); }

int PosTotal() { return PositionsTotal(); }
int PosTicket() { return PositionTicket(); }
double PosLots() { return PositionGetDouble(POSITION_VOLUME); }
string PosSymbol() { return PositionGetString(POSITION_SYMBOL); }
int PosMagic() { return PositionGetInteger(POSITION_MAGIC); }
int PosOpenTime() { return PositionGetInteger(POSITION_TIME); }
double PosOpenPrice() { return PositionGetDouble(POSITION_PRICE_OPEN); }
double PosProfit() { return PositionGetDouble(POSITION_PROFIT); }
ENUM_ORDER_TYPE PosOrderType() { return PositionGetInteger(POSITION_TYPE); }
double PosSL() { return PositionGetDouble(POSITION_SL); }
double PosTP() { return PositionGetDouble(POSITION_TP); }


int order_close_all(){
   int tickets[];
   
   int open_positions = PosTotal();
   for (int i = 0; i < open_positions; i ++){
      int ticket = PositionGetTicket(i);
      int t = PositionSelectByTicket(ticket);
      
      if (PosMagic() != InpMagic){ continue; }
      if (PosSymbol() != Symbol()) { continue; }
      
      //if (!trades_active.check_trade_deadline(PositionTimeOpen())) { continue; }
      
      //int c = Trade.PositionClose(t);
      // create a list, and append
      int arr_size = ArraySize(tickets);
      ArrayResize(tickets, arr_size+1);
      tickets[arr_size] = ticket;
   }
   int total_trades = ArraySize(tickets);
   //Print(total_trades, " Trades added.");
   
   
   // close added trades
   int trades_closed = 0;
   for (int i = 0; i < ArraySize(tickets); i++){
      Print("TICKETS: ", tickets[i]);
      int c = close_trade(tickets[i]);
      if (c == -2) {
         logger("Cannot close trade. Trail Stop is set.");
         break;
      }
      if (c) { 
         trades_closed += 1;
         trade_log.set_order_close_log_info(trade_params.close_price(), TimeCurrent(), PosTicket());
         if (!update_csv("close")) {Print("Failed to write to CSV. Order: CLOSE"); }
         if (c){ Print("Closed: ",PosTicket()); }
         
     }
   }
   return trades_closed;
}


int close_trade(int ticket){
   int t = PositionSelectByTicket(ticket);
   
   
   ENUM_ORDER_TYPE ord_type = OrderGetInteger(ORDER_TYPE);
   int pending = IsPending(ord_type);
   int c = 0;
   switch(pending){
      case 0: 
         // market order
         if (PositionGetDouble(POSITION_PROFIT) > 0 && InpTradeMgt == Trailing) return -2; // ignores open positions in profit when using trail stop 
         c = Trade.PositionClose(ticket); // closes positions in loss when using trail stop 
         if (!c) { logger(StringFormat("ORDER CLOSE FAILED. TICKET: %i, ERROR: %i", ticket, GetLastError()));}
         break;
      case 1:
         //pending order - delete
         c = Trade.OrderDelete(ticket);
         if (!c) { logger(StringFormat("ORDER DELETE FAILED. TICKET; %i, ERROR: %i", ticket, GetLastError()));}
         break;
         
      case -1:
         // invalid order type
         return -1;
         break;
      default:
         break;     
   }
   trade_log.set_order_close_log_info(trade_params.close_price(), TimeCurrent(), PosTicket());
   
   if (!update_csv("close")) { logger("Failed to write to CSV. Order: CLOSE"); }
   if (c) { logger(StringFormat("Closed: %i", PosTicket())); }
   return c;
}



int order_open(string symbol, ENUM_ORDER_TYPE order_type, double volume, double price, double sl, double tp){
   
   bool t = Trade.PositionOpen(symbol, order_type, volume, price, sl, tp, NULL);
   logger(StringFormat("Symbol: %s, Ord Type: %s, Vol: %f, Price: %f, SL: %f, TP: %f, Spread: %f", symbol, EnumToString(order_type), volume, price, sl, tp, market_spread()));
   if (!t) { Print(GetLastError()); }
   int order_ticket = select_ticket();
   return order_ticket;
}


int select_ticket(){
   int open_positions = PosTotal();
   for (int i = 0; i < open_positions; i ++){
      int ticket = PositionGetTicket(i);
      int t = PositionSelectByTicket(ticket);
      
      if (PosMagic() != InpMagic) continue; 
      if (PosSymbol() != Symbol()) continue; 
      
      return ticket;
   }
   return 0;
}


bool trade_match(int index){
   int ticket = PositionGetTicket(index);
   int t = PositionSelectByTicket(ticket);
   if (PosMagic() != InpMagic) return false;
   if (PosSymbol() != Symbol()) return false;
   return true;
}

int order_select_by_ticket(int ticket){
   int s = PositionSelectByTicket(ticket);
   return s;
}

int modify_sl(double sl){
   // SELECT THE TICKET PLEASE
   int m = Trade.PositionModify(PosTicket(), sl, PosTP());
   return m;
}
#endif 
