-- Migration 015: Add charging detail columns to station_checkins
-- Fixes PGRST204 error when submitting check-ins with battery/cost/slip data

ALTER TABLE station_checkins
    ADD COLUMN IF NOT EXISTS battery_start_percent INTEGER CHECK (battery_start_percent BETWEEN 0 AND 100),
    ADD COLUMN IF NOT EXISTS battery_end_percent   INTEGER CHECK (battery_end_percent   BETWEEN 0 AND 100),
    ADD COLUMN IF NOT EXISTS time_taken_minutes    INTEGER CHECK (time_taken_minutes >= 0),
    ADD COLUMN IF NOT EXISTS cost_paid             NUMERIC(10, 2) CHECK (cost_paid >= 0),
    ADD COLUMN IF NOT EXISTS charging_slip_url     TEXT;

COMMENT ON COLUMN station_checkins.battery_start_percent IS 'SoC % when charging started';
COMMENT ON COLUMN station_checkins.battery_end_percent   IS 'SoC % when charging ended';
COMMENT ON COLUMN station_checkins.time_taken_minutes    IS 'Total charging time in minutes';
COMMENT ON COLUMN station_checkins.cost_paid             IS 'Amount paid for this session (INR)';
COMMENT ON COLUMN station_checkins.charging_slip_url     IS 'Storage URL of the uploaded charging slip image';
