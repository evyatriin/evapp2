"""Secure QR code generator with HMAC signing for EV chargers."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import urllib.parse
from typing import Any, Dict

from config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Secret key
# ---------------------------------------------------------------------------

_DEFAULT_SECRET = "dev-secret-key-change-in-prod"
_raw_secret = getattr(settings, "QR_SIGNING_SECRET", _DEFAULT_SECRET) or _DEFAULT_SECRET
SECRET_KEY = _raw_secret.encode()

if _raw_secret == _DEFAULT_SECRET:
    logger.warning(
        "QR_SIGNING_SECRET is not set — using insecure default. "
        "Set this env var before going to production."
    )


# ---------------------------------------------------------------------------
# Signing / verification helpers
# ---------------------------------------------------------------------------

def _compute_signature(payload_b64: str) -> str:
    """HMAC-SHA256 over the base64 payload, returned as a hex string."""
    return hmac.new(SECRET_KEY, payload_b64.encode(), hashlib.sha256).hexdigest()


def sign_qr_data(payload: Dict[str, Any]) -> str:
    """Encode *payload* and append an HMAC signature.

    Returns:
        A string of the form ``evrouter://charge?d=<b64>&s=<sig>&v=v1``.
    """
    payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    payload_b64 = base64.urlsafe_b64encode(payload_json.encode()).decode()
    sig = _compute_signature(payload_b64)
    query = urllib.parse.urlencode({"d": payload_b64, "s": sig, "v": "v1"})
    return f"evrouter://charge?{query}"


def verify_qr_data(qr_string: str) -> Dict[str, Any]:
    """Parse and verify a signed QR string.

    Args:
        qr_string: The full ``evrouter://charge?…`` string.

    Returns:
        The decoded payload dict.

    Raises:
        ValueError: If the signature is missing, invalid, or the payload is
                    malformed.
    """
    try:
        # Extract query string — support both URI and plain query formats
        if "?" in qr_string:
            qs = qr_string.split("?", 1)[1]
        else:
            qs = qr_string

        params = dict(urllib.parse.parse_qsl(qs))
        version = params.get("v", "")
        payload_b64 = params.get("d", "")
        received_sig = params.get("s", "")

        if version != "v1":
            raise ValueError(f"Unknown QR version: {version!r}")
        if not payload_b64 or not received_sig:
            raise ValueError("Missing payload or signature in QR data")

        expected_sig = _compute_signature(payload_b64)
        if not hmac.compare_digest(expected_sig, received_sig):
            raise ValueError("QR signature verification failed — data may be tampered")

        payload_json = base64.urlsafe_b64decode(payload_b64.encode()).decode()
        return json.loads(payload_json)
    except ValueError:
        raise
    except Exception as exc:
        raise ValueError(f"QR data parse error: {exc}") from exc


def parse_qr_data(qr_string: str) -> Dict[str, Any]:
    """Try signed format first; fall back to parsing legacy format.

    Args:
        qr_string: Any QR string — signed or legacy.

    Returns:
        The parsed payload dict.  For legacy QRs the dict contains
        whatever keys were embedded in the URL query string.

    Raises:
        ValueError: If neither format can be parsed.
    """
    # Attempt signed format
    if "v=v1" in qr_string or "evrouter://charge" in qr_string:
        try:
            return verify_qr_data(qr_string)
        except ValueError as exc:
            logger.warning("Signed QR parse failed (%s), trying legacy format", exc)

    # Legacy: plain URL with query params
    return _parse_legacy_qr(qr_string)


def _parse_legacy_qr(qr_string: str) -> Dict[str, Any]:
    """Parse an unsigned legacy QR URL."""
    try:
        if "?" in qr_string:
            qs = qr_string.split("?", 1)[1]
        else:
            qs = qr_string
        params = dict(urllib.parse.parse_qsl(qs))
        if not params:
            raise ValueError("No query parameters found in legacy QR")
        return params
    except Exception as exc:
        raise ValueError(f"Could not parse legacy QR format: {exc}") from exc


def build_legacy_qr_string(charger_data: Dict[str, Any]) -> str:
    """Build an unsigned legacy QR URL (backward compatibility)."""
    params = {k: str(v) for k, v in charger_data.items() if v is not None}
    query = urllib.parse.urlencode(params)
    return f"evrouter://charge?{query}"


def generate_charger_qr(charger_data: Dict[str, Any]) -> str:
    """Generate a signed QR code for *charger_data* as a base64-encoded PNG.

    Tries the ``qrcode`` library; falls back to a base64-encoded placeholder
    string if the library is not installed.

    Returns:
        A base64-encoded PNG string (without the ``data:image/png;base64,`` prefix),
        or a plain base64-encoded QR string if the library is unavailable.
    """
    qr_string = sign_qr_data(charger_data)

    try:
        import io

        import qrcode  # type: ignore
        import qrcode.image.pil  # type: ignore

        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_string)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")

        buffer = io.BytesIO()
        img.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode()
    except ImportError:
        logger.info("qrcode library not installed — returning base64-encoded QR string as fallback")
        return base64.b64encode(qr_string.encode()).decode()
    except Exception as exc:
        logger.error("QR PNG generation failed: %s — returning base64 string fallback", exc)
        return base64.b64encode(qr_string.encode()).decode()
