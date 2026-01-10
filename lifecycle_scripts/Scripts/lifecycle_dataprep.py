import pandas as pd
import numpy as np
import datetime
import json

from libs.logger import Logger
from libs.connectors import DataConnector

use_local_data = True
exclude_travel = False

def get_weekly_estimates(logger, cost, claims, exclude_travel):

    logger.debug('Getting weekly estimates', True)

    max_weeks = 20

    exclude_types = ['Travel', 'Reporting']

    # exclude travel activities if required
    if exclude_travel:
        logger.debug('Removing travel activities')
        cost = cost[~cost['type'].isin(exclude_types)]

    # Prepare claim dates
    claims_df = claims[['ClaimNo', 'first_referral', 'DateClosedLast']]
    claims_df['first_referral'] = pd.to_datetime(claims_df['first_referral'])
    claims_df['date_closed'] = pd.to_datetime(claims_df['DateClosedLast'])

    # Work out day differences from date of referral
    activity_df = cost[cost['BillDate'].notnull()]
    activity_df = activity_df.merge(claims_df[['ClaimNo', 'first_referral']], on='ClaimNo')
    activity_df['activity_date'] = pd.to_datetime(activity_df['BillDate'].str[:10])
    activity_df['diff_days'] = (activity_df['activity_date'] - activity_df['first_referral']).dt.days
    activity_df = activity_df[activity_df['diff_days']>=0]

    # Get weekly diffs and aggregate
    activity_df['diff_weeks'] = (np.floor(activity_df['diff_days']/7)+1).astype('int')
    agg = {
        'Id': 'count',
        'CostsTotalExTax':'sum',
        'Duration':'sum'
    }
    weekly_df = activity_df.groupby(['ClaimNo', 'diff_weeks'], as_index=False).agg(agg)
    weekly_df.rename(columns={'Id': 'n_activities', 'CostsTotalExTax':'total_cost', 'Duration':'total_duration'}, inplace=True)

    # Create a separate aggregation by cost type
    weekly_df_by_type = activity_df.groupby(['ClaimNo', 'diff_weeks', 'type'], as_index=False).agg(agg)
    weekly_df_by_type.rename(columns={'Id': 'n_activities', 'CostsTotalExTax':'total_cost', 'Duration':'total_duration'}, inplace=True)
    weekly_df_by_type_pivot = pd.pivot(weekly_df_by_type, index=['ClaimNo', 'diff_weeks'], values=['n_activities', 'total_cost', 'total_duration'], columns=['type'])
    weekly_df_by_type_pivot.fillna(0, inplace=True)    
    weekly_df_by_type_pivot.columns = [':'.join(col) for col in weekly_df_by_type_pivot.columns]
    weekly_df_by_type_pivot.reset_index(inplace=True)

    # Create a DF will all possible week numbers and claim numbers
    week_nos = pd.DataFrame(pd.Series(range(1, max_weeks)), columns=['week_num'])
    claim_nos = pd.DataFrame(activity_df['ClaimNo'].unique(), columns=['ClaimNo'])
    week_nos['join_col']=1
    claim_nos['join_col']=1
    claim_week_nos = claim_nos.merge(week_nos).drop(columns=['join_col'])

    # remove weeks that are beyond the claim closed date
    claims_df['date_closed'] = pd.to_datetime(claims_df['date_closed'].fillna(datetime.date.today()))
    claims_df['diff_days'] = (claims_df['date_closed'] - claims_df['first_referral']).dt.days
    claims_df['week_num_max'] = (np.floor(claims_df['diff_days']/7)+1).astype('int')
    claim_week_nos = claim_week_nos.merge(claims_df[['ClaimNo', 'week_num_max']])    
    claim_week_nos = claim_week_nos[claim_week_nos['week_num'] <= claim_week_nos['week_num_max']]

    # left-join the actual data zero-ing the nulls
    weekly_df_all = claim_week_nos.merge(weekly_df, how='left', left_on=['ClaimNo', 'week_num'], right_on=['ClaimNo', 'diff_weeks'])
    weekly_df_all = weekly_df_all.merge(weekly_df_by_type_pivot, how='left', left_on=['ClaimNo', 'week_num'], right_on=['ClaimNo', 'diff_weeks'])
    weekly_df_all.fillna(0.0, inplace=True)
    
    return weekly_df_all

def generate_milestones(logger, cost_weekly):

    logger.debug('Generating milestones', True)

    milestone_wks = [2,4,6,8,12,16,20]
    active_mins = 10 # threshold for determinning that a week has been active (from analysis)
    cost_weekly['active'] = cost_weekly['total_duration'] >= active_mins

    milestone_dfs = []
    for milestone in milestone_wks:
        cost_weekly_subset = cost_weekly[(cost_weekly['week_num']<=milestone) & (cost_weekly['week_num_max']>=milestone)]
        milestone_df = cost_weekly_subset.groupby('ClaimNo', as_index=False).sum()
        milestone_df[f'activity_score{active_mins}'] = milestone_df['active']/milestone        

        cols_to_keep = []
        cols_to_keep_rename = []
        for col in list(milestone_df.columns):
            if 'n_activities' in col or 'total_cost' in col or 'total_duration' in col or 'activity_score' in col:
                cols_to_keep.append(col)
                cols_to_keep_rename.append(f'{col}_wk{milestone}')
        
        milestone_df.index = milestone_df['ClaimNo']
        milestone_df = milestone_df[cols_to_keep]
        milestone_df.columns = cols_to_keep_rename
        milestone_dfs.append(milestone_df)

    milestones_all = pd.concat(milestone_dfs, axis=1)
    milestones_all['ClaimNo'] = milestones_all.index
    milestones_all.reset_index(drop=True, inplace=True)
    milestones_all.fillna(-1, inplace=True) # This signifies that the milestone is beyond when the case was closed

    return milestones_all

def extract_cost_type(desc):

    desc = desc.lower()

    if 'travel' in desc:
        return 'Travel'

    if 'report' in desc:
        return 'Reporting'

    if 'assessment' in desc:
        return 'Assessment'

    if 'communic' in desc:
        if 'treat' in desc or 'health' in desc or 'medic' in desc:
            return 'CommunicationTreating'
        else:
            return 'CommunicationOther'

    if 'conferenc' in desc:
        return 'CaseConference'

    return 'Other'

def categorise_activities(logger, cost):

    logger.debug('Categorising activities', True)

    # the coding and classifications here are based on analysis conduced in May 2024.

    # categorise from activity name first
    cost['activity_lower'] = cost['ActivityName'].str.lower()
    cost['activity_lower'].fillna('unknown', inplace=True)
    cost['activity_grp'] = 'Other'
    cost.loc[cost['activity_lower'].str.contains('training'), 'activity_grp'] = 'Coaching'
    cost.loc[cost['activity_lower'].str.contains('coaching'), 'activity_grp'] = 'Coaching'
    cost.loc[cost['activity_lower'].str.contains('conference'), 'activity_grp'] = 'Case Conference'
    cost.loc[cost['activity_lower'].str.contains('liais'), 'activity_grp'] = 'Contact'
    cost.loc[cost['activity_lower'].str.contains('phone'), 'activity_grp'] = 'Contact'
    cost.loc[cost['activity_lower'].str.contains('email'), 'activity_grp'] = 'Contact'
    cost.loc[cost['activity_lower'].str.contains('communic'), 'activity_grp'] = 'Contact'
    cost.loc[cost['activity_lower'].str.contains('assessment'), 'activity_grp'] = 'Assessment'
    cost.loc[cost['activity_lower'].str.contains('report'), 'activity_grp'] = 'Report'
    cost.loc[cost['activity_lower'].str.contains('review'), 'activity_grp'] = 'Review'
    cost.loc[cost['activity_lower'].str.contains('travel'), 'activity_grp'] = 'Travel'
    
    # now categorise from template name
    cost['template_lower'] = cost['TemplateName'].str.lower()
    cost['template_lower'].fillna('unknown', inplace=True)
    cost['template_grp'] = 'Other'
    cost.loc[cost['template_lower'].str.contains('assessment'), 'template_grp'] = 'Assessment'
    cost.loc[cost['template_lower'].str.contains('training'), 'template_grp'] = 'Coaching'
    cost.loc[cost['template_lower'].str.contains('coaching'), 'template_grp'] = 'Coaching'
    cost.loc[cost['template_lower'].str.contains('conference'), 'template_grp'] = 'Case Conference'
    cost.loc[cost['template_lower'].str.contains('report'), 'template_grp'] = 'Report'
    cost.loc[cost['template_lower'].str.contains('review'), 'template_grp'] = 'Review'
    cost.loc[cost['template_lower'].str.contains('travel'), 'template_grp'] = 'Travel'
    cost.loc[cost['template_lower'].str.contains('contact'), 'template_grp'] = 'Contact'
    
    # and now combine them into a single classification
    cost['type'] = cost['activity_grp']
    cost.loc[(cost['template_grp']=='Report') & (cost['activity_grp']=='Other'), 'type'] = 'Report'
    cost.loc[cost['template_grp'].isin(['Coaching', 'Case Conference', 'Travel', 'Review', 'Assessment']), 'type'] = cost['template_grp']
    cost.loc[cost['activity_grp']=='Travel', 'type'] = 'Travel'    

    return cost

def get_claim_totals(logger, claims_cost):

    logger.debug('Removing claims that have fixed-fee costs')

    # Figure out the total and % of the fixed-fee costs for each claim
    all_costs = claims_cost.groupby('ClaimNo').agg({'CostsTotalExTax':'sum'})
    claims_cases_cost_hourly = claims_cost[claims_cost['BillType']==1] #TODO: check this is still right
    hourly_costs = claims_cases_cost_hourly.groupby('ClaimNo').agg({'CostsTotalExTax':'sum'})
    hourly_costs.rename(columns={'CostsTotalExTax':'CostsTotalExTaxHourly'}, inplace=True)
    all_costs = all_costs.merge(hourly_costs, left_index=True, right_index=True, how='left')
    all_costs.fillna(0, inplace=True)
    all_costs = all_costs[all_costs['CostsTotalExTax']>0]
    all_costs['hourly_pctg'] = (all_costs['CostsTotalExTaxHourly'] / all_costs['CostsTotalExTax'])
           
    # Finalise DF
    all_costs['ClaimNo'] = all_costs.index
    all_costs.reset_index(drop=True, inplace=True)
    all_costs = all_costs[['ClaimNo', 'CostsTotalExTax', 'hourly_pctg']].rename(columns={'CostsTotalExTax':'claim_total_cost', 'hourly_pctg': 'claim_cost_hourly_pctg'})
    
    return all_costs

def data_prep():

    logger = Logger()

    with open('config.json', 'rb') as f:
        config = json.load(f)

    data_dir_in = config['data_folder_in']    
    data_dir_out = config['data_folder_out']
    ref_data_dir = config['ref_data_folder']

    logger.debug('Starting lifecycle dataprep', True)

    data_conn = DataConnector(logger, 'creds.json', data_dir_in, use_local_data, data_dir_out)    

    claims = data_conn.read_data('claim_rollup', csv=True)
    cost = data_conn.read_data('case_bill', csv=True)
    claim_rollup_mapping = data_conn.read_data('claim_rollup_mapping', csv=True)
     
    # TODO: modify the ETL to include the template name in the case_bill extract, and the delete the below two lines
    cost_templates = data_conn.read_data('CaseBillTemplate', csv=True)
    #cost = cost[['Id']].merge(cost_templates[['Id', 'TemplateName', 'ActivityName', 'BillDate', 'CostsTotalExTax']], on='Id', how='left')
    cost_templates['CostsTotalExTax'] = cost_templates['SubTotal'].fillna(0)/100
    cost_templates['Duration'] = cost_templates['Minutes'].fillna(0)
    #cost_templates = cost_templates[cost_templates['BillType']<3]
    cost = cost_templates

    cost = categorise_activities(logger, cost)
    claims_cost = claim_rollup_mapping.merge(cost, how='left', on=['CaseServiceId'])
    
    claim_totals = get_claim_totals(logger, claims_cost)
    claim_totals.to_csv(f'{data_dir_out}/claim_cost_totals.csv', index=False)

    cost_weekly = get_weekly_estimates(logger, claims_cost, claims, exclude_travel)    
    if exclude_travel:
        cost_weekly.to_csv(f'{data_dir_out}/cost_weekly_ex_travel.csv', index=False)
    else:
        cost_weekly.to_csv(f'{data_dir_out}/cost_weekly.csv', index=False)

    milestones = generate_milestones(logger, cost_weekly)

    if exclude_travel:
        milestones.to_csv(f'{data_dir_out}/milestones_ex_travel.csv', index=False)
    else:
        milestones.to_csv(f'{data_dir_out}/milestones.csv', index=False)

    data_conn.close_connections()
    
    logger.debug('Completed lifcycle dataprep', True)

    
data_prep()
print('done')
