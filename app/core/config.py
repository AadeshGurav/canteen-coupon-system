from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    # Mongo
    mongo_uri: str = "mongodb://localhost:27017"
    mongo_db_name: str = "canteen_coupon"

    # App
    app_name: str = "Canteen Coupon System"
    local_network_host: str = "0.0.0.0"
    local_network_port: int = 8000

    # local_timezone, upi_id, and upi_payee_name are NOT here — they're
    # admin-editable via PATCH /settings (app/routers/settings.py), stored
    # in the same settings document as grace allowance and meal windows,
    # not env config. An admin can change any of them without a restart.

    # Bill/PDF output
    bills_output_dir: str = "generated_bills"
    qr_output_dir: str = "generated_qr"

    # Logging (the admin's primary debugging tool — see docs/PRD.md §7)
    logs_dir: str = "logs"


settings = Settings()
