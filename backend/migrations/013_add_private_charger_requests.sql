-- Migration: Add host-listing fields to charging_stations and create charger_requests.
-- Description:
-- 1. Lets users host private/community chargers with rates and availability.
-- 2. Adds a lightweight request workflow for drivers to request a charging slot.
-- 3. Keeps payment manual (UPI/cash) for the fastest launchable MVP.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE public.charging_stations
    ADD COLUMN IF NOT EXISTS host_name TEXT,
    ADD COLUMN IF NOT EXISTS host_phone TEXT,
    ADD COLUMN IF NOT EXISTS host_upi_id TEXT,
    ADD COLUMN IF NOT EXISTS price_per_kwh DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS price_per_session DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS available_from TIME,
    ADD COLUMN IF NOT EXISTS available_to TIME,
    ADD COLUMN IF NOT EXISTS available_days TEXT[] DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS is_accepting_requests BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS parking_notes TEXT,
    ADD COLUMN IF NOT EXISTS house_rules TEXT,
    ADD COLUMN IF NOT EXISTS charger_photos TEXT[] DEFAULT ARRAY[]::TEXT[];

CREATE TABLE IF NOT EXISTS public.charger_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id UUID NOT NULL REFERENCES public.charging_stations(id) ON DELETE CASCADE,
    host_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    requester_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    requester_name TEXT,
    requester_phone TEXT NOT NULL,
    vehicle_name TEXT,
    current_soc INTEGER,
    message TEXT,
    requested_start_at TIMESTAMPTZ NOT NULL,
    requested_end_at TIMESTAMPTZ,
    estimated_amount DOUBLE PRECISION,
    payment_mode TEXT NOT NULL DEFAULT 'manual_upi_or_cash',
    status TEXT NOT NULL DEFAULT 'pending',
    host_response TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT charger_requests_status_check
        CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'completed')),
    CONSTRAINT charger_requests_payment_mode_check
        CHECK (payment_mode IN ('manual_upi_or_cash')),
    CONSTRAINT charger_requests_soc_check
        CHECK (current_soc IS NULL OR (current_soc >= 0 AND current_soc <= 100))
);

CREATE INDEX IF NOT EXISTS charger_requests_host_idx
ON public.charger_requests (host_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS charger_requests_requester_idx
ON public.charger_requests (requester_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS charger_requests_station_idx
ON public.charger_requests (station_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.update_charger_requests_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_charger_requests_updated_at
ON public.charger_requests;

CREATE TRIGGER trigger_charger_requests_updated_at
    BEFORE UPDATE ON public.charger_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.update_charger_requests_updated_at();

ALTER TABLE public.charger_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own charger requests"
ON public.charger_requests;

CREATE POLICY "Users can read own charger requests"
    ON public.charger_requests
    FOR SELECT
    USING (
        auth.uid() = host_user_id
        OR auth.uid() = requester_user_id
    );

DROP POLICY IF EXISTS "Requesters can insert charger requests"
ON public.charger_requests;

CREATE POLICY "Requesters can insert charger requests"
    ON public.charger_requests
    FOR INSERT
    WITH CHECK (auth.uid() = requester_user_id);

DROP POLICY IF EXISTS "Hosts can update charger requests"
ON public.charger_requests;

CREATE POLICY "Hosts can update charger requests"
    ON public.charger_requests
    FOR UPDATE
    USING (auth.uid() = host_user_id)
    WITH CHECK (auth.uid() = host_user_id);

DROP POLICY IF EXISTS "Requesters can cancel charger requests"
ON public.charger_requests;

CREATE POLICY "Requesters can cancel charger requests"
    ON public.charger_requests
    FOR UPDATE
    USING (auth.uid() = requester_user_id)
    WITH CHECK (auth.uid() = requester_user_id);

GRANT SELECT, INSERT, UPDATE ON public.charger_requests TO authenticated;
