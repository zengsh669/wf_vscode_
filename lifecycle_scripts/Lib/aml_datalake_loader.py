from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient, Input
from azure.ai.ml.constants import AssetTypes
import pandas as pd
import logging
import os


class DataLoader:
    def __init__(self, source='aml', filename=None, output_dir='dataprep_input'):
        """
        初始化 DataLoader，指定数据来源、文件名和保存路径。
        :param source: 'aml' 或 'datalake'
        :param filename: 要读取的文件名（不含路径）
        :param output_dir: 保存 CSV 的文件夹路径
        """
        self.source = source
        self.filename = filename
        self.output_dir = output_dir
        self.logger = logging.getLogger(__name__)
        logging.basicConfig(level=logging.INFO)

        self.subscription_id = "24fceea3-b944-4568-9028-d77c36beaab5"
        self.resource_group = "rg-machinelearning-prod-ae-001"
        self.workspace_name = "arriba-mlworkspace-prod-ae-001"
        self.credential = DefaultAzureCredential()
        self.ml_client = MLClient(
            credential=self.credential,
            subscription_id=self.subscription_id,
            resource_group_name=self.resource_group,
            workspace_name=self.workspace_name,
        )

        self.default_datalake_prefix = (
            "azureml://subscriptions/24fceea3-b944-4568-9028-d77c36beaab5/"
            "resourcegroups/rg-machinelearning-prod-ae-001/"
            "workspaces/arriba-mlworkspace-prod-ae-001/"
            "datastores/stdataanalyticsadls001/paths/WilsonAI/"
        )

    def load_data(self, datalake_path=None):
        """
        根据 source 加载数据并返回 DataFrame，并保存为 CSV 文件。
        :param datalake_path: 可选，完整的 Data Lake 路径（用于覆盖默认路径）
        :return: pandas DataFrame
        """
        if self.source == 'aml':
            if not self.filename:
                raise ValueError(
                    "filename must be provided when source is 'aml'")
            data_asset = self.ml_client.data.get(name=self.filename, version=1)
            df = pd.read_csv(data_asset.path)
            self.logger.info(
                f"Loaded {len(df)} rows from AML data asset: {self.filename}")

        elif self.source == 'datalake':
            if datalake_path:
                full_path = datalake_path
            elif self.filename:
                full_path = self.default_datalake_prefix + self.filename
            else:
                raise ValueError(
                    "filename or datalake_path must be provided when source is 'datalake'")
            input_data = Input(type=AssetTypes.URI_FILE, path=full_path)
            df = pd.read_csv(input_data.path, header=None)
            self.logger.info(
                f"Loaded {len(df)} rows from Data Lake path: {full_path}")

        else:
            raise ValueError("Invalid source. Must be 'aml' or 'datalake'.")

        # 保存为 CSV 文件
        os.makedirs(self.output_dir, exist_ok=True)
        output_path = os.path.join(self.output_dir, self.filename)
        df.to_csv(output_path, index=False)
        self.logger.info(f"Saved DataFrame to {output_path}")

        return df
