import pandas as pd

# from libs.logger import Logger
from .logger import Logger

def read_data(logger, fname, csv=False, full_path_provided=False, label='na'):
    
    data = None
    data_folder = None

    if full_path_provided:
        file_loc = fname
    else:
        file_loc = data_folder + fname

    try:
        if csv:
            data = pd.read_csv(file_loc)
        else:
            data = pd.read_csv(file_loc, delimiter='\t', low_memory=False)
        logger.debug(f'Read {str(len(data))} rows from {fname} ({label})')
    except Exception as e:
        logger.error('Unable to read data from ' + file_loc + ' - ' + str(e))

    return data


def test_pkey(logger, old_df, new_df, pkey):

    # check key exists in both
    if pkey not in old_df.columns or pkey not in new_df.columns:
        logger.error(f'Primary key {pkey} not found in one or both of the datasets')
        return False

    # check unique
    if len(old_df) != len(old_df[pkey].unique()):
        logger.error(f'Primary key {pkey} not unique in old dataset')
        return False

    if len(new_df) != len(new_df[pkey].unique()):
        logger.error(f'Primary key {pkey} not unique in new dataset')
        return False

    logger.debug('Primary key tests pass')

    return True

def test_joins(logger, old_df, new_df, pkey):

    logger.debug('Testing joins', True)

    old_keys = set(old_df[pkey])
    new_keys = set(new_df[pkey])
    both_keys = old_keys.intersection(new_keys)

    old_only = old_keys - both_keys
    new_only = new_keys - both_keys

    issues_found = 0
    if len(old_only)>0:
        logger.warning(f'Rows in old not in new: {len(old_only)} ({100*round(len(old_only)/len(old_keys),4)}%)')
        issues_found += 1
    if len(new_only)>0:
        logger.warning(f'Rows in new not in old: {len(new_only)} ({100*round(len(new_only)/len(new_keys),4)}%)')
        issues_found += 1

    if issues_found==0:
        logger.debug('Join tests pass')


def compare_columns(logger, old_df, new_df):

    logger.debug('Comparing columns', True)

    old_cols = set(old_df.columns)
    new_cols = set(new_df.columns)
    both_cols = old_cols.intersection(new_cols)

    old_only = old_cols - both_cols
    new_only = new_cols - both_cols

    n_issues = 0

    if len(old_only)>0:
        logger.warning(f'There are {len(old_only)} columns in old not in new: ' + " ".join([str(x) for x in old_only]))
        n_issues += 1

    if len(new_only)>0:
        logger.warning(f'There are {len(new_only)} columns in new not in old: ' + " ".join([str(x) for x in new_only]))
        n_issues += 1

    if n_issues==0:
        logger.debug('Columns match exactly')
        return True
    else:
        return False

def compare_content(logger, old_df, new_df, pkey, date_fields, datetime_fields, day_first_in_dates, num_tolerances):

    logger.debug('Comparing content', True)

    cols = set(old_df.columns).intersection(set(new_df.columns))
    cols = cols - {pkey}

    df = old_df.merge(new_df, on=pkey)
    n_issues=0

    for col in cols:
        col_x = f'{col}_x'
        col_y = f'{col}_y'
                
        if col in date_fields:
            df['diff'] = compare_date_fields(df[col_x], df[col_y], day_first_in_dates)
        elif df[col_x].dtype in ['float64', 'int64'] and df[col_y].dtype in ['float64', 'int64']:
            if type(num_tolerances) is dict:
                if col in num_tolerances:
                    num_tolerance = num_tolerances[col]
                else:
                    num_tolerance = num_tolerances['default']
            else:
                num_tolerance = num_tolerances

            df['diff'] = compare_numerical_fields(df[col_x], df[col_y], num_tolerance)
        else:
            df[col_x].fillna('NA', inplace=True)
            df[col_y].fillna('NA', inplace=True)
            df['diff'] = df[col_x]==df[col_y]
        diff_avg = df['diff'].mean()
        if diff_avg<1:
            if diff_avg>0.98:
                logger.debug(f'Column {col} match rate: {diff_avg}')
            elif diff_avg>0.9:
                logger.warning(f'Column {col} match rate: {diff_avg}')
            else:
                logger.error(f'Column {col} match rate: {diff_avg}')
            n_issues += 1

    if n_issues==0:
        logger.debug('Content matches exactly')

    return df

def compare_date_fields(old, new, dayfirst=False):

    old_date = pd.to_datetime(old, errors='coerce', dayfirst=dayfirst)
    new_date = pd.to_datetime(new, errors='coerce', dayfirst=dayfirst)

    old_date.fillna('1900-01-01', inplace=True)
    new_date.fillna('1900-01-01', inplace=True)

    diff = old_date==new_date

    return diff

def compare_numerical_fields(old, new, tolerance):

    # TODO: Implement a separate test for NAs, because we can accidentaly miss an issue if the correct value is 0, but one DF has missing values and we impute them to 0.
    old.fillna(0, inplace=True)
    new.fillna(0, inplace=True)

    diff = abs(old - new) < tolerance

    return diff

def store_results(logger, fname):
        
    body = ''
    for log in logger.logs:
        body += log['timestamp'] + ' ' + log['severity'] + ' ' + log['message']
        body+= '\n'

    with open(fname, 'w') as f:
        f.write(body)


def run_comparison(logger, old_df, new_df, pkey, old_cols_exclude, date_fields, datetime_fields, day_first_in_dates=False, num_tolerances=0.0001, out_file=None):

    logger.debug('Starting comparison', True)

    logger.debug('Numeral tolerances: ' + str(num_tolerances))

    old_df.drop(columns=old_cols_exclude, inplace=True)

    if not test_pkey(logger, old_df, new_df, pkey):
        return

    test_joins(logger, old_df, new_df, pkey)
    compare_columns(logger, old_df, new_df)
    combined_df = compare_content(logger, old_df, new_df, pkey, date_fields, datetime_fields, day_first_in_dates, num_tolerances)

    if out_file is not None:
        store_results(logger, out_file)

    logger.debug('Completed comparison', True)

    return combined_df

def map_values_prior_to_comparison(logger, df, value_mappings):

    logger.debug('Mapping values prior to doing the comparison')

    for col, mapping in value_mappings.items():
        for x,y in mapping.items():
            if x=='null':
                df[col].fillna(y)
            else:
                df[col] = df[col].replace(x, y)

    return df    


#logger = Logger() 

if False:
    old_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data/case_info.csv', csv=True, full_path_provided=True)
    new_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data test/case_info.csv', csv=True, full_path_provided=True)
    pkey = 'CaseNumber'
    #old_cols_exclude=['CostsTotal','TotalCharge','CostsUnbilled']
    old_cols_exclude=[]
    date_fields = ['DateOfReferral', 'ConditionDate', 'DateClosed', 'DateOpened']
    datetime_fields = []
    day_first_in_dates = True
elif False:
    if False:
        old_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data/vCaseContactRoleClient.txt', csv=False, full_path_provided=True)    
        new_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data test/vCaseContactRoleClient.csv', csv=True, full_path_provided=True)
    else:
        old_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data/vCaseContactRoleEmployer.txt', csv=False, full_path_provided=True)    
        new_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data test/vCaseContactRoleEmployer.csv', csv=True, full_path_provided=True)
    pkey = 'CaseNumber'
    old_cols_exclude=[]
    date_fields = ['DateOfBirth']
    datetime_fields = []
    day_first_in_dates = False
elif False:
    old_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data/claim_rollup.csv', csv=True, full_path_provided=True)
    new_df = read_data(logger, 'C:/Users/wils_ymarom/Documents/Data test/claim_rollup.csv', csv=True, full_path_provided=True)
    pkey = 'ClaimNo'
    old_cols_exclude=[]
    date_fields = []
    datetime_fields = []
    day_first_in_dates = True
    value_maps = {}
else:
    pass

# old_df = map_values_prior_to_comparison(logger, old_df, value_maps)
# run_comparison(logger, old_df, new_df, pkey, old_cols_exclude, date_fields, datetime_fields, day_first_in_dates)
# print('done')

