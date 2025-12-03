# Supabase Setup Guide

## Quick Copy-Paste Instructions

### Step 1: Sign In
You're currently on the Supabase sign-in page. Please sign in with your credentials.

### Step 2: Run Database Migration

1. After signing in, click **SQL Editor** in the left sidebar
2. Click **"New query"**
3. Copy the SQL below and paste it into the editor
4. Click **"Run"** (or press Cmd/Ctrl + Enter)

```sql
-- Migration: Create station_checkins table and add points to profiles
-- Date: 2025-12-02
-- Description: Creates the station_checkins table for user check-ins and adds points column to profiles

-- Create station_checkins table
CREATE TABLE IF NOT EXISTS station_checkins (
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

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_station_checkins_user_id ON station_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_station_checkins_station_id ON station_checkins(station_id);
CREATE INDEX IF NOT EXISTS idx_station_checkins_created_at ON station_checkins(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_station_checkins_status ON station_checkins(status);

-- Add points column to profiles table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'points'
    ) THEN
        ALTER TABLE profiles ADD COLUMN points INTEGER DEFAULT 0 NOT NULL;
    END IF;
END $$;

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add trigger to auto-update updated_at
DROP TRIGGER IF EXISTS update_station_checkins_updated_at ON station_checkins;
CREATE TRIGGER update_station_checkins_updated_at
    BEFORE UPDATE ON station_checkins
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE station_checkins ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view all check-ins
CREATE POLICY "Check-ins are viewable by everyone"
    ON station_checkins FOR SELECT
    USING (true);

-- Users can insert their own check-ins
CREATE POLICY "Users can insert their own check-ins"
    ON station_checkins FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own check-ins
CREATE POLICY "Users can update their own check-ins"
    ON station_checkins FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can delete their own check-ins
CREATE POLICY "Users can delete their own check-ins"
    ON station_checkins FOR DELETE
    USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON station_checkins TO authenticated;
GRANT SELECT ON station_checkins TO anon;
```

### Step 3: Create Storage Bucket

1. Click **Storage** in the left sidebar
2. Click **"New bucket"**
3. Enter bucket name: `checkin-images`
4. Toggle **"Public bucket"** to ON
5. Click **"Create bucket"**

---

## What This Does

✅ Creates `station_checkins` table for user check-ins
✅ Adds `points` column to `profiles` table for rewards
✅ Sets up indexes for fast queries
✅ Configures Row Level Security policies
✅ Creates storage bucket for check-in images

---

**Once you've completed these steps, let me know and I can verify the setup!**
