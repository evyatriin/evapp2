-- Migration: Create OBD sessions table for cloud-backed telemetry history.
-- Description:
-- 1. Stores per-user OBD session summaries in a dedicated relational table.
-- 2. Enables RLS so users can only read and write their own sessions.
-- 3. Adds indexes to support recent-history and month/year analytics queries.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.obd_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    session_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    device_name TEXT,
    device_id TEXT,
    battery_percent DOUBLE PRECISION,
    soh_percent DOUBLE PRECISION,
    voltage DOUBLE PRECISION,
    battery_power_kw DOUBLE PRECISION,
    temperature_c DOUBLE PRECISION,
    average_speed_kph DOUBLE PRECISION NOT NULL DEFAULT 0,
    peak_speed_kph DOUBLE PRECISION NOT NULL DEFAULT 0,
    trip_distance_km DOUBLE PRECISION NOT NULL DEFAULT 0,
    smooth_driving_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    efficiency_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    harsh_events INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, session_id)
);

CREATE INDEX IF NOT EXISTS obd_sessions_user_updated_idx
ON public.obd_sessions (user_id, session_updated_at DESC);

CREATE INDEX IF NOT EXISTS obd_sessions_user_started_idx
ON public.obd_sessions (user_id, started_at DESC);

CREATE OR REPLACE FUNCTION public.update_obd_sessions_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_obd_sessions_updated_at
ON public.obd_sessions;

CREATE TRIGGER trigger_obd_sessions_updated_at
    BEFORE UPDATE ON public.obd_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_obd_sessions_updated_at();

ALTER TABLE public.obd_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'obd_sessions'
          AND policyname = 'Users can read own obd_sessions'
    ) THEN
        CREATE POLICY "Users can read own obd_sessions"
            ON public.obd_sessions
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'obd_sessions'
          AND policyname = 'Users can insert own obd_sessions'
    ) THEN
        CREATE POLICY "Users can insert own obd_sessions"
            ON public.obd_sessions
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'obd_sessions'
          AND policyname = 'Users can update own obd_sessions'
    ) THEN
        CREATE POLICY "Users can update own obd_sessions"
            ON public.obd_sessions
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'obd_sessions'
          AND policyname = 'Users can delete own obd_sessions'
    ) THEN
        CREATE POLICY "Users can delete own obd_sessions"
            ON public.obd_sessions
            FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.obd_sessions TO authenticated;
