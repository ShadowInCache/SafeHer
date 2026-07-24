-- SafeHer Supabase Events Table Schema
-- Run this SQL in Supabase SQL Editor to create the events table


    CREATE TABLE IF NOT EXISTS public.events (
        id BIGSERIAL PRIMARY KEY,
        event_topic TEXT NOT NULL,
        event_data JSONB NOT NULL,
        event_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        threat_level TEXT DEFAULT 'unknown',
        event_type TEXT DEFAULT 'unknown',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
CREATE INDEX IF NOT EXISTS idx_events_topic ON public.events(event_topic);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON public.events(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_threat_level ON public.events(threat_level);
CREATE INDEX IF NOT EXISTS idx_events_type ON public.events(event_type);
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations on events" ON public.events;

    CREATE POLICY "Allow all operations on events" ON public.events
        FOR ALL
        USING (true)
        WITH CHECK (true);
    