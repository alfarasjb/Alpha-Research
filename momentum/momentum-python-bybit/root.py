import spread_momentum as sm 

class Generic: 

    def __init__(self):
        pass 

    @staticmethod 
    def is_blank(value:str) -> bool: 
        if len(value.strip()) == 0:
            return True 
        return value.isspace() 
    
    @staticmethod
    def validate_integer_input(value:str, min_value:int=None) -> bool:   
        """
        Validates integer input 

        Parameters
        ----------
            value: str
                takes a string and converts to integer (index)

            min_value: int 
                minimum input value required
        """
        
        # Returns true if input string is empty 
        if len(value) == 0:
            return True 

        # Checks empty inputs and whitespaces. 
        # Use defaults if whitespace
        if value.isspace():
            return True
        
        # Checks if value is integer. Throws error if cannot be casted to integer
        try:
            int(value)
        except ValueError as e:
            print(e)
            return False
            
        # Checks for negative values
        assert int(value) >= 0, "Value must be positive."        

        # Returns true if no mininum value is specified
        if min_value is None:
            return True

        # Checks if value is greater than minimum only if minimimum value is specified
        assert int(value) > min_value, f"Value must be greater than {min_value}"

        # Returns True if no errors are raised
        return True
    
    

    @staticmethod
    def error_msg(source:str, value:any):
        print(f"Invalid {source}. Value: {value}") 


    @staticmethod 
    def generate_options(options, show_exit:bool=True):
        if show_exit:
            print(f"0. Exit")

        for index, option in enumerate(options):
            print(f"{index+1}. {option}")
            

    @staticmethod 
    def prompt(source:str, default:int, min_value:int= None) -> str:
        if min_value is None:
            return f"\n{source} [{default}]: "
     
        return f"\n{source} [>{min_value}, {default}]: "
    

    def get_integer_value(self, source:str, default:int, min_value:int=None) -> int:
        while True:
            inp_val = input(self.prompt(source, default))
            try:
                valid = self.validate_integer_input(inp_val, min_value)
                if not valid:
                    self.error_msg(source, inp_val)
                    continue 
                if self.is_blank(inp_val):
                    print(f"Using default for {source}: {default}")
                    return default 
                return int(inp_val)
            except AssertionError as e:
                print(f"Error. {e}")
         
    

    def get_string_value(self, source:str, default: int, valid_values:list=None, show_exit:bool=False, use_str_input:bool=False) -> str:
        print()
        self.generate_options(valid_values, show_exit=show_exit)
                
        while True: 
            inp_val = input(self.prompt(source, default))
            try: 
                inp_val = int(inp_val)

            except ValueError: 
                # For string inputs 
                if self.is_blank(inp_val):
                    print(f"Using default for {source}: {default}")
                    return default 
                if not use_str_input:
                    # For selecting files (string inputs not allowed)
                    print(f"Invalid input. Use index to select file.")
                    continue 
                # if use str input 
                inp_val_str = inp_val.strip().lower()
                if inp_val_str not in valid_values:
                    print(f"Invalid string input for {source}. Value: {inp_val_str}.")
                    continue 
                return inp_val_str     

                
            if inp_val == 0:
                print(f"Invalid selected value. Try Again.")
                return None 
            
            try:
                return valid_values[inp_val-1]
            except IndexError:
                print(f"Invalid selected value. True Again.")
                continue 



class MomentumTrade(Generic):
    
    def __init__(self):
        # needs symbol, resolution, period, threshold 
        self.symbol = self.get_symbol()
        self.resolution = self.get_resolution()
        self.zscore_period = self.get_zscore_period()
        self.zscore_threshold = self.get_zscore_threshold()

        #self.strategy = self.generate()
        self.strategy = sm.SpreadMomentum(self.symbol, self.resolution, self.zscore_period, self.zscore_threshold)

    def get_symbol(self): 
        # gets string input 
        # temporary 
        available_symbols=sm.ByBitTrader().available_symbols 
        print("Select Symbol")
        value = self.get_string_value(
            "Symbol", 
            default=available_symbols[0], 
            valid_values=sm.ByBitTrader().available_symbols,
            show_exit=True        
        )

        return value
        

    def get_resolution(self):
        # create a dict of resolutions to map readable inputs to bybit format 
        # temporary 
        resolution = 'D'
        return resolution 
    
    def get_zscore_period(self) -> int:
        # integer input 
        # validate integer input 
        value = self.get_integer_value(
            source = "Z-Score Period", 
            default = 10, 
            min_value = 2
        )
        return value 
        
    def get_zscore_threshold(self) -> int: 
        value = self.get_integer_value(
            source = "Z-Score Threshold",
            default = 1,
            min_value = 1 
        ) 
        return value 
    
    def generate(self) -> sm.SpreadMomentum:
        print()
        self.strategy.get_signal_today()
        print()


    def plot(self):
        print()
        print("===== PLOT FIGURES =====")
        plots = self.strategy.plots 
        options = {
            "Z-Score" : plots.plot_z_score, 
            "OHLC" : plots.plot_ohlc,
            "Backtest" : plots.plot_backtest, 
            "Benchmark" : plots.plot_buy_and_hold_comparison, 
            "Annual Returns" : plots.plot_annual_returns_comparison
        }

        self.generate_options(options.keys())
        try:
            plot = input("Select Option: ")
            if self.is_blank(plot):
                return None 
            plot = int(plot)
            if plot == 0:
                return None 
            keys = list(options.keys())
            options[keys[plot-1]]()
            self.plot()
        except ValueError as e:
            print("Invalid input. Use index to select option.")
            print("Error: {e}")
            self.plot()

        print()  
        

if __name__ == "__main__": 
    ## generate trade parameters here 
    ## Add option in loop to modify current configuration 
    print("============================")
    print("========= MOMENTUM =========")
    print("============================") 
    trade = MomentumTrade() 
    while True: 
        trade.generate()
        trade.plot()

        # Delete this later
        inp = input("Press any key to continue..")
        while True: 
            last_config = input("Use last config? [y/n]: ")
            if last_config.lower() == 'y':
                break 
            if last_config.lower() == 'n':
                trade = MomentumTrade() 
                break 
            else:
                continue 
