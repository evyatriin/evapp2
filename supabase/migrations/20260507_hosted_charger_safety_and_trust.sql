-- Migration: Add hosted charger safety, access, declaration, and trust metadata.
-- Description:
-- 1. Keeps private charger onboarding lightweight while storing legal/safety declarations.
-- 2. Supports future trust badges and moderation flags without positioning EVraahein as a public CPO.
-- 3. Adds separate parking photo support for traveller trust.

ALTER TABLE public.charging_stations
    ADD COLUMN IF NOT EXISTS property_type TEXT,
    ADD COLUMN IF NOT EXISTS visitor_access_type TEXT,
    ADD COLUMN IF NOT EXISTS available_hours TEXT,
    ADD COLUMN IF NOT EXISTS vehicle_size_support TEXT[] DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS parking_photos TEXT[] DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS location_access_checks JSONB DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS safety_checks JSONB DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS host_declarations JSONB DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS declaration_version TEXT,
    ADD COLUMN IF NOT EXISTS declarations_completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS moderation_flags TEXT[] DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS verification_badges JSONB DEFAULT '{}'::JSONB;
