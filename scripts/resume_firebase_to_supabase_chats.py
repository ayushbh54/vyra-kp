#!/usr/bin/env python3
"""
Vyra Parental Control - Resumable Firebase to Supabase Migration
---------------------------------------------------------------
Resumes migration of remaining chat messages from Firebase Firestore into Supabase PostgreSQL,
starting EXACTLY from the last migrated document without re-reading previously synced documents.

Features:
- Cursor-based pagination using Firestore structured queries (startAt)
- Zero duplicate read quota wasted (saves Firebase 50k/day Spark limits)
- Checkpoint persistence in scripts/migration_resume.json
- Merge-on-conflict upserts into Supabase
- Graceful 429 quota handling & OAuth auto-refresh on 401
"""

import os
import sys
import json
import time
import datetime
import subprocess
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

CHILD_DEVICE_ID = "VYRA-13533"
RESUME_FILE = os.path.join(os.path.dirname(__file__), "migration_resume.json")
PAGE_SIZE = 300

def get_last_synced_id_from_supabase():
    url = f"{SUPABASE_URL}/rest/v1/chats?select=id&child_id=eq.{CHILD_DEVICE_ID}&order=id.desc&limit=1"
    cmd = [
        "curl", "-s",
        "-H", f"apikey: {SUPABASE_KEY}",
        "-H", f"Authorization: Bearer {SUPABASE_KEY}",
        url
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        data = json.loads(res.stdout)
        if isinstance(data, list) and len(data) > 0:
            return data[0].get("id")
    except Exception as e:
        print(f"[!] Could not query Supabase for last ID: {e}")
    return None

def load_checkpoint():
    if os.path.exists(RESUME_FILE):
        try:
            with open(RESUME_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("last_id")
        except Exception:
            pass
    return None

def save_checkpoint(last_id, total_migrated_today):
    try:
        with open(RESUME_FILE, "w", encoding="utf-8") as f:
            json.dump({
                "last_id": last_id,
                "total_migrated_today": total_migrated_today,
                "updated_at": datetime.datetime.now().isoformat()
            }, f, indent=2)
    except Exception as e:
        print(f"[!] Could not save checkpoint: {e}")

def query_firestore_runquery(token, last_doc_id=None, limit=300):
    url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}/databases/(default)/documents/chats/{CHILD_DEVICE_ID}:runQuery"
    
    query = {
        "from": [{"collectionId": "messages"}],
        "orderBy": [{"field": {"fieldPath": "__name__"}, "direction": "ASCENDING"}],
        "limit": limit
    }

    if last_doc_id:
        last_ref = f"projects/{FIREBASE_PROJECT}/databases/(default)/documents/chats/{CHILD_DEVICE_ID}/messages/{last_doc_id}"
        query["startAt"] = {
            "values": [{"referenceValue": last_ref}],
            "before": False
        }

    payload = json.dumps({"structuredQuery": query})
    cmd = [
        "curl", "-s", "-X", "POST",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json",
        "-d", payload,
        url
    ]

    for attempt in range(1, 5):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
            if not res.stdout or not res.stdout.strip():
                time.sleep(3)
                continue
            data = json.loads(res.stdout)
            if isinstance(data, dict) and "error" in data:
                err = data["error"]
                code = err.get("code")
                msg = err.get("message", "")
                return None, (code, msg)
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict) and "error" in item:
                        err = item["error"]
                        return None, (err.get("code"), err.get("message", ""))
                docs = []
                for item in data:
                    if isinstance(item, dict) and "document" in item:
                        docs.append(item["document"])
                return docs, None
        except Exception as e:
            time.sleep(3)

    return [], "failed_after_retries"

def main():
    print("=" * 75)
    print("  Vyra Resumable Firebase -> Supabase Migration (Chat Continuation)")
    print(f"  Target Device: {CHILD_DEVICE_ID} | Page Size: {PAGE_SIZE}")
    print("=" * 75)

    token = get_refreshed_firebase_token()
    print("[+] Using authenticated Firebase token.")

    # Determine starting cursor
    cursor_id = load_checkpoint()
    if cursor_id:
        print(f"[+] Loaded saved checkpoint: {cursor_id}")
    else:
        cursor_id = get_last_synced_id_from_supabase()
        if cursor_id:
            print(f"[+] Detected latest synced document in Supabase: {cursor_id}")
        else:
            print("[+] No prior checkpoint found, starting from collection beginning.")

    initial_supabase_chats = count_supabase_table("chats")
    print(f"[+] Current Total Chats in Supabase: {initial_supabase_chats:,}\n")

    total_migrated_session = 0
    batch_num = 1

    consecutive_network_failures = 0

    while True:
        docs, err = query_firestore_runquery(token, last_doc_id=cursor_id, limit=PAGE_SIZE)

        if err:
            if isinstance(err, tuple):
                code, msg = err
                if code == 401:
                    print("\n[!] OAuth token expired. Refreshing token...")
                    token = get_refreshed_firebase_token()
                    time.sleep(1)
                    continue
                elif code == 429:
                    print(f"\n[!] Firebase Spark Daily Read Quota reached (HTTP 429: {msg})")
                    print(f"[+] Progress successfully saved at checkpoint: {cursor_id}")
                    print(f"[+] Total chats migrated in this session: {total_migrated_session:,}")
                    break
                else:
                    print(f"\n[!] Firestore error ({code}): {msg}")
                    break
            else:
                consecutive_network_failures += 1
                if consecutive_network_failures <= 8:
                    wait_s = min(consecutive_network_failures * 5, 30)
                    print(f"\n[!] Network glitch ({err}). Refreshing token and retrying in {wait_s}s... (attempt {consecutive_network_failures}/8)")
                    token = get_refreshed_firebase_token()
                    time.sleep(wait_s)
                    continue
                else:
                    print(f"\n[!] Persistent network issue after 8 retries. Checkpoint safely saved at: {cursor_id}")
                    break

        consecutive_network_failures = 0

        if not docs:
            time.sleep(3)
            verify_docs, _ = query_firestore_runquery(token, last_doc_id=cursor_id, limit=PAGE_SIZE)
            if verify_docs:
                docs = verify_docs
            else:
                print(f"\n🎉 NO MORE UNMIGRATED MESSAGES IN FIRESTORE!")
                print(f"All historical chats for {CHILD_DEVICE_ID} are 100% migrated into Supabase.")
                break

        # Transform and upsert docs
        supa_rows = []
        for d in docs:
            doc_id = d["name"].split("/")[-1]
            p = {k: parse_val(v) for k, v in d.get("fields", {}).items()}
            
            ts = p.get("timestampMs") or p.get("timestamp") or int(time.time() * 1000)
            if isinstance(ts, str):
                try:
                    ts = int(datetime.datetime.fromisoformat(ts.rstrip("Z")).timestamp() * 1000)
                except:
                    ts = int(time.time() * 1000)

            supa_rows.append({
                "id": doc_id,
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

        # Upsert in chunks of 100
        for i in range(0, len(supa_rows), 100):
            upsert_supabase_batch("chats", supa_rows[i:i+100])

        total_migrated_session += len(supa_rows)
        cursor_id = supa_rows[-1]["id"]
        save_checkpoint(cursor_id, total_migrated_session)

        print(f"  Batch #{batch_num}: +{len(supa_rows)} chats synced | Last ID: {cursor_id[:25]}... | Session Total: {total_migrated_session:,}")
        batch_num += 1

        # Small pause between pages to stay well within burst rate limits
        time.sleep(0.3)

    final_supabase_chats = count_supabase_table("chats")
    print("\n" + "=" * 75)
    print("  MIGRATION SUMMARY")
    print("=" * 75)
    print(f"  • Chats Migrated This Session : {total_migrated_session:,}")
    print(f"  • Total Chats Now in Supabase : {final_supabase_chats:,}")
    print(f"  • Last Synced Checkpoint ID   : {cursor_id}")
    print("=" * 75)

if __name__ == "__main__":
    main()
