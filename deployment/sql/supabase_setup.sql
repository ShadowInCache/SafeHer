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
    

-- ============================================================================
-- Evidence bucket (SRS FR-EMG-07)
-- ============================================================================
-- Holds the encrypted audio/video captured during an emergency.
--
-- Created here rather than clicked in the dashboard so that the one property
-- that matters cannot be forgotten on the next deployment: `public => false`.
-- Every object in it is AES-256-GCM ciphertext sealed by `EvidenceStore`
-- before it leaves the application, so a public bucket would leak nothing
-- readable -- but a private one means an attacker needs the service key *and*
-- the encryption key rather than a guessable URL and one of them.

-- The id must match EVIDENCE_BUCKET in .env exactly. Supabase bucket names
-- are CASE-SENSITIVE: 'Evidence' and 'evidence' are two different buckets,
-- and pointing the app at the wrong case fails with NoSuchBucket at the first
-- upload -- which is to say, during someone's emergency.
--
-- `allowed_mime_types` is deliberately restricted to application/octet-stream
-- and NOT to image/audio/video. What lands here is AES-256-GCM ciphertext,
-- which has no media type; encryption erases it. A media-type allow-list
-- could therefore only ever match if the content were *not* encrypted, so
-- restricting to octet-stream turns the list into a guard for the encryption
-- invariant: a future change that stored a plaintext MP4 here would be
-- refused by the storage layer rather than quietly accepted.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('Evidence', 'Evidence', false, 26214400, ARRAY['application/octet-stream'])
ON CONFLICT (id) DO UPDATE
    SET public = false,
        file_size_limit = 26214400,
        allowed_mime_types = ARRAY['application/octet-stream'];

-- Access policy: server-side only.
--
-- Same reasoning as the events table above. The only thing that reads or
-- writes this bucket is the SafeHer API, authenticating with the secret
-- (service_role) key, which bypasses RLS. Retrieval by a user goes through
-- GET /api/v1/media/evidence/{id} -- authenticated, ownership-checked, and
-- streamed -- never through a Supabase URL. No signed URL is ever issued.
--
-- So no policy grants anon or authenticated anything, and with RLS enabled
-- and no matching policy those roles see nothing. That is the intent: a
-- leaked publishable key must not become a directory listing of recordings
-- of people at their most vulnerable.

DROP POLICY IF EXISTS "Service role manages evidence" ON storage.objects;

CREATE POLICY "Service role manages evidence" ON storage.objects
    FOR ALL
    TO service_role
    USING (bucket_id = 'Evidence')
    WITH CHECK (bucket_id = 'Evidence');
