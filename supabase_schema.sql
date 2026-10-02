-- ==============================================================================
-- Vyra Parental Control - Supabase PostgreSQL Schema
-- Migration from Firebase Firestore to Supabase Database
-- ==============================================================================

-- 1. Devices Telemetry Table
CREATE TABLE IF NOT EXISTS public.devices (
    id TEXT PRIMARY KEY,
    device_model TEXT DEFAULT 'Android Phone',
    battery_level INTEGER DEFAULT 100,
    is_online BOOLEAN DEFAULT false,
    is_screen_on BOOLEAN DEFAULT false,
    selected_disguise TEXT DEFAULT 'System Toolkit',
    location_address TEXT DEFAULT '',
    last_seen_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Social & SMS Chat Messages (Including Anti-Delete Preserved Chats)
CREATE TABLE IF NOT EXISTS public.chats (
    id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    app TEXT NOT NULL,
    sender TEXT NOT NULL,
    text TEXT NOT NULL,
    is_incoming BOOLEAN DEFAULT true,
    is_deleted_by_sender BOOLEAN DEFAULT false,
    is_watchlist_target BOOLEAN DEFAULT false,
    media_url TEXT,
    media_type TEXT,
    is_view_once BOOLEAN DEFAULT false,
    timestamp_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chats_child_timestamp ON public.chats(child_id, timestamp_ms DESC);

-- 3. Call Records & Anti-Tamper Events
CREATE TABLE IF NOT EXISTS public.calls (
    id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    call_type TEXT DEFAULT 'incoming',
    duration_seconds INTEGER DEFAULT 0,
    recording_url TEXT,
    recording_duration_seconds INTEGER,
    is_tamper_attempt_detected BOOLEAN DEFAULT false,
    is_watchlist_target BOOLEAN DEFAULT false,
    timestamp_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_calls_child_timestamp ON public.calls(child_id, timestamp_ms DESC);

-- 4. Notification Stream
CREATE TABLE IF NOT EXISTS public.notifications (
    id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    package_name TEXT NOT NULL,
    app_name TEXT NOT NULL,
    title TEXT DEFAULT '',
    text TEXT DEFAULT '',
    is_important BOOLEAN DEFAULT false,
    timestamp_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_child_timestamp ON public.notifications(child_id, timestamp_ms DESC);

-- 5. Screen Time Usage
CREATE TABLE IF NOT EXISTS public.screen_time (
    id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    date TEXT NOT NULL,
    total_screen_time_minutes BIGINT DEFAULT 0,
    apps JSONB DEFAULT '[]'::jsonb,
    timestamp_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_screen_time_child_date ON public.screen_time(child_id, date);

-- 6. Remote Commands Queue (Parent to Child)
CREATE TABLE IF NOT EXISTS public.commands (
    id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    action TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,
    status TEXT DEFAULT 'PENDING',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commands_child_status ON public.commands(child_id, status);

-- 7. Enable Row Level Security (RLS) & Allow Anonymous Access for Pairing
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.screen_time ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commands ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read/write on devices" ON public.devices FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on chats" ON public.chats FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on calls" ON public.calls FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on notifications" ON public.notifications FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on screen_time" ON public.screen_time FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on commands" ON public.commands FOR ALL USING (true) WITH CHECK (true);

-- 8. Storage Buckets (for call recordings and snaps)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('recordings', 'recordings', true) 
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public) 
VALUES ('snaps', 'snaps', true) 
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Allow public uploads on recordings" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'recordings');
CREATE POLICY "Allow public reads on recordings" ON storage.objects FOR SELECT USING (bucket_id = 'recordings');
CREATE POLICY "Allow public uploads on snaps" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'snaps');
CREATE POLICY "Allow public reads on snaps" ON storage.objects FOR SELECT USING (bucket_id = 'snaps');

