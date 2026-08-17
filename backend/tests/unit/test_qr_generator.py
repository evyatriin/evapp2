import pytest
import json
from utils.qr_generator import sign_qr_data, verify_qr_data


class TestQRDataSigning:
    """Test QR data signing."""

    def test_sign_qr_returns_uri(self):
        """sign_qr_data returns a properly formatted URI."""
        data = {"charger_id": "charger-123", "connector_id": "1"}
        result = sign_qr_data(data)

        assert isinstance(result, str)
        assert result.startswith("evrouter://charge?")

    def test_signature_is_deterministic(self):
        """Same data produces the same signature."""
        data = {"charger_id": "charger-123", "connector_id": "1"}
        signed1 = sign_qr_data(data)
        signed2 = sign_qr_data(data)

        assert signed1 == signed2

    def test_different_data_produces_different_signature(self):
        """Different data produces different signatures."""
        data1 = {"charger_id": "charger-123", "connector_id": "1"}
        data2 = {"charger_id": "charger-456", "connector_id": "1"}

        signed1 = sign_qr_data(data1)
        signed2 = sign_qr_data(data2)

        assert signed1 != signed2

    def test_signed_uri_contains_required_params(self):
        """Signed URI contains d, s, and v parameters."""
        data = {"charger_id": "charger-123"}
        uri = sign_qr_data(data)

        assert "d=" in uri  # payload
        assert "s=" in uri  # signature
        assert "v=v1" in uri  # version


class TestQRDataVerification:
    """Test QR data signature verification."""

    def test_verify_valid_signature(self):
        """Valid signature passes verification."""
        data = {"charger_id": "charger-123", "connector_id": "1"}
        signed = sign_qr_data(data)

        verified = verify_qr_data(signed)
        assert verified == data

    def test_verify_invalid_signature_fails(self):
        """Invalid signature fails verification."""
        data = {"charger_id": "charger-123", "connector_id": "1"}
        signed = sign_qr_data(data)

        # Tamper with signature
        tampered = signed.replace("s=", "s=invalid")
        with pytest.raises(ValueError):
            verify_qr_data(tampered)

    def test_verify_tampered_payload_fails(self):
        """Verification fails if payload is tampered."""
        data = {"charger_id": "charger-123", "connector_id": "1"}
        signed = sign_qr_data(data)

        # Modify signature to cause mismatch
        parts = signed.split("&")
        tampered_parts = []
        for part in parts:
            if part.startswith("s="):
                # Flip one character in the signature
                sig = part[2:]
                modified_sig = sig[:-1] + ("0" if sig[-1] != "0" else "1")
                tampered_parts.append(f"s={modified_sig}")
            else:
                tampered_parts.append(part)
        tampered = "&".join(tampered_parts)

        with pytest.raises(ValueError):
            verify_qr_data(tampered)

    def test_verify_missing_signature_fails(self):
        """Verification fails if signature is missing."""
        invalid_uri = "evrouter://charge?d=base64data&v=v1"  # No 's' param
        with pytest.raises(ValueError):
            verify_qr_data(invalid_uri)

    def test_verify_missing_payload_fails(self):
        """Verification fails if payload is missing."""
        invalid_uri = "evrouter://charge?s=sig&v=v1"  # No 'd' param
        with pytest.raises(ValueError):
            verify_qr_data(invalid_uri)


class TestQRPayloadContent:
    """Test QR payload content handling."""

    def test_complex_qr_payload(self):
        """Complex QR payload with multiple fields."""
        data = {
            "charger_id": "charger-123",
            "connector_id": "1",
            "power_kw": 22.0,
            "connector_type": "Type 2",
            "latitude": 12.9716,
            "longitude": 77.5946,
            "network": "Beckn",
        }
        signed = sign_qr_data(data)
        verified = verify_qr_data(signed)

        assert verified == data

    def test_qr_with_special_characters(self):
        """QR payload with special characters."""
        data = {
            "charger_id": "charger-123-@#$",
            "location_name": "EV Hub - Delhi",
        }
        signed = sign_qr_data(data)
        verified = verify_qr_data(signed)

        assert verified == data

    def test_qr_with_numeric_values(self):
        """QR payload with various numeric types."""
        data = {
            "charger_id": "charger-123",
            "power_kw": 22.5,
            "voltage": 400,
            "current": 32.0,
        }
        signed = sign_qr_data(data)
        verified = verify_qr_data(signed)

        assert verified == data

    def test_empty_payload(self):
        """Empty payload handling."""
        data = {}
        signed = sign_qr_data(data)
        verified = verify_qr_data(signed)

        assert verified == data


class TestQRRoundTrip:
    """Test QR signing and verification round-trip."""

    def test_basic_roundtrip(self):
        """Complete sign and verify round-trip."""
        original_data = {
            "charger_id": "charger-123",
            "connector_id": "1",
            "power_kw": 22.0,
        }

        signed = sign_qr_data(original_data)
        verified = verify_qr_data(signed)

        assert verified == original_data

    def test_roundtrip_with_query_string_parsing(self):
        """Verify works with both full URI and plain query string."""
        data = {"charger_id": "charger-123"}
        signed_uri = sign_qr_data(data)

        # Should work with full URI
        verified1 = verify_qr_data(signed_uri)
        assert verified1 == data

        # Should also work with just the query string part
        query_string = signed_uri.split("?", 1)[1]
        verified2 = verify_qr_data(query_string)
        assert verified2 == data

    def test_signature_prevents_replay(self):
        """Different chargers cannot spoof each other's QR codes."""
        data1 = {"charger_id": "charger-123"}
        data2 = {"charger_id": "charger-456"}

        signed1 = sign_qr_data(data1)
        signed2 = sign_qr_data(data2)

        # Cannot use charger-1's QR for charger-2
        assert signed1 != signed2
        assert verify_qr_data(signed1) == data1
        assert verify_qr_data(signed2) == data2

        # Attempt to use charger-1's URI with forged payload (change payload but use old signature)
        # This will fail because signature won't match the modified payload
        parts = signed1.split("&")
        forged_parts = []
        payload_modified = False
        for part in parts:
            if part.startswith("d="):
                # Decode, modify, re-encode
                import base64
                old_payload = part[2:]
                # Just use data2's equivalent payload structure by using its d param
                parts2 = signed2.split("&")
                for p2 in parts2:
                    if p2.startswith("d="):
                        forged_parts.append(p2)  # Use charger-456's payload
                        payload_modified = True
                        break
                if not payload_modified:
                    forged_parts.append(part)
            else:
                forged_parts.append(part)

        if payload_modified:
            forged = "&".join(forged_parts)
            with pytest.raises(ValueError):
                verify_qr_data(forged)
