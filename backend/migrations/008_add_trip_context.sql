-- Migration: Add trip context fields to station_checkins
-- Captures insights from Electric Talks (weather, trip type, passengers, drive mode)
-- Date: 2025-12-29

-- Add weather column (Hot/Rainy/Cold/Normal)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS weather VARCHAR(20);

-- Add trip type column (Highway/City/Mixed)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS trip_type VARCHAR(20);

-- Add passenger count column (1-5+)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS passenger_count INTEGER;

-- Add drive mode column (Eco/Normal/Sport)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS drive_mode VARCHAR(20);

-- Add comments
COMMENT ON COLUMN station_checkins.weather IS 'Weather during trip: Hot, Rainy, Cold, Normal';
COMMENT ON COLUMN station_checkins.trip_type IS 'Type of trip: Highway, City, Mixed';
COMMENT ON COLUMN station_checkins.passenger_count IS 'Number of passengers including driver (1-5+)';
COMMENT ON COLUMN station_checkins.drive_mode IS 'Vehicle drive mode: Eco, Normal, Sport';
