import pybit
import pandas as pd 
from datetime import datetime as dt 
from pybit.unified_trading import HTTP



class ByBitTrader:

    def __init__(self):
        self.session = HTTP(testnet=False)
        self.available_symbols = self.get_all_symbols()
        #self.available_symbols = ['BTCUSD','ETHUSD','XRPUSD'] # temporary

    def get_historical_data(self, symbol:str, interval:str, start_date:dt, end_date:dt) -> pd.DataFrame:
  
        
        # timestamps have to be in ms 
        start_date_ts = int(start_date.timestamp()*1000)
        end_date_ts = int(end_date.timestamp()*1000)

        if start_date > end_date:
            raise ValueError("Error. Start date cannot be greater than end date.")

        result = self.session.get_kline(category="inverse", symbol=symbol, interval=interval, start=start_date_ts, end = end_date_ts, limit=1000)
        json_result = result['result']['list']

        df = self.parse_json_result(json_result)

        # recursion base case 
        if len(df) <= 1: 
            return df 
        
        first_date = df[:1].index.item()
        
        if start_date < first_date: 
            prev = self.get_historical_data(symbol, interval, start_date, first_date)
            return pd.concat([prev, df]).drop_duplicates(keep='first')
            
        return df.drop_duplicates(keep='first')

    @staticmethod 
    def parse_json_result(result) -> pd.DataFrame:
        df = pd.DataFrame(result)
        df.columns=['Date','Open','High','Low','Close','Volume','Turnover']
        df = df.set_index('Date', drop=True)
        df.index = pd.to_datetime(df.index.astype('int64'), unit='ms')
        df = df[::-1]
        df = df.astype('float')
        return df 
    
    def get_server_time(self) -> dt:
        result = self.session.get_server_time()
        ts = int(result['result']['timeSecond'])
        return dt.fromtimestamp(ts)
    
        
    def get_ticker(self, symbol:str) -> pd.DataFrame:
        result = self.session.get_tickers(category="inverse", symbol=symbol)
        df = pd.DataFrame(result['result']['list']).T
        df.columns=['Description']
        
        return df 

    def get_all_symbols(self) -> list: 
        result = self.session.get_tickers(category='inverse')
        df = pd.DataFrame(result['result']['list'])#.T 
        #df.columns=['Symbols']
        return df['symbol'].tolist()