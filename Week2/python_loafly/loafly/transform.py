"""Transform: clean prices, skip bad items, build Order objects, apply discount."""

import logging

from loafly.config import SETTINGS
from loafly.models import Order

logger = logging.getLogger("loafly")


def clean_price(text):
    """Strip spaces and commas, then turn the text into a float."""
    cleaned = text.strip().replace(",", "")
    return float(cleaned)


def apply_discount(price, percent):
    """Take percent off the price. percent comes from config, not a magic 10."""
    return price - price * percent / 100


def transform_orders(rows):
    grouped = {}
    for row in rows:
        oid = row["order_id"]
        if oid not in grouped:
            grouped[oid] = Order(oid, row["customer"])

        item_name = row["item_name"]
        raw_price = row["item_price"]
        try:
            price = clean_price(raw_price)
        except (TypeError, AttributeError, ValueError):
            # blank / missing / junk price: skip this item, keep the rest of the run
            logger.warning(
                "Skipping item with missing or bad price: order=%s item=%s price=%r",
                oid,
                item_name,
                raw_price,
            )
            continue
        finally:
            logger.debug("Finished price parse attempt for order=%s item=%s", oid, item_name)

        grouped[oid].add_item(item_name, price)

    percent = SETTINGS["discount_percent"]
    result = []
    for order in grouped.values():
        discounted = apply_discount(order.total(), percent)
        result.append((order, discounted))
    return result
