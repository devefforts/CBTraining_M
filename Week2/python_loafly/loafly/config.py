"""All settings live here. Logic files must read SETTINGS, not type 10 or file names."""

from pathlib import Path
import os

# Folder that contains run_pipeline.py (this project's root)
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _load_dotenv(path: Path) -> None:
    """Read KEY=value lines from .env into os.environ. Standard library only."""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_dotenv(PROJECT_ROOT / ".env")

SETTINGS = {
    "currency": "INR",
    "discount_percent": 10,
    "input_file": str(PROJECT_ROOT / "data" / "raw_orders.csv"),
    "retry_count": 3,
    "retry_wait_seconds": 0.4,
    "log_file": str(PROJECT_ROOT / "logs" / "loafly.log"),
    "api_key": os.getenv("LOAFLY_API_KEY", "demo-key"),
}
