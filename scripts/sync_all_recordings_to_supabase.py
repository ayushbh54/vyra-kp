#!/usr/bin/env python3
"""
Sync All Local Device Audio Recordings to Supabase Cloud
- Uploads .m4a files to Supabase Storage bucket 'recordings'
- Inserts call records into Supabase 'calls' table with proper duration, timestamps, and contact names
"""

import os
import sys
import re
import json
import time
import urllib.request
import urllib.parse
import subprocess
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

SUPABASE_URL = "https://wtlqlkkduescumpggttm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0"
CHILD_DEVICE_ID = "VYRA-13533"

def get_audio_duration_seconds(file_path):
    try:
        res = subprocess.run(["afinfo", file_path], capture_output=True, text=True, timeout=5)
        for line in res.stdout.splitlines():
            if "estimated duration:" in line:
                val = line.split(":")[1].replace("sec", "").strip()
                return max(1, int(float(val)))
    except Exception:
        pass
    return 30

def parse_filename_meta(filename, file_path):
    # Pattern 1: Contact YYYY-MM-DD HH-MM-SS.m4a
    m = re.match(r"^(.*?)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}-\d{2}-\d{2})\.m4a$", filename, re.IGNORECASE)
    if m:
        contact = m.group(1).strip()
        date_str = m.group(2)
        time_str = m.group(3).replace("-", ":")
        dt_str = f"{date_str} {time_str}"
        try:
            dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
            ts_ms = int(dt.timestamp() * 1000)
        except Exception:
            ts_ms = int(os.path.getmtime(file_path) * 1000)
        return contact, contact, "recorded", ts_ms

    # Pattern 2: YYYYMMDD_HHMMSS...
    m2 = re.match(r"^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})", filename)
    if m2:
        dt_str = f"{m2.group(1)}-{m2.group(2)}-{m2.group(3)} {m2.group(4)}:{m2.group(5)}:{m2.group(6)}"
        try:
            dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
            ts_ms = int(dt.timestamp() * 1000)
        except Exception:
            ts_ms = int(os.path.getmtime(file_path) * 1000)
        return "Voice Memo (Device)", "Voice Memo", "recorded", ts_ms

    # Fallback: Use file modified time
    ts_ms = int(os.path.getmtime(file_path) * 1000)
    clean_name = os.path.splitext(filename)[0]
    return clean_name, clean_name, "recorded", ts_ms

def upload_file_to_storage(local_path, remote_name):
    try:
        with open(local_path, "rb") as f:
            data = f.read()

        quoted = urllib.parse.quote(remote_name)
        url = f"{SUPABASE_URL}/storage/v1/object/recordings/{quoted}"

        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("apikey", SUPABASE_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_KEY}")
        req.add_header("Content-Type", "audio/mp4")
        req.add_header("x-upsert", "true")

        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status in (200, 201)
    except Exception as e:
        return False

def sync_single_file(file_path):
    fname = os.path.basename(file_path)
    contact, phone, call_type, ts_ms = parse_filename_meta(fname, file_path)
    dur = get_audio_duration_seconds(file_path)

    # 1. Upload to root and child prefix in storage
    up1 = upload_file_to_storage(file_path, fname)
    upload_file_to_storage(file_path, f"{CHILD_DEVICE_ID}/{fname}")

    # 2. Insert into Supabase calls table
    safe_slug = re.sub(r"[^a-zA-Z0-9]", "_", fname[:30])
    call_id = f"call_vivo_{ts_ms}_{safe_slug}"

    is_target = any(k in contact.lower() for k in ["harshit", "manasvi", "aryan"])

    payload = {
        "id": call_id,
        "child_id": CHILD_DEVICE_ID,
        "contact_name": contact,
        "phone_number": phone,
        "call_type": call_type,
        "duration_seconds": dur,
        "recording_url": fname,
        "recording_duration_seconds": dur,
        "is_tamper_attempt_detected": False,
        "is_watchlist_target": is_target,
        "timestamp_ms": ts_ms
    }

    try:
        db_url = f"{SUPABASE_URL}/rest/v1/calls"
        req_db = urllib.request.Request(db_url, data=json.dumps(payload).encode(), method="POST")
        req_db.add_header("apikey", SUPABASE_KEY)
        req_db.add_header("Authorization", f"Bearer {SUPABASE_KEY}")
        req_db.add_header("Content-Type", "application/json")
        req_db.add_header("Prefer", "resolution=merge-duplicates")

        with urllib.request.urlopen(req_db, timeout=15) as resp:
            return True, fname, contact, dur
    except Exception as e:
        return False, fname, str(e), dur

def main():
    base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "backups", "device_recordings")
    files_to_sync = []

    for sub in ["Call", "Record"]:
        p = os.path.join(base_dir, sub)
        if os.path.exists(p):
            for fn in os.listdir(p):
                if fn.lower().endswith((".m4a", ".mp3", ".aac", ".wav", ".amr")):
                    full = os.path.join(p, fn)
                    if os.path.isfile(full) and os.path.getsize(full) > 500:
                        files_to_sync.append(full)

    print(f"[*] Found {len(files_to_sync)} audio recordings to upload & sync.")

    success_count = 0
    fail_count = 0

    with ThreadPoolExecutor(max_workers=6) as executor:
        future_map = {executor.submit(sync_single_file, f): f for f in files_to_sync}
        for future in as_completed(future_map):
            ok, fname, info, dur = future.result()
            if ok:
                success_count += 1
                print(f"[+] [{success_count}/{len(files_to_sync)}] Synced: {fname} ({info}, {dur}s)")
            else:
                fail_count += 1
                print(f"[-] Failed: {fname} -> {info}")

    print("\n" + "=" * 60)
    print(f"[*] Synchronization complete! Total: {success_count} success, {fail_count} failed.")
    print("=" * 60)

if __name__ == "__main__":
    main()
