import pyodbc
import json
import pandas as pd
from pathlib import Path
import shutil
import os

class DataConnector:
    def __init__(self, logger, credentials_path, local_data_dir_in, use_local_data,local_data_dir_out):

        self.logger = logger
        self.creds_path = credentials_path
        self.local_data_dir_in = local_data_dir_in
        self.local_data_dir_out = local_data_dir_out
        self.use_local_data = use_local_data

        with open(credentials_path, 'rb') as f:
            self.creds = json.load(f)

        if not use_local_data:
            self.conn = self.create_sql_connection('arribasqlpool1')            


    def create_sql_connection(self, database):

        self.logger.debug(f'Connecting to database {database}', True)

        server = self.creds['server']
        username = self.creds['username_db']
        password = self.creds['password_db']
        driver= self.creds['driver']
        database = database

        conn = pyodbc.connect('DRIVER='+driver+';SERVER='+server+';DATABASE='+database+';UID='+username+';PWD='+ password)

        return conn


    def close_connections(self):

        if not self.use_local_data:

            self.logger.debug('Closing db connections', True)

            self.conn.close()

    def read_data(self, table_name, schema='default', cols=[], csv=False, sql_filter='', keep_default_na=True):

        if self.use_local_data or csv:
            
            try:
                if csv:
                    file_path = f'{self.local_data_dir_in}/{table_name}.csv'
                    df = pd.read_csv(file_path, keep_default_na=keep_default_na)
                else:
                    file_path = f'{self.local_data_dir_in}/{table_name}.txt'
                    df = pd.read_csv(file_path, delimiter='\t', low_memory=False, keep_default_na=keep_default_na)

                self.logger.debug(f'Read {len(df)} rows from file {file_path}')
            except Exception as e:
                self.logger.error(f'Could not read file {file_path}: {str(e)}')
                df = None

        else:

            if schema=='default':
                conn = self.conn
            else:
                self.logger.error(f'Unknown schema specified to read from: {schema}')
                return None

            if len(cols)==0:
                sql_query = f'select * from {table_name}'
            else:
                sql_query = 'select ' + cols.pop(0)                
                for col in cols:
                    sql_query += ', ' + col
                sql_query += ' from ' + table_name

            if sql_filter!='':
                sql_query += ' ' + sql_filter

            try:
                df = pd.read_sql(sql_query, conn)
                self.logger.debug(f'Read {len(df)} rows from table {table_name}')
            except Exception as e:
                self.logger.error(f'Could not read table {table_name} in schema {schema}: {str(e)}')
                df = None
        
        # do some cleanup before returning
        df_obj = df.select_dtypes(['object'])
        if df_obj is not None:
            for col in df_obj.columns:
                try:
                    df[col] = df[col].str.strip()
                except:
                    pass

        return df

    def run_sql_query(self, sql_query):

        try:
            df = pd.read_sql(sql_query, self.conn)
            self.logger.debug(f'SQL query generated {len(df)} rows')
        except Exception as e:
            self.logger.error('Could not run SQL query provided: ' + str(e))
            df = None

        return df

    def write_data(self, df, fname, insert=False):

        try:
            loc = f'{self.local_data_dir_out}/{fname}.csv'
            if insert:
                df.to_csv(loc, index=False, mode='a', header=False)
            else:
                df.to_csv(loc, index=False)
            self.logger.debug(f'Saved {len(df)} rows to {loc}')
        except Exception as e:
            self.logger.error(f'Could not write data to {loc}: {str(e)}')

    def file_exists(self, fname):

        loc = f'{self.local_data_dir_out}/{fname}.csv'
        path = Path(loc)
        return path.exists()

    def copy_file(self, filename, dst):

        src = self.local_data_dir_out
        fname = f'{filename}.csv'
        try:
            shutil.copy(os.path.join(src, fname), os.path.join(dst, fname))
            self.logger.debug(f'Copied file {fname} to {dst}')
            return True
        except Exception as e:
            self.logger.warning(f'Cannot copy file {fname} from {src} to {dst}: {e}')
            return False
