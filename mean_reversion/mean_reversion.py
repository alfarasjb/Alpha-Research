

import pandas as pd 
import numpy as np 

import statsmodels.tsa.stattools as ts 
import hurst
from sklearn import linear_model

class Mean_Reversion:

    def __init__(self, dataset):
        self.dataset = dataset 
        self.test_statistic, self.p_value, self.num_samples, self.crit_values, self.confidence = self.get_adf()
        self.hurst = self.get_hurst()
        self.half_life = self.get_half_life()

    
    def get_adf(self):
        test_stat, p_val, _, n, crit_val, _ = ts.adfuller(self.dataset)

        confidence = None
        
        for i,j in enumerate(crit_val.values()):
            
            if test_stat < j:
                confidence = [int(k.replace('%','')) for k in crit_val.keys()][i]
                break 
            
        return test_stat, p_val, n, crit_val, confidence

    def get_hurst(self):
        H,c,data = hurst.compute_Hc(self.dataset, kind = 'price', simplified = True)
        return H

    def get_half_life(self):
        df_close = self.dataset.to_frame()
        df_close_1 = df_close.shift(1).dropna()
        delta = (df_close - df_close_1).dropna()

        model = linear_model.LinearRegression()

        delta = delta.values.reshape(len(delta), 1)
        df_close_1 = df_close_1.values.reshape(len(df_close_1), 1)

        model.fit(df_close_1, delta)

        coef = model.coef_.item()

        half_life = -np.log(2) / coef 
        return half_life
    
    def summary(self):
        
        items = {
            'test_statistic' : self.test_statistic,
            'confidence': self.confidence,
            'p_value' : self.p_value,
            'hurst' : self.hurst, 
            'half_life' : self.half_life
        }

        df = pd.DataFrame.from_dict(items, orient = 'index')
        df.columns = ['Value']
        return df
