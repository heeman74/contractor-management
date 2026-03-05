from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    database_url: str = (
        "postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub"
    )
    redis_url: str = "redis://localhost:6379/0"
    debug: bool = False

    model_config = {"env_file": ".env", "case_sensitive": False}


settings = Settings()
