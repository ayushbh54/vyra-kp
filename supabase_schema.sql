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

-- 5. Enable Row Level Security (RLS) & Allow Anonymous Access for Pairing
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read/write on devices" ON public.devices FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on chats" ON public.chats FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on calls" ON public.calls FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write on notifications" ON public.notifications FOR ALL USING (true) WITH CHECK (true);
