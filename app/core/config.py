from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Mongo
    mongo_uri: str = "mongodb://localhost:27017"
    mongo_db_name: str = "canteen_coupon"

    # App
    app_name: str = "Canteen Coupon System"
    local_network_host: str = "0.0.0.0"
    local_network_port: int = 8000

    # UPI
    upi_id: str = ""          # e.g. friend@upi
    upi_payee_name: str = ""

    # Bill/PDF output
    bills_output_dir: str = "generated_bills"
    qr_output_dir: str = "generated_qr"

    class Config:
        env_file = ".env"


settings = Settings()
