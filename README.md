# Vyra Parental Control Suite (Vyra K & Vyra P)

A high-performance, discreet, and reliable two-application Parental Control & Child Safety suite specially designed for modern Android (Android 14 / Vivo T3 Pro 5G / Funtouch OS 14) and cross-platform monitoring.

---

## Project Structure

```
controll/
├── vyra_k/               # Child Android Engine (Native Kotlin, Android 14 / Vivo T3 Pro 5G)
│   ├── app/
│   │   ├── src/main/java/com/vyra/kids/
│   │   │   ├── core/         # Constants (60FPS/48kHz), PrefsManager, NetworkSyncManager, FirebaseSyncManager, DisguiseManager
│   │   │   ├── services/     # Accessibility (Anti-Tamper), CallRecordingSync, NotificationListener, SMS, 60FPS WebRTC, VoiceIntercomPlayerService
│   │   │   ├── receivers/    # DeviceAdmin (Anti-Uninstall), PackageInstall (New Apps), Boot
│   │   │   ├── workers/      # VaultSyncWorker (Offline Queue & Local Vault Auto-Sync)
│   │   │   └── ui/           # SetupWizard (1-time pairing) & DecoyDisplayActivity (Boring Decoys with PIN unlock)
│   │   └── AndroidManifest.xml
│   ├── build.gradle.kts
│   └── settings.gradle.kts
│
├── vyra_p/               # Parent Dashboard App (Flutter / Material 3 / iOS & Android)
│   ├── lib/
│   │   ├── models/           # ChildProfile, DeviceStatus, ChatMessage, CallRecord, NotificationItem, WatchlistTarget
│   │   ├── providers/        # ParentDashboardProvider (Multi-child state management & Firestore/Render real-time sync)
│   │   ├── screens/          # Dashboard, Chats, Calls, Feed, 60FPS Live Monitor, Watchlist
│   │   ├── widgets/          # VoiceIntercomSheet, ChatBubble, AudioPlayerCard, QuickActionTile
│   │   └── main.dart
│   ├── test/
│   └── pubspec.yaml
│
└── vyra_backend/         # Ultra-HD 60 FPS Signaling Server & Lossless Audio Vault (Node.js + Socket.io)
    ├── server.js         # WebRTC 60 FPS signaling hub, Range-seekable audio streaming & Intercom relay
    ├── Dockerfile        # Container build
    ├── render.yaml       # 1-Click Free Blueprint for Render.com
    └── package.json

```

---

## 🚀 Key Features Implemented

### 1. 🎙️ Parent Voice Intercom (Live Speaker Blast)
- **Push-to-Talk**: Parent holds the mic button in `Vyra P`, speaks directly, and their voice plays out loud through the child's phone loudspeaker via `VoiceIntercomPlayerService`.
- **Quick Voice Presets (1-Tap Blast)**:
  - 📢 *"Beta, phone band karo aur dinner ke liye aao!"*
  - 📚 *"Coaching ka time ho gaya hai, turant niklo."*
  - ⏰ *"Raat ke 10 baj gaye hain, phone table par rakh do."*
  - ⚠️ *"Papa room me aa rahe hain, padhai start karo."*
- **Custom TTS Announcement**: Type any message, and Vyra K announces it through device speaker.

### 2. 👨‍👩‍👧‍👦 Multi-Child Profile Switcher
- Manage multiple siblings (e.g. **Aryan** on Vivo T3 Pro 5G, **Ananya** on Samsung Galaxy M34) in `Vyra P`.
- Seamless 1-tap child switcher bar right at the top of the dashboard.
- Switches real-time device battery, online status, location, logs, chats, and calls cleanly per child.

### 3. 🎭 "Never-Opened" Boring Disguise Suite (`<activity-alias>`)
Instead of a calculator that kids might open for school math homework, Vyra K is disguised as boring system utilities that no child ever touches:
- **Option 1 (Default)**: **SIM Toolkit** (Shows clean *"SIM Services are active and up to date"*)
- **Option 2**: **Device Support** (Shows *"No diagnostic issues found"*)
- **Option 3**: **Digital Compass** (Shows compass heading sensor dial)
- **Option 4**: **System Sync** (Shows *"Sync status: Idle"*)
- **Secret Parent PIN Unlock**: Tapping the corner lock icon and entering Master PIN (`8899`) unlocks the setup wizard and disguise switcher.

### 4. 📞 Vivo Silent Call Recording Sync & Anti-Tamper (Solution A)
- **Automatic Sync**: Watches `/storage/emulated/0/Record/Call` (Vivo native dialer default path).
- **Fast Secret Vault (<50ms)**: Copies audio to `context.filesDir/vault_recordings/` immediately when a call ends. Even if the child deletes the recording from the phone dialer or file manager, the vault copy is safe!
- **Anti-Tamper Logic**: `VyraAccessibilityService` monitors the Vivo in-call dialer (`com.vivo.phone`). If the child attempts to tap "Stop Recording", the service auto-resumes the recording within 300ms and sends a priority tamper alert to the parent.
- **Offline Resilience**: `VaultSyncWorker` queues recordings when internet is off and automatically uploads them the moment Wi-Fi or Mobile Data connects.

### 5. 📺 Live Screen Mirroring & Remote Camera
- **On-Demand Live Stream**: Low-latency WebRTC streaming of the child's screen or camera.
- **Remote Controls**: Switch between Front and Back camera, toggle the device Flashlight/Torch, and stream ambient room audio.
- **In-App Camera Trap**: Automatically captures preview snapshots when Instagram or Snapchat camera/shutter buttons are clicked.

### 6. 💬 Smart Chat & Notification Mirroring (Text-Optimized)
- **Zero Storage Waste**: Chats and notifications are stored as lightweight JSON text instead of screenshots (saving ~99.9% data and battery).
- **Deleted Messages Backup**: Captures WhatsApp, Telegram, and Instagram messages the exact millisecond they hit the notification bar. Preserved even after "Delete for Everyone".
- **SMS Interception**: Real-time incoming (`SMS_RECEIVED`) and outgoing (`ContentObserver`) message logging.

### 7. 🚨 High-Priority Watchlist Targets
- Add specific suspicious phone numbers or social handles to the Watchlist.
- Instant loud alarm/notification whenever the watched contact calls or messages the child.
- Unified 360° timeline profile for all interactions with that specific person.

---

## 🛠️ Setup Guide for Vivo T3 Pro 5G (Target Device)

1. **Enable Vivo Alternate Phone Dialer**:
   - Go to **Settings -> Apps -> Enable Alternate Phone and Contacts** -> Turn **ON**.
2. **Turn on Silent Auto Call Recording**:
   - Open Phone App -> Top-right 3 dots -> **Call Settings -> Record settings -> Record all calls automatically**.
3. **Install Vyra K & Complete Permissions**:
   - Launch `Vyra K` -> Complete the 4 permission cards:
     1. Accessibility Service (`Device Care Accessibility Service`)
     2. Notification Access (`Device Care Notification Service`)
     3. All Files Access (`MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`)
     4. Device Administrator (`Device Care Security Administrator`)
   - Enter Pairing Code (e.g. `VYRA-8921`) and tap **Complete Setup**.
4. **Funtouch OS 14 Background Keep-Alive**:
   - Go to **Settings -> Battery -> Background power consumption management -> Device Care -> "Allow high background power usage"**.
   - Go to **Settings -> Apps -> Autostart -> Device Care -> "Allow"**.

---

## 💻 Running the Parent Dashboard (Vyra P)

### On Android Phone / Emulator:
```bash
cd vyra_p
flutter pub get
flutter run
```

### On iPhone (via Xcode on Mac):
1. Open the iOS project workspace in Xcode:
   ```bash
   open vyra_p/ios/Runner.xcworkspace
   ```
2. In Xcode:
   - Click on the top-level **Runner** project in the left sidebar.
   - Go to **Signing & Capabilities**.
   - Under **Team**, select your Apple ID (Personal Team - Free).
3. Connect your iPhone via USB / Wi-Fi (or choose an iOS Simulator).
4. Click the **Play / Run ▶** button in Xcode, or run in terminal:
   ```bash
   cd vyra_p
   flutter run -d ios
   ```
5. *(If running on physical iPhone for the first time)*: On your iPhone, go to **Settings -> General -> VPN & Device Management** -> tap your developer account -> tap **Trust**.
 
---

## ☁️ Deploying the Backend on Render (100% Free - No Credit Card)

1. Open **[Render.com](https://dashboard.render.com)** and create a free account (Sign in with GitHub).
2. Click **New +** -> **Blueprint**.
3. Connect your repository: **`ayushbh54/vyra-kp`**.
4. Render will automatically read `vyra_backend/render.yaml` and configure the **Node.js Web Service**.
5. Click **Apply / Deploy**.
6. Within 60 seconds, your free public URL is live: `https://vyra-backend-yei8.onrender.com`.
   - Call Recordings audio uploads will work continuously with zero storage fees.
   - 60 FPS WebRTC Signaling and live Voice Intercom will connect instantly anywhere in the world!
