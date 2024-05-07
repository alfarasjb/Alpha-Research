import matplotlib.pyplot as plt 
import mplfinance as mpf 
import pandas as pd 


class Plots:

    def __init__(self, data, symbol:str):
        self.data = data 
        self.symbol=symbol

        
        self.returns = self.generate_returns_df(self.data)

    def plot_z_score(self):
        try:
            data = self.data.copy()
        except AttributeError as a:
            print("Something went wrong. Data does not exist yet.")
            return None 

        data['z_score'].plot(figsize=(12, 4))
        plt.axhline(data['z_upper'].mean(), color='firebrick', ls='--')
        plt.axhline(data['z_lower'].mean(), color='springgreen', ls='--')
        plt.ylabel('Rolling Z-Score')
        plt.title('Normalized Spread with Long/Short Levels')
        plt.show()

    def plot_ohlc(self):
        mpf.plot(self.data.tail(100), figsize=(12, 6), title=f"{self.symbol} Price - Last 100 Candles", type='candle')
        plt.show()

    def plot_backtest(self): 
        data = self.data.copy()
        
        # signal is already shifted
        strategy = data['log_returns'] * data['signal'] 

        strategy.cumsum().plot(figsize=(12, 6))
        plt.ylabel('Log Returns')
        plt.title('Strategy Returns')
        plt.show()

    def plot_buy_and_hold_comparison(self):
        self.returns.cumsum().plot(figsize=(12, 6))
        plt.ylabel('Log Returns')
        plt.title('Benchmark vs Strategy Returns')
        plt.show()

    def plot_annual_returns_comparison(self):
        ann_returns = self.returns.groupby(self.returns.index.year).sum() 
        
        strategy_annual = ann_returns['Strategy'].mean() * 100 
        benchmark_annual = ann_returns['Benchmark'].mean() * 100 
        print()
        print(f"Strategy Average Annual Returns: {strategy_annual:.2f}%")
        print(f"Benchmark Average Annual Returns: {benchmark_annual:.2f}%")

        ann_returns.plot(kind='bar', figsize=(12, 6))
        plt.ylabel('Returns')
        plt.title('Annual Returns Comparison: Benchmark vs Strategy')
        plt.show()


    @staticmethod 
    def generate_returns_df(data):
        returns = pd.DataFrame(columns=['Benchmark','Strategy'])
        returns['Benchmark'] = data['log_returns']
        # signal is already shifted
        returns['Strategy'] = data['log_returns'] * data['signal']
        return returns 