"""Launch unmodified Decidealot with Aigate-owned resource admission."""

import httpx
import uvicorn
from coordinator import CoordinatedSupervisor, CoordinationSettings
from decidealot.app import create_app
from decidealot.logging_config import configure_logging
from decidealot.settings import Settings
from decidealot.supervisor import ProviderSupervisor
from hardware_lock import get_locks


def main() -> None:
    settings = Settings()
    coordination = CoordinationSettings()
    configure_logging(settings.log_level, settings.log_file)
    supervisor = CoordinatedSupervisor(
        ProviderSupervisor(settings),
        settings,
        coordination,
        get_locks(),
        httpx.AsyncClient(),
    )
    uvicorn.run(
        create_app(settings, supervisor=supervisor),
        host=settings.listen_host,
        port=settings.listen_port,
        log_config=None,
    )


if __name__ == "__main__":
    main()
