# Vyra OTA — GitHub Release Rules

Ye rules Vyra child app ke Over-The-Air (OTA) update system ke liye mandatory hain.
Render backend `APK_REDIRECT_URL` ko
`https://github.com/ayushbh54/vyra-kp/releases/latest/download/child-app.apk`
pe point kiya gaya hai — jo automatically latest GitHub Release ka APK serve karta hai.

## RULE 1 — Release Asset Ka Naam HAMESHA `child-app.apk` Rakhna

Jab bhi `gh release create` command run karo, APK file ko `#child-app.apk` alias
se upload KARNA ZAROORI hai:

```bash
# ✅ SAHI — #child-app.apk alias zaroori hai
gh release create v1.0.101 \
  "vyra_k/app/build/outputs/apk/release/app-release.apk#child-app.apk" \
  --title "Vyra v1.0.101" --notes "..."

# ❌ GALAT — alias nahi diya, file naam 'app-release.apk' hoga
gh release create v1.0.101 \
  "vyra_k/app/build/outputs/apk/release/app-release.apk" \
  --title "Vyra v1.0.101"
```

**Kyun:** Render ka `APK_REDIRECT_URL` specifically `/download/child-app.apk` filename
dhundta hai. Agar naam alag hua to 404 aayega aur child app ko update nahi milega.

## RULE 2 — Release Ko Kabhi `--prerelease` Flag Mat Lagana

GitHub ka `/releases/latest/` URL sirf **non-prerelease** releases ko "latest"
maanta hai. Pre-release hone par purana version hi serve hota rahega.

```bash
# ✅ SAHI — koi prerelease flag nahi
gh release create v1.0.101 \
  "vyra_k/app/build/outputs/apk/release/app-release.apk#child-app.apk" \
  --title "Vyra v1.0.101"

# ❌ GALAT — prerelease flag lagaya, /latest/ mein count nahi hoga
gh release create v1.0.101 \
  "vyra_k/app/build/outputs/apk/release/app-release.apk#child-app.apk" \
  --title "Vyra v1.0.101" --prerelease
```

**Kyun:** `--prerelease` se GitHub release create to ho jaayegi lekin
`/releases/latest/` URL purane stable release pe hi point karta rahega.
Child app ko naya update milna band ho jaayega.

## Complete Future Update Workflow (3 Commands Only)

```bash
# Step 1: Release APK build karo
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
  ./gradlew assembleRelease -p vyra_k

# Step 2: GitHub Release create karo (dono rules follow karo)
gh release create vX.X.X \
  "vyra_k/app/build/outputs/apk/release/app-release.apk#child-app.apk" \
  --title "Vyra vX.X.X" \
  --notes "Changes..." \
  --repo ayushbh54/vyra-kp

# Step 3: Render pe KUCHH NAHI karna — done!
# /releases/latest/ automatically naye release pe shift ho jaata hai
```
