import pandas as pd 
import numpy as np 
import matplotlib.pyplot as plt
import seaborn as sns 
from datetime import datetime as dt 

import os
key = os.environ.get('quandl_api_key')

import quandl
quandl.ApiConfig.api_key = key

from alpha_vantage.timeseries import TimeSeries
ts = TimeSeries(key = 'alpha_vantage_api_key', output_format = 'pandas')

import warnings
warnings.filterwarnings('ignore')

plt.style.use('seaborn-darkgrid')


class Seasonality:
    
    
    """
    A module for assessing seasonal changes and trends. 
    
    Allows backtesting, and studying strategy returns
    
    
    Methods
    -------
    get_fred_from_quandl: Fetches FRED data using the Quandl API
    
    get_data_from_alpha_vantage: Fetches stock data using the AlphaVantage API
    
    clean_data: Static method for cleaning raw FRED data, and adding necessary columns.
    
    backtest: Backtests returns using the daily timeframe
    
    plot_data_by_month: Measures periodic average change by month
    
    plot_close: Plots close price
    
    plot_distribution: Plots probability distribution of dataset
    
    plot_backtest: Plots a comparison of returns for different strategies
    
    plot_returns_by_month: Plots returns by month
    
    plot_annual_returns: Plots annual returns
    
    update_monthly_data: Updates monthly data with user-specified dataframe
    
    update_daily_data: Updates daily data with user-specified dataframe
    
    backtest_data_is_empty: Checks if backest_data is empty
    """
    
    
    def __init__(self, start_date: str = None, end_date: str = None):
        
        """
        Parameters
        ----------
        start_date: str
            Start Date for dataset
            
        end_date: str
            End Date for dataset
        """
        self.backtest_data = None
        self.monthly_data = None
        self.daily_data = None
        self.strats_list = []
        
        self.start_date = start_date
        self.end_date = end_date
    
        timeframes = ['daily', 'monthly']
        calculations = ['mean', 'sum', 'std']
        days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
        months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


            
    def get_fred_from_quandl(self, fred_code: str):
        
        """
        Fetches FRED data using the Quandl API. 
        
        Parameters
        ----------
        fred_code: str
            Code for target data. Codes are available on the FRED website.
            
        Returns
        -------
        monthly_data: pd.DataFrame
            A dataframe on monthly data for the target set. 
            
        daily_data: pd.DataFrame
            A dataframe on daily data for the target set. 
        """
        assert type(fred_code) == str, 'Invalid Data Type for fred_code'
        # MONTHLY 
        fred = f'FRED/{fred_code}'
        self.monthly_data = self.clean_data(quandl.get(fred, collapse = 'monthly'), 'monthly', self.start_date, self.end_date)
        self.daily_data = self.clean_data(quandl.get(fred), 'daily', self.start_date, self.end_date)
        
        return self.monthly_data, self.daily_data
    
    def get_data_from_alpha_vantage(self, ticker_id: str):
        """
        Fetches Stock data using the Alpha Vantage API.
        
        Parameters
        ----------
        ticker_id: str
            Ticker ID for target stock
            
        Returns
        -------
        monthly_data: pd.DataFrame
            A dataframe on monthly data for the target set. 
            
        daily_data: pd.DataFrame
            A dataframe on daily data for the target set. 
        """
        
        assert type(ticker_id) == str, 'Invalid Data Type for ticker_id'
        av_daily, meta_data = ts.get_daily(ticker_id, 'full')
        av_monthly, meta_data = ts.get_monthly(ticker_id)
        
        d = av_daily[['4. close']][::-1]
        d = d.reset_index()
        d.columns = ['Date', 'Close']
        d = d.set_index('Date', drop = True)

        mon = av_monthly[['4. close']][::-1]
        mon = mon.reset_index()
        mon.columns = ['Date', 'Close']
        mon = mon.set_index('Date', drop = True)
        
        self.monthly_data = self.clean_data(mon, 'monthly', self.start_date, self.end_date)
        self.daily_data = self.clean_data(d, 'daily', self.start_date, self.end_date)
        
        return self.monthly_data, self.daily_data
        
        
    @staticmethod
    def clean_data(data: pd.DataFrame, timeframe: str, start_date: str = None, end_date: str = None):
        
        """
        Static method for cleaning raw FRED data, and adding necessary columns.
        
        Parameters
        ----------
        data: pd.DataFrame
            Raw FRED data to process
            
        timeframe: str
            Timeframe of received data (daily, monthly)
            
        start_date: str
            Start Date of dataset
            
        end_date: str
            End Date of dataset
        
        Returns
        --------
        data: pd.DataFrame
            Cleaned data
        """
        assert type(data) == pd.DataFrame, 'Invalid Data Type for raw data'
        assert type(timeframe) == str, 'Invalid Data Type for timeframe'
        
        data.columns = ['Close']
        
        data['pct_change'] = data['Close'].pct_change() * 100
        data = data.dropna()
        data = data.reset_index()
        
        
        data['month'] = data['Date'].dt.month
        data['month'] = data['month'].map({i+1:m for i, m in enumerate(months)})
        data['year'] = data['Date'].dt.year
        if timeframe == 'daily':
            # month and day of week
            
            data['day_of_week'] = data['Date'].dt.dayofweek
            data['day_of_week'] = data['day_of_week'].map({i:d for i, d in enumerate(days)})
            
        data = data.set_index('Date', drop = True)
        
        date_format = '%Y-%m-%d'
        start = data.index[0].date().strftime(date_format) if start_date is None else start_date
        end = data.index[-1].date().strftime(date_format) if end_date is None else end_date

        start_obj = dt.strptime(start, date_format)
        end_obj = dt.strptime(end, date_format)

        data = data.loc[(data.index < end_obj) & (data.index >= start_obj)]
        
        return data
    
    
    def backtest(self, maxdd: float = 1):
        
        """
        Backtests returns using the daily dataframe
        
        Parameters
        ----------
        maxdd: float
            Max Drawdown Percent 
            Default: 1%
            
        Returns
        -------
        backtest_data: pd.DataFrame
            backtest dataframe containing signals and returns used for plotting and comparison
        """
        
        backtest_data = self.daily_data.copy()
        
        # daily change by month
        grouped = backtest_data.groupby('month')[['pct_change']].mean().reindex(months)

        grouped['sig'] = np.where(grouped['pct_change'] > 0, 1, -1)
        
        # intraweek change
        week = backtest_data.groupby('day_of_week')[['pct_change']].mean().reindex(days)
        week['sig'] = np.where(week['pct_change'] > 0, 1, -1)
        
        backtest_data['signal'] = backtest_data['month'].map({m:s for m, s in zip(grouped.index, grouped['sig'])})
        backtest_data['daily_sig'] = backtest_data['day_of_week'].map({k:l for k,l in zip(week.index, week['sig'])})
        backtest_data['signal_actual'] = np.where(backtest_data['pct_change'] > 0, 1, -1)
        
        backtest_data['strategy_returns'] = backtest_data['pct_change'] * backtest_data['signal'].shift(periods = 1)
        backtest_data['actual_returns'] = backtest_data['pct_change'] * backtest_data['signal_actual'].shift(periods = 1)
        backtest_data['d_sig_returns'] = backtest_data['pct_change'] * backtest_data['daily_sig'].shift(periods = 1)
        
        backtest_data['filtered_returns'] = backtest_data['strategy_returns']
        backtest_data['filtered_returns'][backtest_data['strategy_returns'] < -maxdd] = -maxdd
        backtest_data['d_sig_returns'][backtest_data['d_sig_returns'] < -maxdd] = -maxdd
        
        backtest_data = backtest_data.dropna()
    
        self.backtest_data = backtest_data.copy()
        self.strats_list = ['d_sig_returns', 'filtered_returns', 'strategy_returns', 'actual_returns','pct_change']
        
        return backtest_data
    
    
    
    def plot_data_by_month(self, timeframe: str, calculation: str):
        
        """
        Measures monthly average change based on period. 
        
        Parameters:
        -----------
        timeframe: str
            timeframe to measure
            
            month: calculates monthly average percent change
            daily: calculates daily average percent change
            
        calculation: str
            calculation type (mean, std)

        """
        assert type(timeframe) == str, 'Invalid data type for timeframe'
        assert type(calculation) == str, 'Invalid Calculation Data Type'
        
        if calculation not in calculations:
            raise ValueError('Calculation not in calculations list. Allowed Calculations: "mean", "std"')
        
        if timeframe not in timeframes:
            raise ValueError('Invalid Timeframe')
       
        
        
        cols = ['pct_change', 'month']
        if timeframe == 'daily':
            data_to_plot = self.daily_data[cols]
            
        elif timeframe == 'monthly':
            data_to_plot = self.monthly_data[cols]
            
        else: 
            raise ValueError('Invalid Group')
        
        if calculation == 'mean':
            title = f'Average {timeframe.capitalize()} Change by Month'
            grouped = data_to_plot.groupby('month').mean().reindex(months)
            
        elif calculation == 'std':
            title = f'{timeframe.capitalize()} Volatility by Month'
            grouped = data_to_plot.groupby('month').std().reindex(months)
            
        else:
            raise ValueError('Invalid Calculation Type')
        
        grouped.plot(kind = 'bar', grid = True, title = title)
        plt.ylabel('Percent Change')
        plt.xlabel('Period')
        plt.legend(labels = ['Percent Change'])
        
    
        
    def plot_close(self, timeframe: str):
        
        """
        Plots close price of the dataset specified by timeframe (daily, monthly)
        
        Parameters:
        -----------
        timeframe: str
            timeframe to plot (daily, monthly)
        """
        assert type(timeframe) == str, 'Invalid Timeframe Data Type'
        
        if timeframe not in timeframes:
            raise ValueError('Invalid Timeframe')
        
        if timeframe == 'daily':
            data_to_plot = self.daily_data['Close']
            
        elif timeframe == 'monthly':
            data_to_plot = self.monthly_data['Close']
        
        else:
            raise ValueError('Invalid Timeframe')
            
        data_to_plot.plot()            
        plt.title(f'WTI Crude Oil {timeframe.capitalize()} Close Price')
        plt.ylabel('Price')
        plt.legend(labels = ['Close'])
        
        
    def plot_distribution(self, timeframe: str):
        
        """
        Plots probability distribution 
        
        Parameters
        ----------
        timeframe: str
            timeframe to plot (daily, monthly)
        """
        
        assert type(timeframe) == str, 'Invalid Timeframe Data Type'
        
        if timeframe not in timeframes:
            raise ValueError('Invalid Timeframe')
            
            
        cols = ['pct_change', 'month']
        if timeframe == 'daily':
            data_to_plot = self.daily_data[cols]
        elif timeframe == 'monthly':
            data_to_plot = self.montly_data[cols]
        else:
            raise ValueError('Invalid Timeframe')
            
        fig, ax = plt.subplots(3, 4, sharey = True, sharex = False, figsize = (15, 12))
        
        month_map = {j+1:m for j, m in enumerate(months)}
        
        for i, a in zip(months, ax.flat):
            data = data_to_plot.loc[data_to_plot['month'] == i]['pct_change']
            mean = data.mean()
            
            sns.distplot(data, ax = a, bins = 20)
            a.set_xlim(-10, 10)
            a.set(xlabel = i)
            a.axvline(mean, ls = '--')
            
            
    def plot_backtest(self, data: pd.DataFrame, strat: str):
        
        """
        Plots a comparison of returns for different strategies
        
        Parameters
        ----------
        data: pd.DataFrame
            Main data to process
            
        strat: str
            Strategy Type in strats_list
        """
        assert type(data) == pd.DataFrame, 'Invalid Data Type'
        assert type(strat) == str, 'Invalid Strat Data Type'
        
        if strat not in self.strats_list:
            raise ValueError('Strat not in strats list')
            
            
        data[self.strats_list].cumsum().plot(figsize = (8, 6))
        plt.title('Comparison of Returns')
        plt.ylabel('Gain (%)')
        plt.legend(labels = ['Daily Signal Returns', 'Loss Minimized Returns', 'Non-Adjusted Returns', 'Raw Returns','Market Returns'])
        
        
    def plot_returns_by_month(self, strat: str, calculation: str):
        
        """
        Plots Returns by month
        
        Parameters
        ----------
        strat: str
            Strategy Type in strats_list
            
            
        calculation: str
            Calculation Type
            mean, sum, std
        """
        assert type(strat) == str, 'Invalid Strat Data Type'
        assert type(calculation) == str, 'Invalid Calculation Data Type'
        
        if self.backtest_data_is_empty():
            raise ValueError('Nothing to test. Run backtest() method first.')
        
        if calculation not in calculations:
            raise ValueError('Calculation not in calculations list. Allowed Calculations: "mean", "sum", "std"')
        
        grouped = self.backtest_data.groupby('month')
        returns_average = grouped.mean()[[strat]].reindex(months)
        returns_total = grouped.sum()[[strat]].reindex(months)
        returns_volatility = grouped.std()[[strat]].reindex(months)
        
        # calculation: mean, sum, std
        if calculation == 'mean':
            title = 'Average Daily Returns by Month'
            ylabel = 'Percent Gain'
            label = 'Average Daily Returns (%)'
            data_to_plot = returns_average
        
        elif calculation == 'sum':
            title = 'Total Daily Returns by Month'
            grouped = grouped.sum()[[strat]].reindex(months)
            ylabel = 'Percent Gain'
            label = 'Total Daily Returns (%)'
            data_to_plot = returns_total
            
        elif calculation == 'std':
            title = 'Returns Volatility by Month'
            grouped = grouped.std()[[strat]].reindex(months)
            ylabel = 'Volatility'
            label = 'Volatility (%)'
            data_to_plot = returns_volatility
            
        else:
            raise ValueError('Invalid Calculation Type')
        
        data_to_plot.plot(kind = 'bar', grid = True, title = title)
        plt.ylabel(ylabel)
        plt.xlabel('Month')
        plt.legend(labels = [label])
        
        
    def plot_annual_returns(self, strat: str):
        
        """
        Plots annual returns for selected strategy
        
        Parameters
        ----------
        strat: str
            Strategy Type in strats_list
        """
        assert type(strat) == str, 'Invalid Strat Type'
        
        if self.backtest_data_is_empty():
            raise ValueError('Nothing to test. Run backtest() method first.')
        
        if strat not in self.strats_list:
            raise ValueError('Strat not in strats list')
        
        years = list(self.backtest_data['year'].unique())
        returns_annual = self.backtest_data.groupby('year')[[strat]].sum().reindex(years)
        returns_annual.plot(kind = 'bar', grid = True, figsize = (12, 6), title = 'Annual Returns')
        plt.xlabel('Year')
        plt.ylabel('Gain (%)')
        plt.legend(labels = ['Annual Returns (%)'])
        
        
    def update_monthly_data(self, data: pd.DataFrame):
        """
        Overwrites stored monthly data with user-specified dataframe. 
        
        Dataframe must contain a datetime index and Close column.
        
        Parameters
        ----------
        data: pd.DataFrame
            Dataset to test
            
        Returns
        -------
        monthly_data: pd.DataFrame
            updated dataframe
        """
        assert type(data) == pd.DataFrame, 'Invalid Data Type'
        assert type(data.index) == pd.DatetimeIndex, 'Invalid Index Type'
        
        if 'Close' not in data.columns:
            raise ValueError('Close not found in columns')
        
        self.monthly_data = self.clean_data(data, 'monthly', self.start_date, self.end_date)
        
        return self.monthly_data
    
    def update_daily_data(self, data: pd.DataFrame):
        """
        Overwrites stored daily data with user-specified dataframe.
        
        Dataframe must contain a datetime index and Close column.
        
        Parameters
        ----------
        data: pd.DataFrame
            Dataset to test
            
        Returns
        -------
        daily_data: pd.DataFrame
            updated dataframe
        """
        assert type(data) == pd.DataFrame, 'Invalid Data Type'
        assert type(data.index) == pd.DatetimeIndex, 'Invalid Index Type'
        
        if 'Close' not in data.columns:
            raise ValueError('Close not found in columns')
            
        self.daily_data = self.clean_data(data, 'daily', self.start_date, self.end_date)
        
        return self.daily_data
        
    def backtest_data_is_empty(self):
        """
        Checks if backtest_data is empty.
        """
        if self.backtest_data is None:
            return True
        else:
            return False
        