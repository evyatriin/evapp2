-- Migration: Create saved_chargers table
-- Date: 2025-12-02
-- Description: Creates the saved_chargers table for users to favorite/bookmark charging stations

-- Create saved_chargers table
DROP TABLE IF EXISTS saved_chargers CASCADE;

CREATE TABLE saved_chargers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    station_id UUID NOT NULL REFERENCES charging_stations(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, station_id)
);

-- Create indexes
CREATE INDEX idx_saved_chargers_user_id ON saved_chargers(user_id);
CREATE INDEX idx_saved_chargers_station_id ON saved_chargers(station_id);
CREATE INDEX idx_saved_chargers_created_at ON saved_chargers(created_at DESC);

-- Enable Row Level Security
ALTER TABLE saved_chargers ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own saved chargers"
    ON saved_chargers FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can save chargers"
    ON saved_chargers FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can unsave their own chargers"
    ON saved_chargers FOR DELETE
    USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON saved_chargers TO authenticated;
