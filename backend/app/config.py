from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Avoclara API"
    app_env: str = "development"
    debug: bool = True
    api_prefix: str = "/api/v1"

    secret_key: str = "change-this-to-a-long-random-string"
    access_token_expire_minutes: int = 60 * 24 * 7

    database_url: str = "sqlite:///./avoclara.db"
    cors_origins: str = "http://localhost:4200,http://localhost:3000"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)


settings = Settings()
