import pandas as pd 
import numpy as np 
from .bybit_trader import ByBitTrader
from datetime import datetime as dt 
import matplotlib.pyplot as plt 
import mplfinance as mpf
from .plots import Plots 

class SpreadMomentum: 

    def __init__(self, symbol:str, resolution:any, spread_period:int=10, z_threshold:int=1):
        # Initialize symbol to generate signals 
        self.symbol = symbol 
        self.resolution = resolution 
        self.spread_period = spread_period
        self.z_threshold = z_threshold

        # Create instance of ByBitTrader to fetch historical data 
        self.bbt = ByBitTrader()
        self.dataset = self.bbt.get_historical_data(symbol, resolution, start_date=dt(2014, 1,1), end_date=dt.now())

        
        # Exclude date today 
        last_date = self.dataset[-1:].index.item().date()
        if last_date == dt.now().date():
            self.dataset = self.dataset[:len(self.dataset)-1]

        # Generates a dataframe containing signals 
        self.built = self.build_signal(self.dataset.copy())


        # Create instance of Plots class 
        self.plots = Plots(self.built, self.symbol)

    def build_signal(self, data:pd.DataFrame) -> pd.DataFrame:

        if not isinstance(data, pd.DataFrame):
            raise ValueError("Failed to generate signal. Invalid data type.") 
        
        # Asset Log Returns 
        data['log_returns'] = np.log(data['Close']/data['Close'].shift(1))

        # Building Z-Score Indicator
        data['mean'] = data['Close'].ewm(span=self.spread_period).mean()
        data['spread'] = data['Close'] - data['mean']
        data['spread_mean'] = data['spread'].ewm(span=self.spread_period).mean()
        data['spread_sdev'] = data['spread'].ewm(span=self.spread_period).std()
        data['z_score'] = (data['spread'] - data['spread_mean']) / data['spread_sdev']

        # Method for attaching signal based on entry and exit conditions 
        def attach(df, column_name, entry_mask, exit_mask, entry_signal, exit_signal): 
            sig = df.copy()
            sig[column_name] = np.nan
            sig.loc[entry_mask, column_name] = entry_signal 
            sig.loc[exit_mask, column_name] = exit_signal 
            sig[column_name] = sig[column_name].ffill()
            sig[column_name] = sig[column_name].fillna(0)

            return sig 
        
        data['z_upper'] = self.z_threshold 
        data['z_lower'] = -self.z_threshold 

        # entry conditions 
        short_entry = (data['z_score'] <= data['z_lower'])
        short_exit = (data['z_score'] >= 0)

        long_entry = (data['z_score'] >= data['z_upper'])
        long_exit = (data['z_score'] <= 0) 

        # Attaches signals based on entry and exit conditions 
        data = attach(df=data, column_name='long_pos', entry_mask=long_entry, exit_mask=long_exit, entry_signal=1, exit_signal=0)
        data = attach(df=data, column_name='short_pos', entry_mask=short_entry, exit_mask=short_exit, entry_signal=-1, exit_signal=0) 

        # Calculated signal to be traded for the next day. (To prevent look ahead bias)
        data['next_day_position'] = data['long_pos'] + data['short_pos'] 
        
        # Signal used for backtesting 
        data['signal'] = data['next_day_position'].shift(1)

        return data 
    
    def get_signal_today(self):
        last_entry = self.built[-1:]['next_day_position'].item()
        position = "Long" if last_entry == 1 else "Short" if last_entry == -1 else "None"
        print(f"{self.symbol} Position for {dt.now().date()}: {position}")

