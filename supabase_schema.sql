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

-- Insert standard campus stops with verified satellite coordinates
INSERT INTO public.stops (name, lat, lng) VALUES
    ('Q-Block / P&N Block Cluster', 12.973810, 79.164065),
    ('K & L Block Cluster', 12.972722, 79.161581),
    ('DC Cafe & Dining', 12.969718, 79.158588),
    ('Men''s Hostel Office & F/G', 12.972619, 79.159068),
    ('Periyar EVR Central Library', 12.968807, 79.156940),
    ('VIT Main Gate (Gate 1)', 12.968634, 79.156367),
    ('G-Block Ladies'' Hostel', 12.968256, 79.159605),
    ('Ladies'' Hostel near SJT', 12.971659, 79.162310),
    ('SJT (Silver Jubilee Tower)', 12.971847, 79.163585),
    ('PRP Block', 12.972287, 79.166090),
    ('Gandhi Block / East Campus', 12.972703, 79.167738),
    ('S & T Block Cluster', 12.973834, 79.165005),
    ('P & N Block', 12.974397, 79.164205),
    ('M-Block', 12.973066, 79.163866),
    ('F-Block Hostels', 12.973675, 79.158419),
    ('G-Block Hostels', 12.973744, 79.159754);

-- Insert official VIT shuttle routes
INSERT INTO public.routes (route_name, color, points) VALUES
    (
        'Men''s Hostels Express Route (Bus #101)', 
        '#2563eb', 
        '[
            {"lat": 12.968634, "lng": 79.156367},
            {"lat": 12.968807, "lng": 79.156940},
            {"lat": 12.969718, "lng": 79.158588},
            {"lat": 12.972619, "lng": 79.159068},
            {"lat": 12.973675, "lng": 79.158419},
            {"lat": 12.973744, "lng": 79.159754},
            {"lat": 12.972722, "lng": 79.161581},
            {"lat": 12.971847, "lng": 79.163585},
            {"lat": 12.973066, "lng": 79.163866},
            {"lat": 12.973810, "lng": 79.164065},
            {"lat": 12.974397, "lng": 79.164205},
            {"lat": 12.973834, "lng": 79.165005},
            {"lat": 12.972287, "lng": 79.166090},
            {"lat": 12.972703, "lng": 79.167738}
        ]'::jsonb
    ),
    (
        'Women''s Hostel Express Route (Bus #102)', 
        '#ec4899', 
        '[
            {"lat": 12.968256, "lng": 79.159605},
            {"lat": 12.969718, "lng": 79.158588},
            {"lat": 12.968807, "lng": 79.156940},
            {"lat": 12.968634, "lng": 79.156367},
            {"lat": 12.971659, "lng": 79.162310},
            {"lat": 12.971847, "lng": 79.163585}
        ]'::jsonb
    ),
    (
        'Faculty Exclusive Route (Shuttle #201)', 
        '#059669', 
        '[
            {"lat": 12.968634, "lng": 79.156367},
            {"lat": 12.968807, "lng": 79.156940},
            {"lat": 12.969718, "lng": 79.158588},
            {"lat": 12.971659, "lng": 79.162310},
            {"lat": 12.971847, "lng": 79.163585},
            {"lat": 12.972287, "lng": 79.166090},
            {"lat": 12.972703, "lng": 79.167738}
        ]'::jsonb
    );
