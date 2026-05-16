-- Migration 017: Beckn EV Charging Support
-- Run this migration ONLY when BECKN_CHARGING_ENABLED=true is set.
-- All tables are prefixed with no schema changes to existing tables.

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Charger metadata cache ───────────────────────────────────────────────────
-- Stores EV charger details for Beckn search. Synced from chargers table.
CREATE TABLE IF NOT EXISTS charger_metadata (
    charger_id      TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    latitude        DECIMAL(10, 8) NOT NULL,
    longitude       DECIMAL(11, 8) NOT NULL,
    address         TEXT,
    connector_types TEXT[]      DEFAULT '{}',
    power_kw        DECIMAL(8, 2),
    availability_status TEXT    DEFAULT 'Online',
    price_per_kwh   DECIMAL(8, 2) DEFAULT 15.0,
    metadata        JSONB,
    updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_charger_metadata_location
    ON charger_metadata(latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_charger_metadata_availability
    ON charger_metadata(availability_status);

-- ─── Charging sessions ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS charging_sessions (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    charger_id                  TEXT NOT NULL,
    connector_id                TEXT NOT NULL,
    user_id                     UUID NOT NULL,
    vehicle_id                  UUID,
    start_time                  TIMESTAMP NOT NULL,
    end_time                    TIMESTAMP,
    duration_minutes            INTEGER,
    energy_delivered_kwh        DECIMAL(10, 2) DEFAULT 0.0,
    total_cost_inr              DECIMAL(10, 2) DEFAULT 0.0,
    charging_rate_inr_per_kwh   DECIMAL(10, 2) NOT NULL DEFAULT 15.0,
    payment_type                TEXT DEFAULT 'ON_FULFILLMENT',
    state                       TEXT DEFAULT 'initiated',
    idempotency_key             TEXT,
    metadata                    JSONB,
    created_at                  TIMESTAMP DEFAULT NOW(),
    updated_at                  TIMESTAMP DEFAULT NOW(),

    CONSTRAINT chk_session_state CHECK (state IN (
        'initiated', 'authorizing', 'authorized', 'starting', 'charging',
        'stopping', 'metering_final', 'awaiting_payment', 'payment_confirmed',
        'unlocking', 'completed', 'cancelled', 'failed', 'disputed'
    )),
    CONSTRAINT chk_payment_type CHECK (payment_type IN (
        'PRE_FULFILLMENT', 'ON_FULFILLMENT'
    ))
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id     ON charging_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_charger_id  ON charging_sessions(charger_id);
CREATE INDEX IF NOT EXISTS idx_sessions_state       ON charging_sessions(state);
CREATE INDEX IF NOT EXISTS idx_sessions_created_at  ON charging_sessions(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_idempotency
    ON charging_sessions(user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- ─── Meter readings (time-series) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS meter_readings (
    id                          SERIAL PRIMARY KEY,
    session_id                  UUID NOT NULL REFERENCES charging_sessions(id) ON DELETE CASCADE,
    charger_id                  TEXT NOT NULL,
    energy_kwh                  DECIMAL(10, 2),
    cost_so_far_inr             DECIMAL(10, 2),
    charging_rate_inr_per_kwh   DECIMAL(10, 2),
    current_amps                DECIMAL(8, 2),
    voltage_volts               DECIMAL(8, 2),
    power_kw                    DECIMAL(8, 2),
    soc_percent                 DECIMAL(5, 2),
    recorded_at                 TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_meter_session_id    ON meter_readings(session_id);
CREATE INDEX IF NOT EXISTS idx_meter_recorded_at   ON meter_readings(recorded_at DESC);

-- ─── Payment transactions ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id      UUID NOT NULL REFERENCES charging_sessions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL,
    amount_inr      DECIMAL(10, 2) NOT NULL,
    currency        TEXT DEFAULT 'INR',
    payment_method  TEXT NOT NULL DEFAULT 'UPI',
    upi_id          TEXT,
    phone_number    TEXT,
    reference_id    TEXT UNIQUE,
    status          TEXT DEFAULT 'PENDING_COLLECT',
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP,
    notes           TEXT,

    CONSTRAINT chk_payment_status CHECK (status IN (
        'NOT_PAID', 'PENDING_COLLECT', 'COLLECTED', 'FAILED', 'REFUNDED'
    ))
);

CREATE INDEX IF NOT EXISTS idx_payment_session_id  ON payment_transactions(session_id);
CREATE INDEX IF NOT EXISTS idx_payment_user_id     ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_status      ON payment_transactions(status);

-- ─── Reservations (charger holds) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS charger_reservations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    charger_id      TEXT NOT NULL,
    connector_id    TEXT NOT NULL,
    user_id         UUID NOT NULL,
    expires_at      TIMESTAMP NOT NULL,
    cancelled_at    TIMESTAMP,
    converted_to_session_id UUID REFERENCES charging_sessions(id),
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reservations_active
    ON charger_reservations(charger_id, connector_id, expires_at)
    WHERE cancelled_at IS NULL;

-- ─── Beckn transaction audit log ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS beckn_transaction_log (
    id              SERIAL PRIMARY KEY,
    session_id      UUID REFERENCES charging_sessions(id),
    action          TEXT NOT NULL,
    request_context JSONB,
    response_body   JSONB,
    status_code     INTEGER,
    duration_ms     INTEGER,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_beckn_log_session_id ON beckn_transaction_log(session_id);
CREATE INDEX IF NOT EXISTS idx_beckn_log_action     ON beckn_transaction_log(action);

-- ─── Postgres function: atomic session start ──────────────────────────────────
-- Locks the charger row, marks it Charging, inserts the session — all in one transaction.
CREATE OR REPLACE FUNCTION start_charging_session_atomic(
    p_session_id            UUID,
    p_charger_id            TEXT,
    p_connector_id          TEXT,
    p_user_id               UUID,
    p_charging_rate         DECIMAL,
    p_idempotency_key       TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_available BOOLEAN;
BEGIN
    -- Check for existing session with same idempotency key (return early if duplicate)
    IF p_idempotency_key IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM charging_sessions
            WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key
        ) THEN
            SELECT id INTO p_session_id FROM charging_sessions
            WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key
            LIMIT 1;
            RETURN p_session_id;
        END IF;
    END IF;

    -- Lock charger row and check availability
    SELECT availability_status = 'Online' INTO v_available
    FROM charger_metadata
    WHERE charger_id = p_charger_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Charger not found: %', p_charger_id;
    END IF;

    IF NOT v_available THEN
        RAISE EXCEPTION 'Charger not available: %', p_charger_id;
    END IF;

    -- Mark charger as busy
    UPDATE charger_metadata
    SET availability_status = 'Charging', updated_at = NOW()
    WHERE charger_id = p_charger_id;

    -- Insert the session
    INSERT INTO charging_sessions (
        id, charger_id, connector_id, user_id,
        start_time, charging_rate_inr_per_kwh, state, idempotency_key
    ) VALUES (
        p_session_id, p_charger_id, p_connector_id, p_user_id,
        NOW(), p_charging_rate, 'starting', p_idempotency_key
    );

    RETURN p_session_id;
END;
$$ LANGUAGE plpgsql;

-- ─── Postgres function: release charger on session end ────────────────────────
CREATE OR REPLACE FUNCTION release_charger_on_session_end(
    p_session_id UUID,
    p_final_state TEXT DEFAULT 'completed'
) RETURNS VOID AS $$
DECLARE
    v_charger_id TEXT;
BEGIN
    SELECT charger_id INTO v_charger_id
    FROM charging_sessions WHERE id = p_session_id;

    IF FOUND AND v_charger_id IS NOT NULL THEN
        UPDATE charger_metadata
        SET availability_status = 'Online', updated_at = NOW()
        WHERE charger_id = v_charger_id;
    END IF;

    UPDATE charging_sessions
    SET state = p_final_state, end_time = NOW(), updated_at = NOW()
    WHERE id = p_session_id;
END;
$$ LANGUAGE plpgsql;

-- ─── Populate charger_metadata from existing chargers table ───────────────────
-- Run this once after migration to seed initial data.
-- Adjust column names if your chargers table differs.
/*
INSERT INTO charger_metadata (charger_id, name, latitude, longitude, address, connector_types, power_kw, price_per_kwh)
SELECT
    id::text,
    name,
    latitude,
    longitude,
    address,
    connector_types,
    power_kw,
    COALESCE(price_per_kwh, 15.0)
FROM chargers
WHERE status = 'Operational'
ON CONFLICT (charger_id) DO UPDATE
    SET name = EXCLUDED.name,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        updated_at = NOW();
*/
