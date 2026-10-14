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
    -- Men's Hostels Shuttle Stops
    ('Vajpayee / Q & R-Block Cluster', 12.9723, 79.1627),
    ('L, M, N, P Block Cluster', 12.9712, 79.1612),
    ('MH Food Court & All Maart Area', 12.9701, 79.1601),
    ('GD Naidu Block / A-G Blocks', 12.9692, 79.1588),
    ('TT / Central Library Junction', 12.9691, 79.1560),
    
    -- Women's Hostel Shuttle Stops
    ('Main Ladies'' Hostel (LH) Gate', 12.9675, 79.1595),
    ('LH G Block', 12.9668, 79.1602),
    ('Periyar EVR Central Library', 12.9688, 79.1561),
    ('SMV / MB Block Portico', 12.9698, 79.1552),
    
    -- Faculty Shuttle Stops & Shared Academic Stops
    ('Main Gate 1 Entrance', 12.9682, 79.1542),
    ('Main Gate 2 Entrance', 12.9665, 79.1551),
    ('Dr. M.G.R. Central Admin Block', 12.9688, 79.1550),
    ('Staff & Faculty Quarters Zone', 12.9658, 79.1578),
    ('TT (Technology Tower)', 12.9695, 79.1563),
    ('SJT (Silver Jubilee Tower)', 12.9708, 79.1558),
    ('Gandhi Block / Netaji Block', 12.9715, 79.1548);

-- Insert official VIT shuttle routes
INSERT INTO public.routes (route_name, color, points) VALUES
    (
        'Men''s Hostels Express Route (Bus #101)', 
        '#0284c7', 
        '[
            {"lat": 12.9723, "lng": 79.1627},
            {"lat": 12.9712, "lng": 79.1612},
            {"lat": 12.9701, "lng": 79.1601},
            {"lat": 12.9692, "lng": 79.1588},
            {"lat": 12.9691, "lng": 79.1560},
            {"lat": 12.9708, "lng": 79.1558}
        ]'::jsonb
    ),
    (
        'Women''s Hostel Express Route (Bus #102)', 
        '#ec4899', 
        '[
            {"lat": 12.9675, "lng": 79.1595},
            {"lat": 12.9668, "lng": 79.1602},
            {"lat": 12.9688, "lng": 79.1561},
            {"lat": 12.9698, "lng": 79.1552},
            {"lat": 12.9708, "lng": 79.1558}
        ]'::jsonb
    ),
    (
        'Faculty Exclusive Route (Shuttle #201)', 
        '#059669', 
        '[
            {"lat": 12.9682, "lng": 79.1542},
            {"lat": 12.9665, "lng": 79.1551},
            {"lat": 12.9688, "lng": 79.1550},
            {"lat": 12.9658, "lng": 79.1578},
            {"lat": 12.9695, "lng": 79.1563},
            {"lat": 12.9708, "lng": 79.1558},
            {"lat": 12.9715, "lng": 79.1548}
        ]'::jsonb
    );
