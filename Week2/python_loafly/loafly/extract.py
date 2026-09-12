"""Extract: read the CSV. No cleaning, no discount, no save."""

import csv
from loafly.config import SETTINGS


def extract_rows(path=None):
    file_path = path or SETTINGS["input_file"]
    with open(file_path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))
