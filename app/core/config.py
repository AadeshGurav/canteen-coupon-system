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

    # Auth bootstrap: if the users collection is empty at startup, one admin
    # account is created from these. If a password isn't set, a random one
    # is generated and logged prominently (never silently) — the admin can
    # change it immediately after logging in via the Users page. This is the
    # only auth-related env config; everything after first login (more
    # users, roles, password resets) is managed through the app itself.
    initial_admin_username: str = "admin"
    initial_admin_password: str = ""
    session_ttl_hours: int = 12


settings = Settings()
