-- Migration: Add voting columns to station_checkins
-- This migration adds upvotes, downvotes, and user_name columns for the community review voting feature

-- Add upvotes column (default 0)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS upvotes INTEGER DEFAULT 0;

-- Add downvotes column (default 0)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS downvotes INTEGER DEFAULT 0;

-- Add user_name column for storing the user's name (will be anonymized when returned)
ALTER TABLE station_checkins 
ADD COLUMN IF NOT EXISTS user_name TEXT;

-- Update the check-in creation trigger or function to populate user_name from users table
-- This is optional - the frontend can also send the name during check-in submission

-- Create index for faster public check-in queries
CREATE INDEX IF NOT EXISTS idx_station_checkins_created_at ON station_checkins(created_at DESC);

-- Create index for station-specific queries
CREATE INDEX IF NOT EXISTS idx_station_checkins_station_id ON station_checkins(station_id);

-- Add comment
COMMENT ON COLUMN station_checkins.upvotes IS 'Number of upvotes from community';
COMMENT ON COLUMN station_checkins.downvotes IS 'Number of downvotes from community';
COMMENT ON COLUMN station_checkins.user_name IS 'User name for display (anonymized on retrieval)';

-- Add RLS policy to allow authenticated users to update vote counts
-- This allows any logged-in user to upvote/downvote any check-in
CREATE POLICY "Authenticated users can update vote counts"
    ON station_checkins FOR UPDATE
    USING (true)
    WITH CHECK (true);

-- Alternative: If you want to restrict to only updating upvotes/downvotes
-- You would need a more complex column-level security or use a function
