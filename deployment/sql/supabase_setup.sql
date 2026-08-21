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
-- Access policy.
--
-- The previous policy here was `FOR ALL USING (true) WITH CHECK (true)`,
-- which grants every holder of the publishable key -- a key designed to be
-- distributed to clients -- read and write access to every row. On a table
-- archiving raw safety events, that is every user's threat data readable by
-- anyone who obtains it.
--
-- Only one thing writes this table: safeher_event_processor.py, server-side,
-- authenticating with the *secret* (service_role) key. That key bypasses RLS
-- entirely, so the archive keeps working with no policy granting access at
-- all. Deny-by-default is therefore free here, and the permissive policy was
-- buying nothing.
--
-- If a client ever needs to read its own events, add a policy scoped to
-- auth.uid() rather than reopening this one.
DROP POLICY IF EXISTS "Allow all operations on events" ON public.events;
DROP POLICY IF EXISTS "Service role writes events" ON public.events;

    -- No USING clause for anon/authenticated: with RLS enabled and no policy
    -- matching them, those roles see nothing, which is the intent.
    CREATE POLICY "Service role writes events" ON public.events
        FOR ALL
        TO service_role
        USING (true)
        WITH CHECK (true);
    