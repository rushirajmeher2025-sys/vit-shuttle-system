-- ==============================================================================
-- VIT Shuttle Tracking System - Supabase Database Setup Script
-- Paste this entire script into your Supabase Dashboard -> SQL Editor and Run
-- ==============================================================================

-- 1. STOPS TABLE
CREATE TABLE IF NOT EXISTS public.stops (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. ROUTES TABLE
CREATE TABLE IF NOT EXISTS public.routes (
    id SERIAL PRIMARY KEY,
    route_name TEXT NOT NULL,
    color TEXT DEFAULT '#1E88E5',
    points JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. SHUTTLE LOGS TABLE (For 5-minute historical batch logging)
-- Supports both shuttle categories:
--   'general': Bus service for everyone (Fare: Rs 20)
--   'faculty': Exclusive shuttle for faculty only (Fare: Free Rs 0)
CREATE TABLE IF NOT EXISTS public.shuttle_logs (
    id BIGSERIAL PRIMARY KEY,
    shuttle_id TEXT NOT NULL,
    shuttle_type TEXT DEFAULT 'general' CHECK (shuttle_type IN ('general', 'faculty')),
    fare NUMERIC DEFAULT 20.0,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CROWDING REPORTS TABLE (For passenger crowding reports)
CREATE TABLE IF NOT EXISTS public.crowding_reports (
    id BIGSERIAL PRIMARY KEY,
    shuttle_id TEXT NOT NULL,
    level TEXT NOT NULL CHECK (level IN ('Low', 'Moderate', 'Full')),
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE public.stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shuttle_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crowding_reports ENABLE ROW LEVEL SECURITY;

-- Allow public read access to stops & routes
CREATE POLICY "Allow public read access for stops" 
    ON public.stops FOR SELECT USING (true);

CREATE POLICY "Allow public read access for routes" 
    ON public.routes FOR SELECT USING (true);

-- Allow backend and clients to insert/read logs & crowding
CREATE POLICY "Allow all access for shuttle_logs" 
    ON public.shuttle_logs FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Allow all access for crowding_reports" 
    ON public.crowding_reports FOR ALL USING (true) WITH CHECK (true);

-- ==============================================================================
-- INITIAL VIT VELLORE CAMPUS SEED DATA
-- ==============================================================================

-- Clear existing sample data if re-running
DELETE FROM public.stops;
DELETE FROM public.routes;

-- Insert standard campus stops
INSERT INTO public.stops (name, lat, lng) VALUES
    ('Main Gate', 12.9692, 79.1559),
    ('MB (Main Building)', 12.9698, 79.1588),
    ('SJT (Silver Jubilee Tower)', 12.9715, 79.1633),
    ('TT (Technology Tower)', 12.9730, 79.1585),
    ('Men''s Hostel', 12.9750, 79.1610);

-- Insert sample VIT shuttle routes
INSERT INTO public.routes (route_name, color, points) VALUES
    (
        'Main Gate to SJT Express', 
        '#1E88E5', 
        '[
            {"lat": 12.9692, "lng": 79.1559},
            {"lat": 12.9698, "lng": 79.1588},
            {"lat": 12.9708, "lng": 79.1610},
            {"lat": 12.9715, "lng": 79.1633}
        ]'::jsonb
    ),
    (
        'Campus Loop (Hostels - TT - SJT)', 
        '#43A047', 
        '[
            {"lat": 12.9750, "lng": 79.1610},
            {"lat": 12.9730, "lng": 79.1585},
            {"lat": 12.9698, "lng": 79.1588},
            {"lat": 12.9715, "lng": 79.1633}
        ]'::jsonb
    );
