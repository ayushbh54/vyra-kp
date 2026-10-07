#!/usr/bin/env python3
"""
Vyra Parental Control - Live Incremental Firebase to Supabase Relay
------------------------------------------------------------------
Continuously monitors Firebase Firestore for new incoming data (chats, calls, notifications)
from child devices running older versions of the app, and seamlessly bridges them to Supabase.

Handles:
- HTTP 429 Quota Exceeded with automated wait & exponential backoff
- HTTP 401 Auth Expiry with automatic OAuth token refresh
- Deduplication via Supabase merge-duplicates upserts
- Graceful background execution
"""

import sys
import os
import json
import time
import datetime
import subprocess
import urllib.request
import urllib.parse
import re

from migrate_firebase_to_supabase import (
    SUPABASE_URL,
    SUPABASE_KEY,
    FIREBASE_PROJECT,
    get_refreshed_firebase_token,
    parse_val,
    upsert_supabase_batch,
    count_supabase_table
)

POLL_INTERVAL_SECONDS = 30
CHILD_DEVICE_ID = "VYRA-13533"

def query_latest_firestore(token, collection_path, limit=50):
    url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}/databases/(default)/documents/{collection_path}?pageSize={limit}"
    cmd = ["curl", "-s", "--compressed", "-H", f"Authorization: Bearer {token}", url]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if not res.stdout:
            return None, "empty_response"
        data = json.loads(res.stdout)
        if "error" in data:
            err = data["error"]
            code = err.get("code")
            msg = err.get("message", "")
            return None, (code, msg)
        return data.get("documents", []), None
    except Exception as e:
        return None, str(e)

def run_relay_loop():
    print("=" * 75)
    print("  Vyra Live Firebase -> Supabase Incremental Relay Service")
    print(f"  Target Device: {CHILD_DEVICE_ID} | Poll Interval: {POLL_INTERVAL_SECONDS}s")
    print("=" * 75)

    token = get_refreshed_firebase_token()
    print("[+] Connected with authenticated Firebase token.\n")

    iteration = 1
    consecutive_429 = 0

    while True:
        timestamp_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp_str}] [Cycle #{iteration}] Checking Firebase for new child data...")

        # 1. Sync Calls
        calls, err = query_latest_firestore(token, f"calls/{CHILD_DEVICE_ID}/records", limit=50)
        if err:
            if isinstance(err, tuple) and err[0] == 401:
                print(" [!] Token expired, refreshing...")
                token = get_refreshed_firebase_token()
            elif isinstance(err, tuple) and err[0] == 429:
                consecutive_429 += 1
                wait_time = min(300, 30 * consecutive_429)
                print(f" [!] Firebase Read Quota reached (HTTP 429). Waiting {wait_time}s for quota window reset...")
                time.sleep(wait_time)
                continue
            else:
                print(f" [!] Notice checking calls: {err}")
        elif calls:
            consecutive_429 = 0
            supa_calls = []
            for c in calls:
                c_id = c["name"].split("/")[-1]
                p = {k: parse_val(v) for k, v in c.get("fields", {}).items()}
                ts = p.get("timestampMs") or p.get("timestamp") or int(time.time() * 1000)
                if isinstance(ts, str):
                    try:
                        ts = int(datetime.datetime.fromisoformat(ts.rstrip("Z")).timestamp() * 1000)
                    except:
                        ts = int(time.time() * 1000)
                supa_calls.append({
                    "id": c_id,
                    "child_id": CHILD_DEVICE_ID,
                    "contact_name": p.get("contactName", "Unknown"),
                    "phone_number": p.get("phoneNumber", ""),
                    "call_type": p.get("callType", "incoming"),
                    "duration_seconds": p.get("durationSeconds", 0),
                    "recording_url": p.get("recordingUrl"),
                    "recording_duration_seconds": p.get("durationSeconds", 0),
                    "is_tamper_attempt_detected": p.get("isTamperAttemptDetected", False),
                    "is_watchlist_target": p.get("isWatchlistTarget", False),
                    "timestamp_ms": ts
                })
            upsert_supabase_batch("calls", supa_calls)

        # 2. Sync Notifications
        notifs, err = query_latest_firestore(token, f"notifications/{CHILD_DEVICE_ID}/items", limit=50)
        if notifs:
            supa_notifs = []
            for n in notifs:
                n_id = n["name"].split("/")[-1]
                p = {k: parse_val(v) for k, v in n.get("fields", {}).items()}
                ts = p.get("timestampMs") or p.get("timestamp") or int(time.time() * 1000)
                if isinstance(ts, str):
                    try:
                        ts = int(datetime.datetime.fromisoformat(ts.rstrip("Z")).timestamp() * 1000)
                    except:
                        ts = int(time.time() * 1000)
                supa_notifs.append({
                    "id": n_id,
                    "child_id": CHILD_DEVICE_ID,
                    "package_name": p.get("packageName", ""),
                    "app_name": p.get("appName", "App"),
                    "title": p.get("title", ""),
                    "text": p.get("text", p.get("message", "")),
                    "is_important": p.get("isImportant", False),
                    "timestamp_ms": ts
                })
            upsert_supabase_batch("notifications", supa_notifs)

        # 3. Sync Chats
        chats, err = query_latest_firestore(token, f"chats/{CHILD_DEVICE_ID}/messages", limit=50)
        if chats:
            supa_chats = []
            for c in chats:
                c_id = c["name"].split("/")[-1]
                p = {k: parse_val(v) for k, v in c.get("fields", {}).items()}
                ts = p.get("timestampMs") or p.get("timestamp") or int(time.time() * 1000)
                if isinstance(ts, str):
                    try:
                        ts = int(datetime.datetime.fromisoformat(ts.rstrip("Z")).timestamp() * 1000)
                    except:
                        ts = int(time.time() * 1000)
                supa_chats.append({
                    "id": c_id,
                    "child_id": CHILD_DEVICE_ID,
                    "app": p.get("app", "WhatsApp"),
                    "sender": p.get("sender", p.get("contactName", "Unknown")),
                    "text": p.get("text", p.get("messageText", "")),
                    "is_incoming": p.get("isIncoming", True),
                    "is_deleted_by_sender": p.get("isDeletedBySender", p.get("isDeleted", False)),
                    "is_watchlist_target": p.get("isWatchlistTarget", False),
                    "media_url": p.get("mediaUrl", p.get("recordingUrl")),
                    "media_type": p.get("mediaType"),
                    "is_view_once": p.get("isViewOnce", False),
                    "timestamp_ms": ts
                })
            upsert_supabase_batch("chats", supa_chats)
            print(f" -> Cycle #{iteration} complete: Checked and synced latest items to Supabase.")

        iteration += 1
        time.sleep(POLL_INTERVAL_SECONDS)

if __name__ == "__main__":
    run_relay_loop()
