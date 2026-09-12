"""Run extract -> transform -> load. Start from this folder: python run_pipeline.py"""

from pathlib import Path
import logging
import sys

# Project root on sys.path so "import loafly" and "import gateway" work
ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from loafly.config import SETTINGS
from loafly.extract import extract_rows
from loafly.transform import transform_orders
from loafly.load import load_orders


def setup_logging():
    log_path = Path(SETTINGS["log_file"])
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(log_path, encoding="utf-8"),
        ],
        force=True,
    )


def main():
    setup_logging()
    logger = logging.getLogger("loafly")
    logger.info("Pipeline start. api_key loaded (length=%s)", len(SETTINGS["api_key"] or ""))

    rows = extract_rows()
    logger.info("Extracted %s item rows from %s", len(rows), SETTINGS["input_file"])

    orders = transform_orders(rows)
    logger.info("Built %s orders after skipping bad prices", len(orders))

    saved, failed = load_orders(orders)
    logger.info("Pipeline done. saved=%s failed=%s", saved, failed)


if __name__ == "__main__":
    main()
