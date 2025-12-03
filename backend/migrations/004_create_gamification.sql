-- Migration: Create Gamification Tables
-- Description: Creates tables for user stats, badges, and leaderboard view
-- Created: 2025-12-03

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Create user_stats table
CREATE TABLE IF NOT EXISTS user_stats (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_points INTEGER DEFAULT 0,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_active_date DATE,
    total_check_ins INTEGER DEFAULT 0,
    total_routes_planned INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create badges table
CREATE TABLE IF NOT EXISTS badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    icon VARCHAR(50),
    requirement_type VARCHAR(50), -- 'check_in', 'route', 'streak'
    requirement_value INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Create user_badges table
CREATE TABLE IF NOT EXISTS user_badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_id UUID REFERENCES badges(id) ON DELETE CASCADE,
    earned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, badge_id)
);

-- 4. Create leaderboard view
CREATE OR REPLACE VIEW weekly_leaderboard AS
SELECT 
    u.id as user_id,
    COALESCE(u.raw_user_meta_data->>'name', 'Anonymous') as name,
    COALESCE(u.raw_user_meta_data->>'profile_image_url', NULL) as profile_image_url,
    COALESCE(us.total_points, 0) as total_points,
    COALESCE(us.current_streak, 0) as current_streak,
    COUNT(DISTINCT ub.badge_id) as badge_count,
    ROW_NUMBER() OVER (ORDER BY COALESCE(us.total_points, 0) DESC) as rank
FROM auth.users u
LEFT JOIN user_stats us ON u.id = us.user_id
LEFT JOIN user_badges ub ON u.id = ub.user_id
GROUP BY u.id, u.raw_user_meta_data, us.total_points, us.current_streak
ORDER BY us.total_points DESC
LIMIT 10;

-- 5. Seed initial badges
INSERT INTO badges (name, description, icon, requirement_type, requirement_value) VALUES
('First Check-in', 'Complete your first charging station check-in', 'check_circle', 'check_in', 1),
('Route Planner', 'Plan 10 routes', 'map', 'route', 10),
('Week Warrior', 'Maintain a 7-day streak', 'local_fire_department', 'streak', 7)
ON CONFLICT DO NOTHING;

-- 6. Create trigger to update updated_at timestamp for user_stats
CREATE OR REPLACE FUNCTION update_user_stats_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_user_stats_updated_at
    BEFORE UPDATE ON user_stats
    FOR EACH ROW
    EXECUTE FUNCTION update_user_stats_updated_at();

-- 7. Enable Row Level Security
ALTER TABLE user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

-- 8. RLS Policies

-- user_stats: Everyone can read (for leaderboard), only owner can update (via API)
CREATE POLICY "Everyone can read user_stats" ON user_stats FOR SELECT USING (true);
-- Note: Updates are handled by backend service role usually, but if client updates:
CREATE POLICY "Users can update own stats" ON user_stats FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own stats" ON user_stats FOR INSERT WITH CHECK (auth.uid() = user_id);

-- badges: Everyone can read
CREATE POLICY "Everyone can read badges" ON badges FOR SELECT USING (true);

-- user_badges: Everyone can read (for profiles), only owner can insert (via API logic)
CREATE POLICY "Everyone can read user_badges" ON user_badges FOR SELECT USING (true);
-- Note: Insertions handled by backend logic

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON user_stats TO authenticated;
GRANT SELECT ON user_stats TO anon;
GRANT SELECT ON badges TO authenticated, anon;
GRANT SELECT, INSERT ON user_badges TO authenticated;
GRANT SELECT ON user_badges TO anon;
GRANT SELECT ON weekly_leaderboard TO authenticated, anon;
