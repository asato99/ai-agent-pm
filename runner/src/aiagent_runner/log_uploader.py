# runner/src/aiagent_runner/log_uploader.py
# ログアップロードクラス
# 参照: docs/design/LOG_TRANSFER_DESIGN.md

import asyncio
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)


@dataclass
class LogUploadConfig:
    """ログアップロード設定

    Note: endpoint is typically set by CoordinatorConfig based on server_url
    or mcp_socket_path. Direct specification is optional.
    """
    enabled: bool = False
    endpoint: str = ""  # Set by CoordinatorConfig or directly
    max_file_size_mb: int = 10
    retry_count: int = 3
    retry_delay_seconds: float = 1.0


class LogUploader:
    """
    ログファイルをRESTサーバーにアップロードするクラス

    非同期でログファイルをプロジェクトのworkingDirectory配下に転送する。
    リトライ機能付きで、一時的なネットワーク障害に対応。
    """

    def __init__(self, config: LogUploadConfig, coordinator_token: str):
        """
        LogUploaderを初期化

        Args:
            config: アップロード設定
            coordinator_token: 認証用トークン
        """
        self.config = config
        self.coordinator_token = coordinator_token

    async def upload(
        self,
        log_file_path: str,
        execution_log_id: str,
        agent_id: str,
        task_id: str,
        project_id: str
    ) -> Optional[str]:
        """
        ログファイルをアップロード

        Args:
            log_file_path: ログファイルのローカルパス
            execution_log_id: 実行ログID
            agent_id: エージェントID
            task_id: タスクID
            project_id: プロジェクトID

        Returns:
            成功時: アップロード先のパス
            失敗時: None
        """
        # 無効化されている場合はスキップ
        if not self.config.enabled:
            logger.debug("Log upload is disabled")
            return None

        # ファイル存在確認
        path = Path(log_file_path)
        if not path.exists():
            logger.warning(f"Log file not found: {log_file_path}")
            return None

        # ファイルサイズ確認
        file_size_mb = path.stat().st_size / (1024 * 1024)
        if file_size_mb > self.config.max_file_size_mb:
            logger.warning(
                f"Log file too large: {file_size_mb:.2f}MB > {self.config.max_file_size_mb}MB"
            )
            return None

        # リトライ付きでアップロード
        for attempt in range(self.config.retry_count):
            try:
                result = await self._do_upload(
                    path,
                    execution_log_id,
                    agent_id,
                    task_id,
                    project_id
                )
                if result:
                    return result
            except Exception as e:
                logger.warning(
                    f"Upload attempt {attempt + 1}/{self.config.retry_count} failed: {e}"
                )

            # 最後のリトライでない場合は待機
            if attempt < self.config.retry_count - 1:
                await asyncio.sleep(self.config.retry_delay_seconds)

        logger.error(f"All {self.config.retry_count} upload attempts failed")
        return None

    async def _do_upload(
        self,
        file_path: Path,
        execution_log_id: str,
        agent_id: str,
        task_id: str,
        project_id: str
    ) -> Optional[str]:
        """
        実際のアップロード処理

        Returns:
            成功時: アップロード先のパス
            失敗時: None
        """
        headers = {
            "Authorization": f"Bearer {self.coordinator_token}"
        }

        # multipart/form-dataを構築
        data = aiohttp.FormData()
        data.add_field("execution_log_id", execution_log_id)
        data.add_field("agent_id", agent_id)
        data.add_field("task_id", task_id)
        data.add_field("project_id", project_id)
        data.add_field(
            "log_file",
            file_path.read_bytes(),
            filename=file_path.name,
            content_type="text/plain"
        )
        data.add_field("original_filename", file_path.name)

        async with aiohttp.ClientSession() as session:
            async with session.post(
                self.config.endpoint,
                data=data,
                headers=headers
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    if result.get("success"):
                        logger.info(
                            f"Log uploaded successfully: {result.get('log_file_path')}"
                        )
                        return result.get("log_file_path")
                    else:
                        logger.warning(f"Upload response indicates failure: {result}")
                        return None
                else:
                    error_text = await response.text()
                    logger.warning(
                        f"Upload failed with status {response.status}: {error_text}"
                    )
                    return None
