"""Aigate admission control around Decidealot's provider lifecycle."""

import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager, nullcontext
from urllib.parse import urlsplit

import httpx
from decidealot.constants import CLM_PROVIDER_NAME
from decidealot.decisions import Supervisor
from decidealot.errors import ProviderUnavailableError
from decidealot.settings import Settings
from decidealot.supervisor import ProviderUnloadResult
from hardware_lock import HardwareLocks, HardwareLockUnavailable
from pydantic import AnyHttpUrl, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)
_cuda_hardware = "CUDA"
_cpu_hardware = "CPU"
_internal_embeddings_host = "litellm"
_encoder_model_prefix = "local-llamacpp-cuda-"


class CoordinationSettings(BaseSettings):
    """Deployment-owned encoder control, never supplied by decision requests."""

    model_config = SettingsConfigDict(env_prefix="AIGATE_DECIDEALOT_")
    encoder_url: AnyHttpUrl = AnyHttpUrl("http://llamacpp-cuda:8000")
    encoder_enabled: bool = False
    unload_timeout_seconds: float = Field(default=30, gt=0, le=300, allow_inf_nan=False)


class CoordinatedSupervisor:
    """Lock local inference and evict Aigate's encoder before CUDA allocation.

    CLM holds no outer hardware lock. Its LiteLLM embeddings call owns that lock,
    so both direct requests and batches avoid recursively acquiring it.
    """

    def __init__(
        self,
        supervisor: Supervisor,
        settings: Settings,
        coordination: CoordinationSettings,
        locks: HardwareLocks,
        client: httpx.AsyncClient,
    ) -> None:
        self._supervisor = supervisor
        self._hardware = _cuda_hardware if settings.device == "cuda" else _cpu_hardware
        self._locks = locks
        self._client = client
        self._coordination = coordination
        embedding_url = urlsplit(settings.clm_embeddings_url or "")
        uses_local_encoder = (
            settings.clm_enabled
            and embedding_url.hostname == _internal_embeddings_host
            and settings.clm_embeddings_model.startswith(_encoder_model_prefix)
        )
        self._evicts_encoder = coordination.encoder_enabled or uses_local_encoder
        self._shares_encoder_gpu = (
            uses_local_encoder and self._hardware == _cuda_hardware
        )
        self._encoder_lane = asyncio.Lock()

    @property
    def ready(self) -> bool:
        return self._supervisor.ready

    async def start(self) -> None:
        await self._supervisor.start()

    async def stop(self) -> None:
        try:
            await self._supervisor.stop()
        finally:
            await self._client.aclose()

    async def unload_all(self) -> tuple[ProviderUnloadResult, ...]:
        return await self._supervisor.unload_all()

    @asynccontextmanager
    async def acquire(self, provider_name: str) -> AsyncGenerator[None, None]:
        # A resident-provider swap can wait for active CLM. Do not hold CUDA's
        # Redis lock during that wait while CLM still needs it for embeddings.
        lane = self._encoder_lane if self._shares_encoder_gpu else nullcontext()
        async with lane, self._acquire_provider(provider_name):
            yield

    @asynccontextmanager
    async def _acquire_provider(self, provider_name: str) -> AsyncGenerator[None, None]:
        if provider_name == CLM_PROVIDER_NAME:
            async with self._supervisor.acquire(provider_name):
                yield
            return

        try:
            token = await self._locks.acquire(self._hardware)
        except HardwareLockUnavailable as error:
            raise ProviderUnavailableError(
                "Aigate hardware admission is unavailable"
            ) from error
        try:
            if self._hardware == _cuda_hardware and self._evicts_encoder:
                await self._evict_encoder()
            async with self._supervisor.acquire(provider_name):
                yield
        finally:
            await asyncio.shield(self._locks.release(self._hardware, token))

    async def _evict_encoder(self) -> None:
        try:
            response = await self._client.post(
                f"{str(self._coordination.encoder_url).rstrip('/')}/unload",
                timeout=self._coordination.unload_timeout_seconds,
            )
            response.raise_for_status()
            body = response.json()
            if not isinstance(body, dict) or not isinstance(body.get("unloaded"), list):
                raise TypeError("encoder unload response is malformed")
        except (httpx.HTTPError, ValueError, TypeError) as error:
            logger.error(
                "encoder eviction failed", extra={"reason": "encoder_unload_failed"}
            )
            raise ProviderUnavailableError("Aigate encoder eviction failed") from error
        logger.info("encoder eviction completed", extra={"hardware": self._hardware})
