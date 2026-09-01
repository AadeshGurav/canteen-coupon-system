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

    # The canteen's own timezone (IANA name, e.g. "Asia/Kolkata") — meal
    # windows like "07:00" are meant as the canteen's local wall-clock hours,
    # not UTC. The server always computes "now" in UTC internally (stored
    # timestamps stay UTC — see app/core/database.py's tz_aware note) and
    # converts to this zone only where local wall-clock time actually
    # matters: resolving the current meal and the Saturday-brunch-only day
    # of week (app/services/scan_service.py). Defaults to UTC rather than
    # guessing a locale — set this explicitly for a real deployment.
    local_timezone: str = "UTC"

    # UPI
    upi_id: str = ""  # e.g. friend@upi
    upi_payee_name: str = ""

    # Bill/PDF output
    bills_output_dir: str = "generated_bills"
    qr_output_dir: str = "generated_qr"

    # Logging (the admin's primary debugging tool — see docs/PRD.md §7)
    logs_dir: str = "logs"


settings = Settings()
