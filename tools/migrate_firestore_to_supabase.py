#!/usr/bin/env python3
"""
Vyra Parental Control - Firestore to Supabase Migration & Offline Backup Tool.
Downloads full historical records (chats, calls, notifications, devices) from
Firebase Firestore and imports them directly into Supabase PostgreSQL.

Usage:
  python3 tools/migrate_firestore_to_supabase.py [--backup-only] [--supabase-url <URL>] [--supabase-key <KEY>]
"""

import sys
import os
import json
import time
import urllib.request
import urllib.error
from datetime import datetime

FIREBASE_PROJECT = "vyra-kp-control-a35ec"
FIREBASE_API_KEY = "AIzaSyChI37d-OGJ-ZfupgruQyBh_d8kVLiJSsU"
CHILD_ID = "VYRA-13533"

def parse_firestore_fields(fields):
    """Recursively converts Firestore REST field format to clean Python dict."""
    result = {}
    if not fields or not isinstance(fields, dict):
        return result

    for key, val in fields.items():
        if "stringValue" in val:
            result[key] = val["stringValue"]
        elif "integerValue" in val:
            result[key] = int(val["integerValue"])
        elif "booleanValue" in val:
            result[key] = val["booleanValue"]
        elif "timestampValue" in val:
            result[key] = val["timestampValue"]
        elif "mapValue" in val:
            result[key] = parse_firestore_fields(val["mapValue"].get("fields", {}))
        elif "arrayValue" in val:
            arr = []
            for item in val["arrayValue"].get("values", []):
                if "stringValue" in item:
                    arr.append(item["stringValue"])
                elif "mapValue" in item:
                    arr.append(parse_firestore_fields(item["mapValue"].get("fields", {})))
            result[key] = arr
        elif "nullValue" in val:
            result[key] = None
        else:
            result[key] = str(val)
    return result

def fetch_firestore_collection(path):
    """Fetches all documents from a Firestore collection via REST API."""
    docs = []
    page_token = None
    base_url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}/databases/(default)/documents/{path}?key={FIREBASE_API_KEY}&pageSize=300"

    print(f"📥 Fetching collection: {path}...")
    while True:
        url = base_url
        if page_token:
            url += f"&pageToken={page_token}"

        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                current_docs = data.get("documents", [])
                for d in current_docs:
                    doc_id = d.get("name", "").split("/")[-1]
                    clean_data = parse_firestore_fields(d.get("fields", {}))
                    clean_data["id"] = doc_id
                    docs.append(clean_data)

                page_token = data.get("nextPageToken")
                if not page_token:
                    break
        except urllib.error.HTTPError as e:
            if e.code == 429:
                print(f"⚠️ Quota limit currently active on Firestore for {path} (HTTP 429). Please run when unblocked.")
            else:
                print(f"❌ Error fetching {path}: HTTP {e.code} - {e.read().decode()}")
            break
        except Exception as e:
            print(f"❌ Unexpected error fetching {path}: {e}")
            break

    print(f"   ✅ Fetched {len(docs)} records from {path}")
    return docs

def post_to_supabase(url, anon_key, table, records):
    """Inserts/upserts records into Supabase PostgREST table."""
    if not records:
        return
    print(f"🚀 Uploading {len(records)} records to Supabase '{table}' table...")
    endpoint = f"{url.rstrip('/')}/rest/v1/{table}"

    # Batch in groups of 50
    batch_size = 50
    for i in range(0, len(records), batch_size):
        batch = records[i:i + batch_size]
        payload = json.dumps(batch).encode("utf-8")
        req = urllib.request.Request(endpoint, data=payload, method="POST")
        req.add_header("apikey", anon_key)
        req.add_header("Authorization", f"Bearer {anon_key}")
        req.add_header("Content-Type", "application/json")
        req.add_header("Prefer", "resolution=merge-duplicates")

        try:
            with urllib.request.urlopen(req) as resp:
                pass
        except urllib.error.HTTPError as e:
            print(f"   ⚠️ Batch error on {table}: HTTP {e.code} - {e.read().decode()}")
        except Exception as e:
            print(f"   ⚠️ Network error uploading to {table}: {e}")

    print(f"   ✅ Finished sync for {table}")

def main():
    print("=" * 70)
    print(" Vyra Parental Control - Data Backup & Supabase Migration Tool")
    print("=" * 70)

    # 1. Fetch from Firestore
    backup_data = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "child_id": CHILD_ID,
        "devices": fetch_firestore_collection("devices"),
        "chats": fetch_firestore_collection(f"chats/{CHILD_ID}/messages"),
        "calls": fetch_firestore_collection(f"calls/{CHILD_ID}/records"),
        "notifications": fetch_firestore_collection(f"notifications/{CHILD_ID}/items"),
    }

    # 2. Save local JSON offline backup
    os.makedirs("backups", exist_ok=True)
    filename = f"backups/firestore_backup_{CHILD_ID}_{int(time.time())}.json"
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(backup_data, f, indent=2, ensure_ascii=False)

    print(f"\n💾 Full Offline Backup Saved to: {filename}")
    total_records = len(backup_data["chats"]) + len(backup_data["calls"]) + len(backup_data["notifications"])
    print(f"📊 Total Records Preserved: {total_records}")

    # 3. Optional Supabase Import
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_KEY")

    if "--supabase-url" in sys.argv:
        idx = sys.argv.index("--supabase-url")
        if idx + 1 < len(sys.argv):
            supabase_url = sys.argv[idx + 1]

    if "--supabase-key" in sys.argv:
        idx = sys.argv.index("--supabase-key")
        if idx + 1 < len(sys.argv):
            supabase_key = sys.argv[idx + 1]

    if supabase_url and supabase_key:
        print(f"\n⚡ Migrating to Supabase at: {supabase_url}")
        # Format chats
        formatted_chats = []
        for c in backup_data["chats"]:
            formatted_chats.append({
                "id": c.get("id"),
                "child_id": CHILD_ID,
                "app": c.get("app", "Social"),
                "sender": c.get("sender", "Unknown"),
                "text": c.get("text", ""),
                "is_incoming": c.get("isIncoming", True),
                "is_deleted_by_sender": c.get("isDeletedBySender", False),
                "is_watchlist_target": c.get("isWatchlistTarget", False),
                "media_url": c.get("mediaUrl"),
                "media_type": c.get("mediaType"),
                "is_view_once": c.get("isViewOnce", False)
            })
        post_to_supabase(supabase_url, supabase_key, "chats", formatted_chats)

        # Format calls
        formatted_calls = []
        for cl in backup_data["calls"]:
            formatted_calls.append({
                "id": cl.get("id"),
                "child_id": CHILD_ID,
                "contact_name": cl.get("contactName", "Unknown"),
                "phone_number": cl.get("phoneNumber", ""),
                "call_type": cl.get("callType", "incoming"),
                "duration_seconds": cl.get("durationSeconds", 0),
                "recording_url": cl.get("recordingUrl"),
                "is_tamper_attempt_detected": cl.get("isTamperAttemptDetected", False)
            })
        post_to_supabase(supabase_url, supabase_key, "calls", formatted_calls)

        # Format notifications
        formatted_notifs = []
        for n in backup_data["notifications"]:
            formatted_notifs.append({
                "id": n.get("id"),
                "child_id": CHILD_ID,
                "package_name": n.get("packageName", ""),
                "app_name": n.get("appName", "App"),
                "title": n.get("title", ""),
                "text": n.get("text", ""),
                "is_important": n.get("isImportant", False)
            })
        post_to_supabase(supabase_url, supabase_key, "notifications", formatted_notifs)

        print("\n✨ Migration to Supabase Completed Successfully!")
    else:
        print("\n💡 Tip: To automatically import this backup into Supabase, run:")
        print(f"   python3 tools/migrate_firestore_to_supabase.py --supabase-url <YOUR_URL> --supabase-key <YOUR_KEY>")

if __name__ == "__main__":
    main()
