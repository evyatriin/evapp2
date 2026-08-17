# Backend Test Suite

This directory contains automated tests for the EV Router backend, with comprehensive coverage of the Beckn EV charging implementation.

## Test Structure

```
tests/
├── conftest.py          # Shared fixtures and configuration
├── unit/                # Unit tests for individual utilities
│   ├── test_circuit_breaker.py      # Circuit breaker state machine (12 tests)
│   ├── test_idempotency.py          # Idempotency key generation & storage (8 tests)
│   ├── test_qr_generator.py         # QR code signing & verification (16 tests)
│   └── test_session_state_machine.py # Session lifecycle state machine (20 tests)
└── integration/         # Integration tests for full flows
    └── test_beckn_endpoints.py      # Beckn charging API endpoints

## Running Tests

**Run all tests:**
```bash
pytest
```

**Run specific test file:**
```bash
pytest tests/unit/test_qr_generator.py -v
```

**Run with coverage:**
```bash
pytest --cov=utils --cov=routers --cov-report=html
```

**Run only unit tests:**
```bash
pytest tests/unit/ -v
```

**Run only integration tests:**
```bash
pytest tests/integration/ -v
```

## Test Coverage

### Unit Tests (58 tests)

#### Session State Machine (20 tests)
- Valid state transitions (INITIATED → AUTHORIZED → STARTING → CHARGING → STOPPING → COMPLETED)
- Invalid transitions (no backward traversal, terminal states)
- Terminal state detection (COMPLETED, CANCELLED, DISPUTED)
- All states in transition matrix

#### Circuit Breaker (12 tests)
- State transitions (CLOSED → OPEN → HALF_OPEN → CLOSED)
- Failure threshold triggers circuit opening
- Recovery timeout transitions to HALF_OPEN
- Success in HALF_OPEN closes circuit
- Failure in HALF_OPEN reopens circuit
- Per-charger breaker isolation
- Both async and sync function execution

#### Idempotency (8 tests)
- Key generation from user_id, request_key, and body
- Deterministic key generation (same inputs → same key)
- Different inputs produce different keys
- Idempotency response storage and retrieval
- Full retry flow with cached responses

#### QR Generator (16 tests)
- QR code signing with HMAC-SHA256
- Deterministic signatures for same data
- Different data produces different signatures
- QR verification for valid signatures
- Detection of invalid signatures
- Detection of tampered payloads
- Detection of tampered signatures
- Complex payloads with multiple fields
- Special characters in payloads
- Anti-spoofing (different chargers cannot use each other's QR codes)

### Integration Tests

- Beckn API endpoints gating behind feature flag
- Search endpoint with charger discovery
- QR validation endpoint
- Session start/end flow
- Payment confirmation
- Authentication requirements

## Key Test Patterns

### Async Testing
Tests using `asyncio.run()` for async operations in unit tests, and `pytest.mark.asyncio` for integration tests.

### Mocking
- `unittest.mock` for synchronous function mocking
- `AsyncMock` for async function mocking
- `patch` context managers for dependency injection

### Fixture Usage
- `enable_beckn_flag` / `disable_beckn_flag` for feature flag testing
- `auth_headers` for authentication testing
- `sample_charging_session` and `sample_qr_payload` for test data

## Coverage Goals

| Component | Target | Status |
|-----------|--------|--------|
| Session State Machine | 100% | ✓ |
| Circuit Breaker | 100% | ✓ |
| Idempotency | 90%+ | ✓ |
| QR Generator | 95%+ | ✓ |
| Beckn Endpoints | 70%+ | In Progress |
| OCPP Integration | 60%+ | Planned |
| Payment Service | 60%+ | Planned |

## Continuous Integration

Tests run automatically on:
- Pull requests
- Commits to main branch
- Pre-deployment verification

Minimum passing tests required: **95%**

## Adding New Tests

1. Create test file in appropriate directory (`unit/` or `integration/`)
2. Follow naming convention: `test_<module>.py`
3. Use descriptive test names: `test_<scenario>_<expected_outcome>`
4. Add docstrings explaining what's being tested
5. Use fixtures from `conftest.py` for common setup
6. Keep tests focused and independent

Example:
```python
def test_circuit_breaker_opens_after_threshold(self):
    """Circuit breaker transitions to OPEN after 5 consecutive failures."""
    breaker = CircuitBreaker(name="test", failure_threshold=5)
    # ... test implementation ...
    assert breaker.state == CircuitState.OPEN
```
