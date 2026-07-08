# HearBeats

Listen to your heartbeat. The Apple Watch streams your live heart rate to the iPhone, which plays a synthesized stethoscope "lub-dub" at exactly that rate. A demo mode lets you hear it without a watch.

## Quick start (Xcode project included)

The repo includes a generated `HearBeats.xcodeproj` (via [XcodeGen](https://github.com/yonaskolb/XcodeGen)). To regenerate after editing `project.yml`:

```bash
brew install xcodegen   # once
xcodegen generate
```

**Requirements:** Xcode 16+, watchOS simulator runtime (for the full watch+iPhone build). Install via Xcode → Settings → Platforms, or:

```bash
xcodebuild -downloadPlatform watchOS
```

### Run demo mode (no watch)

```bash
chmod +x scripts/run-ios-demo.sh
./scripts/run-ios-demo.sh
```

Or in Xcode: open `HearBeats.xcodeproj`, select the **HearBeats** scheme, run on an iPhone simulator. Switch source to **Demo**, drag the slider, press **Listen**.

### Run live from Apple Watch

1. Open `HearBeats.xcodeproj`, pick your Team under Signing for both targets.
2. Run **HearBeats Watch App** on a paired Apple Watch (simulator or device).
3. On the watch: allow Health access, tap **Start**.
4. Run **HearBeats** on your iPhone. Keep source on **Watch**, then press **Listen**.

## How it works

- **Watch app** runs a HealthKit workout session (heart rate updates every ~2–5 s) and sends each reading to the phone via WatchConnectivity. The workout is discarded, not saved to Health.
- **iPhone app** synthesizes the lub-dub in code (`AVAudioEngine`, no audio files) — each beat is one sample-accurate buffer, so tempo follows your heart rate seamlessly.

## Manual Xcode setup (legacy)

If you prefer creating the project yourself instead of using the included `.xcodeproj`:

1. **Create the project**
   - Xcode → File → New → Project → **watchOS** tab → **App** → Next.
   - Product Name: `HearBeats`. Check **"Watch App with New Companion iOS App"**. Interface: SwiftUI. Finish, and save it anywhere *except* inside this folder.
   - This creates two targets: `HearBeats` (iOS) and `HearBeats Watch App`.

2. **Replace the source files**
   - Delete the template `ContentView.swift` and `*App.swift` from both targets (Move to Trash).
   - Drag the four files from this folder's `HearBeats/` into the Xcode **HearBeats** group. In the dialog, check target **HearBeats** only.
   - Drag the three files from `HearBeats Watch App/` into the **HearBeats Watch App** group. Check target **HearBeats Watch App** only.

3. **Watch target — HealthKit**
   - Select the `HearBeats Watch App` target → Signing & Capabilities → **+ Capability → HealthKit**.
   - Target → Info tab, add two keys:
     - `Privacy - Health Share Usage Description` → `HearBeats reads your heart rate to play it as sound.`
     - `Privacy - Health Update Usage Description` → `HearBeats runs a workout session to measure your live heart rate.`

4. **iPhone target — background audio** (optional but recommended)
   - Select the `HearBeats` (iOS) target → Signing & Capabilities → **+ Capability → Background Modes** → check **Audio, AirPlay, and Picture in Picture**. Lets playback continue with the screen locked.

5. **Signing**
   - In both targets' Signing & Capabilities, pick your Team (a free Apple ID works for personal devices).

## Running it

**Demo first (no watch needed):** select the `HearBeats` iOS scheme, run on your iPhone (or simulator), switch the source to **Demo**, drag the slider, press **Listen**.

**Live from the watch:**
1. Run the `HearBeats Watch App` scheme on your paired Apple Watch (first install can take a while).
2. On the watch, allow the Health permission prompt, then tap **Start**.
3. Run the iOS scheme on your iPhone, keep source on **Watch** — the BPM appears within a few seconds. Press **Listen**.

## Troubleshooting

- **"--" on the phone**: make sure the watch app says "iPhone connected" and monitoring is started; both apps must be in the foreground the first time.
- **No Health prompt on watch**: check Settings → Privacy & Security → Health on the iPhone, or reinstall the watch app.
- **Heart rate is slow to appear**: normal — the sensor takes ~5–15 s to lock on after Start.

## Next up (v2 ideas)

- Match music to the current BPM (MusicKit tempo search, or rate-adjust a local track with `AVAudioUnitTimePitch`).
- Record and replay a heartbeat session.
- Haptic lub-dub on the watch itself.

## Copyright

Copyright © 2026 Christopher Johnson. All rights reserved.
