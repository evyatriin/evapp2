-- Migration: Change station_id from UUID to TEXT
-- Reason: Stations are identified by Google Places IDs (strings), not UUIDs
-- Date: 2025-12-29

-- Drop the foreign key constraint first (if it exists)
ALTER TABLE station_checkins 
DROP CONSTRAINT IF EXISTS station_checkins_station_id_fkey;

-- Change station_id from UUID to TEXT to support Google Places IDs
ALTER TABLE station_checkins 
ALTER COLUMN station_id TYPE TEXT USING station_id::text;

-- Add comment explaining the change
COMMENT ON COLUMN station_checkins.station_id IS 'Google Places ID of the charging station (text format, e.g., ChIJ...)';
