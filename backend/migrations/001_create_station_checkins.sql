-- Migration: Create station_checkins table and add points to profiles
-- Date: 2025-12-02
-- Description: Creates the station_checkins table for user check-ins and adds points column to profiles
-- This version handles existing tables gracefully

-- Step 1: Drop and recreate station_checkins table (safer approach)
DROP TABLE IF EXISTS station_checkins CASCADE;

CREATE TABLE station_checkins (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    station_id UUID REFERENCES charging_stations(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('Working', 'Busy', 'Broken')),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 2: Create indexes
CREATE INDEX idx_station_checkins_user_id ON station_checkins(user_id);
CREATE INDEX idx_station_checkins_station_id ON station_checkins(station_id);
CREATE INDEX idx_station_checkins_created_at ON station_checkins(created_at DESC);
CREATE INDEX idx_station_checkins_status ON station_checkins(status);

-- Step 3: Add points column to profiles table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'points'
    ) THEN
        ALTER TABLE profiles ADD COLUMN points INTEGER DEFAULT 0 NOT NULL;
    END IF;
END $$;

-- Step 4: Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Add trigger to auto-update updated_at
CREATE TRIGGER update_station_checkins_updated_at
    BEFORE UPDATE ON station_checkins
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Step 6: Enable Row Level Security
ALTER TABLE station_checkins ENABLE ROW LEVEL SECURITY;

-- Step 7: Create RLS Policies
CREATE POLICY "Check-ins are viewable by everyone"
    ON station_checkins FOR SELECT
    USING (true);

CREATE POLICY "Users can insert their own check-ins"
    ON station_checkins FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own check-ins"
    ON station_checkins FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own check-ins"
    ON station_checkins FOR DELETE
    USING (auth.uid() = user_id);

-- Step 8: Grant permissions
GRANT ALL ON station_checkins TO authenticated;
GRANT SELECT ON station_checkins TO anon;
