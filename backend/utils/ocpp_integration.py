"""OCPP bridge using httpx for communicating with charger management systems."""
from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

import httpx

logger = logging.getLogger(__name__)

_OCPP_BASE_URL = os.getenv("OCPP_BASE_URL", "")
_OCPP_API_KEY = os.getenv("OCPP_API_KEY", "")
_OCPP_TIMEOUT = float(os.getenv("OCPP_TIMEOUT_SECONDS", "10"))


class OCPPManager:
    """HTTP client adapter for an OCPP 1.6/2.0 charge point management system."""

    def __init__(self, charger_id: str, charger_endpoint: Optional[str] = None) -> None:
        self.charger_id = charger_id
        self.base_url = charger_endpoint or _OCPP_BASE_URL
        self._headers = {
            "Content-Type": "application/json",
            "X-API-Key": _OCPP_API_KEY,
        }

    def _url(self, path: str) -> str:
        base = self.base_url.rstrip("/")
        return f"{base}{path}"

    async def start_charging(self, connector_id: str) -> bool:
        """Send a RemoteStartTransaction request to the charger.

        Returns True if the charger accepted the request.
        """
        if not self.base_url:
            logger.warning(
                "OCPP_BASE_URL not configured — simulating start_charging for charger=%s connector=%s",
                self.charger_id,
                connector_id,
            )
            return True  # Simulate acceptance in dev

        try:
            async with httpx.AsyncClient(timeout=_OCPP_TIMEOUT) as client:
                resp = await client.post(
                    self._url(f"/ocpp/chargers/{self.charger_id}/remote-start"),
                    json={"connectorId": connector_id},
                    headers=self._headers,
                )
                resp.raise_for_status()
                data = resp.json()
                status = data.get("status", "").upper()
                accepted = status == "ACCEPTED"
                if not accepted:
                    logger.warning(
                        "OCPP start_charging rejected: charger=%s connector=%s status=%s",
                        self.charger_id,
                        connector_id,
                        status,
                    )
                return accepted
        except httpx.TimeoutException:
            logger.error(
                "OCPP start_charging timeout: charger=%s connector=%s", self.charger_id, connector_id
            )
            return False
        except Exception as exc:
            logger.error(
                "OCPP start_charging error: charger=%s connector=%s error=%s",
                self.charger_id,
                connector_id,
                exc,
            )
            return False

    async def stop_charging(self, connector_id: str) -> bool:
        """Send a RemoteStopTransaction request to the charger.

        Returns True if the charger accepted the request.
        """
        if not self.base_url:
            logger.warning(
                "OCPP_BASE_URL not configured — simulating stop_charging for charger=%s connector=%s",
                self.charger_id,
                connector_id,
            )
            return True

        try:
            async with httpx.AsyncClient(timeout=_OCPP_TIMEOUT) as client:
                resp = await client.post(
                    self._url(f"/ocpp/chargers/{self.charger_id}/remote-stop"),
                    json={"connectorId": connector_id},
                    headers=self._headers,
                )
                resp.raise_for_status()
                data = resp.json()
                return data.get("status", "").upper() == "ACCEPTED"
        except httpx.TimeoutException:
            logger.error(
                "OCPP stop_charging timeout: charger=%s connector=%s", self.charger_id, connector_id
            )
            return False
        except Exception as exc:
            logger.error(
                "OCPP stop_charging error: charger=%s connector=%s error=%s",
                self.charger_id,
                connector_id,
                exc,
            )
            return False

    async def get_live_metrics(self) -> Dict[str, Any]:
        """Fetch live meter values from the charger.

        Returns a dict with keys: energy, current, voltage, power, soc, temperature.
        Falls back to zeroed-out defaults on error.
        """
        defaults: Dict[str, Any] = {
            "energy": 0.0,
            "current": 0.0,
            "voltage": 0.0,
            "power": 0.0,
            "soc": None,
            "temperature": None,
        }

        if not self.base_url:
            logger.debug(
                "OCPP_BASE_URL not configured — returning zero metrics for charger=%s",
                self.charger_id,
            )
            return defaults

        try:
            async with httpx.AsyncClient(timeout=_OCPP_TIMEOUT) as client:
                resp = await client.get(
                    self._url(f"/ocpp/chargers/{self.charger_id}/meter-values"),
                    headers=self._headers,
                )
                resp.raise_for_status()
                data = resp.json()
                return {
                    "energy": float(data.get("energyActiveImportRegister", 0)) / 1000.0,  # Wh -> kWh
                    "current": float(data.get("currentImport", 0.0)),
                    "voltage": float(data.get("voltage", 0.0)),
                    "power": float(data.get("powerActiveImport", 0.0)) / 1000.0,  # W -> kW
                    "soc": data.get("soc"),
                    "temperature": data.get("temperature"),
                }
        except httpx.TimeoutException:
            logger.error("OCPP get_live_metrics timeout: charger=%s", self.charger_id)
            return defaults
        except Exception as exc:
            logger.error("OCPP get_live_metrics error: charger=%s error=%s", self.charger_id, exc)
            return defaults

    async def unlock_connector(self, connector_id: str) -> bool:
        """Send an UnlockConnector request.

        Returns True if the charger confirms the connector was unlocked.
        """
        if not self.base_url:
            logger.warning(
                "OCPP_BASE_URL not configured — simulating unlock_connector for charger=%s connector=%s",
                self.charger_id,
                connector_id,
            )
            return True

        try:
            async with httpx.AsyncClient(timeout=_OCPP_TIMEOUT) as client:
                resp = await client.post(
                    self._url(f"/ocpp/chargers/{self.charger_id}/unlock-connector"),
                    json={"connectorId": connector_id},
                    headers=self._headers,
                )
                resp.raise_for_status()
                data = resp.json()
                return data.get("status", "").upper() == "UNLOCKED"
        except httpx.TimeoutException:
            logger.error(
                "OCPP unlock_connector timeout: charger=%s connector=%s", self.charger_id, connector_id
            )
            return False
        except Exception as exc:
            logger.error(
                "OCPP unlock_connector error: charger=%s connector=%s error=%s",
                self.charger_id,
                connector_id,
                exc,
            )
            return False

    async def get_connector_status(self, connector_id: str) -> str:
        """Return the status string for a specific connector (e.g. 'Available', 'Charging').

        Falls back to 'Unknown' on any error.
        """
        if not self.base_url:
            return "Unknown"

        try:
            async with httpx.AsyncClient(timeout=_OCPP_TIMEOUT) as client:
                resp = await client.get(
                    self._url(f"/ocpp/chargers/{self.charger_id}/connectors/{connector_id}/status"),
                    headers=self._headers,
                )
                resp.raise_for_status()
                data = resp.json()
                return data.get("status", "Unknown")
        except Exception as exc:
            logger.error(
                "OCPP get_connector_status error: charger=%s connector=%s error=%s",
                self.charger_id,
                connector_id,
                exc,
            )
            return "Unknown"


async def get_live_meter_data(charger_id: str) -> Dict[str, Any]:
    """Convenience function: create an OCPPManager and fetch live metrics."""
    manager = OCPPManager(charger_id)
    return await manager.get_live_metrics()
