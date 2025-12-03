-- Migration: Create EV News Table
-- Description: Stores AI-curated EV news articles from India
-- Created: 2025-12-03

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ev_news table
CREATE TABLE IF NOT EXISTS ev_news (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    summary TEXT,
    source_url TEXT NOT NULL,
    source_name VARCHAR(100),
    published_at TIMESTAMP WITH TIME ZONE NOT NULL,
    image_url TEXT,
    category VARCHAR(50) CHECK (category IN ('policy', 'vehicles', 'charging', 'industry')),
    is_featured BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_ev_news_published_at ON ev_news(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_ev_news_category ON ev_news(category);
CREATE INDEX IF NOT EXISTS idx_ev_news_featured ON ev_news(is_featured);
CREATE INDEX IF NOT EXISTS idx_ev_news_created_at ON ev_news(created_at DESC);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_ev_news_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ev_news_updated_at
    BEFORE UPDATE ON ev_news
    FOR EACH ROW
    EXECUTE FUNCTION update_ev_news_updated_at();

-- Enable Row Level Security
ALTER TABLE ev_news ENABLE ROW LEVEL SECURITY;

-- Create policy: Anyone can read news
CREATE POLICY "Anyone can read news"
    ON ev_news
    FOR SELECT
    USING (true);

-- Create policy: Only authenticated users can insert (for AI agent)
CREATE POLICY "Authenticated users can insert news"
    ON ev_news
    FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Create policy: Only authenticated users can update
CREATE POLICY "Authenticated users can update news"
    ON ev_news
    FOR UPDATE
    USING (auth.role() = 'authenticated');

-- Grant permissions
GRANT SELECT ON ev_news TO anon;
GRANT ALL ON ev_news TO authenticated;
