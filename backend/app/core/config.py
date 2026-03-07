from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables.

    CRITICAL: jwt_secret_key and database_url have no defaults — the app
    will crash on startup if they are not set in the environment or .env file.
    This prevents accidental use of hardcoded secrets in production.
    """

    database_url: str  # No default — must be set via env
    jwt_secret_key: str  # No default — must be set via env
    redis_url: str = "redis://localhost:6379/0"
    debug: bool = False

    # CORS origins (comma-separated in env, e.g. "http://localhost:3000,https://app.example.com")
    cors_origins: str = ""

    @field_validator("cors_origins", mode="before")
    @classmethod
    def validate_cors_origins(cls, v: str) -> str:
        return v or ""

    @property
    def cors_origin_list(self) -> list[str]:
        """Parse comma-separated CORS origins into a list."""
        if not self.cors_origins:
            return []
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    model_config = {"env_file": ".env", "case_sensitive": False}


settings = Settings()
