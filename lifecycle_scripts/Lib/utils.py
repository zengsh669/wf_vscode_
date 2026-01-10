import pandas as pd

from libs.logger import Logger

# General utils

def no_dups(logger, df, pkey):

    if pkey not in df.columns:
        logger.warning(f'Cannot find {pkey} in dataframe provided to work out if dups exist')
        return True
    
    else:
        return len(df)==len(df[pkey].unique())

# Method to add a new column to a CSV file.
# Include a 'pos' parameter to add the column at a specified position (first column is position 0)
def add_column_to_csv(logger, fname, col_name, pos=-1):

    logger.debug(f'Adding column {col_name} to csv file {fname}')

    df = pd.read_csv(fname)

    df[col_name] = None
    
    # move col if position specified
    if pos>-1:        
        cols = df.columns
        if pos>len(cols)-2:
            logger.error('Specified column position is higher than the number of columns, aborting. Use -1 to add column to the end')
            return
        new_cols = list(cols[:pos]) + [col_name] + list(cols[pos:-1])        
        df = df[new_cols]

    df.to_csv(fname, index=False)

    

# logger = Logger()
# add_column_to_csv(logger, 'C:/Users/wils_ymarom/Documents/Data test/risk_scores.csv', 'TeamName_last', 7)
# #add_column_to_csv(logger, 'C:/Users/wils_ymarom/Documents/Data test/risk_scores_hist.csv', 'TeamName_last', 7)
# print('done')