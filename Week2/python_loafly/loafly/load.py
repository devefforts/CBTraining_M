"""Load: save each order to the flaky API, with retry. Do not edit gateway.py."""

import logging
import time

from gateway import save_to_orders_api
from loafly.config import SETTINGS

logger = logging.getLogger("loafly")


def save_order_with_retry(order, discounted_total):
    retries = SETTINGS["retry_count"]
    wait = SETTINGS["retry_wait_seconds"]
    last_error = None

    for attempt in range(1, retries + 1):
        try:
            result = save_to_orders_api(order.order_id, discounted_total)
            logger.info(
                "Saved order %s for %s total=%.2f %s (attempt %s)",
                order.order_id,
                order.customer,
                discounted_total,
                SETTINGS["currency"],
                attempt,
            )
            return result
        except ConnectionError as exc:
            last_error = exc
            logger.warning(
                "Save failed for order %s (attempt %s/%s): %s",
                order.order_id,
                attempt,
                retries,
                exc,
            )
            if attempt < retries:
                time.sleep(wait)

    logger.error("Gave up saving order %s after %s attempts: %s", order.order_id, retries, last_error)
    return None


def load_orders(orders_with_totals):
    saved = 0
    failed = 0
    for order, total in orders_with_totals:
        if save_order_with_retry(order, total) is None:
            failed += 1
        else:
            saved += 1
    return saved, failed
