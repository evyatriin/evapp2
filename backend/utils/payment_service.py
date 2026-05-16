"""UPI payment service for EV charging sessions."""
from __future__ import annotations

import hashlib
import logging
import os
import time
import urllib.parse
from typing import Any, Dict

logger = logging.getLogger(__name__)

_UPI_VPA = os.getenv("UPI_VPA", "evrouter@upi")
_PAYMENT_API_URL = os.getenv("PAYMENT_API_URL", "")
_PAYMENT_API_KEY = os.getenv("PAYMENT_API_KEY", "")


class PaymentService:
    """Handles UPI collect requests, payment verification, refunds, and receipts."""

    # ------------------------------------------------------------------
    # Create UPI collect
    # ------------------------------------------------------------------

    async def create_upi_collect(
        self,
        phone: str,
        amount: float,
        description: str,
        reference_id: str,
    ) -> str:
        """Generate a UPI deep link for the given collect request.

        If a real payment gateway is configured (PAYMENT_API_URL), it calls the
        API and returns the deep link from the response.  Otherwise it generates
        a standard UPI intent URL that can be opened on the device.

        Returns:
            A UPI deep link / intent URL string.
        """
        if _PAYMENT_API_URL:
            try:
                import httpx

                async with httpx.AsyncClient(timeout=10) as client:
                    resp = await client.post(
                        f"{_PAYMENT_API_URL.rstrip('/')}/collect",
                        json={
                            "phone": phone,
                            "amount": amount,
                            "description": description,
                            "reference_id": reference_id,
                            "vpa": _UPI_VPA,
                        },
                        headers={
                            "Authorization": f"Bearer {_PAYMENT_API_KEY}",
                            "Content-Type": "application/json",
                        },
                    )
                    resp.raise_for_status()
                    data = resp.json()
                    return data.get("upi_link", self._build_upi_link(amount, description, reference_id))
            except Exception as exc:
                logger.error("Payment API create_upi_collect failed: %s", exc)
                # Fall through to local UPI link

        return self._build_upi_link(amount, description, reference_id)

    def _build_upi_link(self, amount: float, description: str, reference_id: str) -> str:
        """Build a standard UPI intent deep link."""
        params = {
            "pa": _UPI_VPA,
            "pn": "EV Router",
            "am": f"{amount:.2f}",
            "cu": "INR",
            "tn": description[:50],
            "tr": reference_id,
        }
        query = urllib.parse.urlencode(params)
        return f"upi://pay?{query}"

    # ------------------------------------------------------------------
    # Verify payment
    # ------------------------------------------------------------------

    async def verify_payment(self, reference_id: str) -> str:
        """Check the payment status for *reference_id*.

        Returns one of: "COLLECTED", "PENDING", "FAILED".
        """
        if _PAYMENT_API_URL:
            try:
                import httpx

                async with httpx.AsyncClient(timeout=10) as client:
                    resp = await client.get(
                        f"{_PAYMENT_API_URL.rstrip('/')}/status/{reference_id}",
                        headers={"Authorization": f"Bearer {_PAYMENT_API_KEY}"},
                    )
                    resp.raise_for_status()
                    data = resp.json()
                    raw_status = data.get("status", "PENDING").upper()
                    # Normalise gateway-specific status strings
                    if raw_status in {"SUCCESS", "COLLECTED", "PAID"}:
                        return "COLLECTED"
                    if raw_status in {"FAILED", "CANCELLED", "EXPIRED"}:
                        return "FAILED"
                    return "PENDING"
            except Exception as exc:
                logger.error("Payment API verify_payment failed for ref=%s: %s", reference_id, exc)
                return "PENDING"

        # Dev fallback — always returns PENDING
        logger.warning(
            "PAYMENT_API_URL not configured — verify_payment returning PENDING for ref=%s",
            reference_id,
        )
        return "PENDING"

    # ------------------------------------------------------------------
    # Refund
    # ------------------------------------------------------------------

    async def refund_payment(self, reference_id: str, amount: float) -> bool:
        """Initiate a refund for *reference_id* of *amount* INR.

        Returns True if the refund was successfully initiated.
        """
        if _PAYMENT_API_URL:
            try:
                import httpx

                async with httpx.AsyncClient(timeout=10) as client:
                    resp = await client.post(
                        f"{_PAYMENT_API_URL.rstrip('/')}/refund",
                        json={"reference_id": reference_id, "amount": amount},
                        headers={
                            "Authorization": f"Bearer {_PAYMENT_API_KEY}",
                            "Content-Type": "application/json",
                        },
                    )
                    resp.raise_for_status()
                    data = resp.json()
                    return data.get("status", "").upper() in {"SUCCESS", "INITIATED", "QUEUED"}
            except Exception as exc:
                logger.error(
                    "Payment API refund_payment failed for ref=%s amount=%.2f: %s",
                    reference_id,
                    amount,
                    exc,
                )
                return False

        logger.warning(
            "PAYMENT_API_URL not configured — refund_payment returning False for ref=%s", reference_id
        )
        return False

    # ------------------------------------------------------------------
    # Receipt generation
    # ------------------------------------------------------------------

    def generate_receipt(self, session_data: Dict[str, Any]) -> Dict[str, Any]:
        """Build a structured receipt dict from session data.

        Args:
            session_data: A dict representing a charging_sessions row.

        Returns:
            A receipt dict suitable for returning to the client or storing.
        """
        session_id = session_data.get("id", "")
        energy_kwh = float(session_data.get("energy_kwh", 0.0))
        amount_inr = float(session_data.get("amount_inr", 0.0))
        duration_seconds = int(session_data.get("duration_seconds", 0))
        charger_id = session_data.get("charger_id", "")
        connector_id = session_data.get("connector_id", "")
        started_at = session_data.get("started_at")
        ended_at = session_data.get("ended_at")
        reference_id = session_data.get("transaction_id", "")

        # Compute breakdown (5% service + 5% GST applied during billing)
        base_energy_cost = round(amount_inr / 1.1, 2)  # approximate reverse of 10% fees
        service_fee = round(base_energy_cost * 0.05, 2)
        gst = round(base_energy_cost * 0.05, 2)

        duration_min = duration_seconds // 60
        duration_sec = duration_seconds % 60

        receipt_hash = hashlib.sha256(
            f"{session_id}:{amount_inr}:{time.time()}".encode()
        ).hexdigest()[:12].upper()

        return {
            "receipt_number": f"EVR-{receipt_hash}",
            "session_id": session_id,
            "charger_id": charger_id,
            "connector_id": connector_id,
            "started_at": str(started_at) if started_at else None,
            "ended_at": str(ended_at) if ended_at else None,
            "duration": f"{duration_min}m {duration_sec}s",
            "energy_kwh": round(energy_kwh, 3),
            "payment": {
                "reference_id": reference_id,
                "total_inr": round(amount_inr, 2),
                "breakup": {
                    "energy_cost": base_energy_cost,
                    "service_fee": service_fee,
                    "gst": gst,
                },
                "currency": "INR",
            },
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
