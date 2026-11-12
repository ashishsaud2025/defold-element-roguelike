# Porting Element Roguelike to Other Platforms

How to ship this game (Defold 1.14.0, `Element Roguelike`) on Windows, macOS, Linux,
Android, iOS and the web. Research notes only — nothing in the codebase has been
changed yet, and nothing below has been tested on device. Where a step needs an
Apple/Google account or a change to the game itself, it is called out as such.

Verified against the official Defold manuals as of Nov 2026 (Defold 1.14.0). The
sources for every platform section are listed at the bottom.

---

## 0. Where this project stands today

Hard facts from the repo, written against what we know works today:

| Property | Value | Consequence |
|---|---|---|
| Engine | Defold **1.14.0** (d295ed4), editor on Windows | Same editor bundles everywhere; the bottleneck is signing/distribution, not compilation |
| Display | 960×640, `[display] width=960, height=640` | Landscape only, 3:2 aspect |
| `high_dpi` | `1` | Retina/HDR screens render at 2× without changing logical size |
| Render | `/main/letterbox.renderc` | World is drawn into the largest centred 960×640 rect; black bars elsewhere; aspect never stretches |
| Textures | nearest filtering (pixel art) | Scales 1:1 crisply; keep `nearest` everywhere, on mobile too |
| Input | Keyboard WASD + mouse aim (`action.x/y`) + LMB/RMB « basic » | **No touch bindings yet — the game cannot be controlled on a phone as-is** |
| Debug build | `TUNING.DEBUG = true` (dev keys 1-5, 6-0, `[`/`]`, F1, O/P/L/K, etc.) | **Must be false / removed before any release build**; the rebindable `k_*` ids do *not* activate those keys (they are only for the settings rebind system) |
| Smoke gate | `tools/run_smoke_test.py` + HUD harness | Stays green only if game flow changes stay minimal |
| Sprite budget | `max_count = 2048`, `collection.max_instances = 4096` | Comfortably fine for mobile GPUs |
| No native extensions | no AndroidX/CocoaPods/Gradle deps | Bundling needs **no** network connection and **no** Java/SDK/Xcode for the app build itself |
| No automated signing | — | Release bundles must be signed by you (Android keystore / Apple cert) |

**The two things that must change in the game before ANY release** (see §6):

1. Touch support for the actual gameplay loop (feed/aim — right now basic fire is a
   tap, but *aiming* relies on pointer position and the settings LMB↔RMB toggle, and
   there is no equivalent of `basic_rmb` on a phone).
2. `TUNING.DEBUG = false` (or strip the debug row entirely) — and re-run the suite.

Everything else is packaging work.

---

## 1. TL;DR

| Platform | Build where | Toolchain needed | Effort for this game |
|---|---|---|---|
| **Windows (`.exe`)** | Windows (this machine) | none extra | trivial |
| **Linux** | any OS | `libopenal1` (+`libffi7` on older distros) on the *target* | trivial |
| **macOS (`.app`)** | any OS | Apple Developer account + a Mac to sign/notarize | medium (signing), needs Mac |
| **Android (`.apk`/`.aab`)** | any OS | JDK only if you want `adb`/keytool locally; Defold needs no local SDK/NDK | low (no native extensions) |
| **iOS (`.ipa`)** | **macOS only** | Apple Developer Program, Xcode, signing identity + provisioning profile | medium |
| **HTML5** | any OS | any static file host + HTTP server for testing | low |
| **Consoles** (Switch/PS4/Xbox) | approved partner hardware | NDA, separate SDK by Sony/Microsoft/Nintendo, and Defold console support is gated | not viable without you being an approved partner |

Defold cross-compiles for every target above from one editor; only **iOS requires the
Mac** (Apple's rule, not Defold's), and only **macOS distribution requires a Mac** for
signing/notarization.

---

## 2. Universal pipeline (every target)

### 2.1 Editor bundling — one menu entry per platform

`Project ▸ Bundle… ▸ <Platform> Application…` → choose Debug/Release/Headless + bundle
options → pick the output folder. Options for release-vs-debug are documented in
`Bundling an application`; build reports show asset sizes.

### 2.2 Command line (Bob) — for CI / batch builds

The editor uses **Bob** (`bob.jar`) under the hood; any platform's bundle can be
scripted. Target names from `bob --help`:

```
x86_64-macos   x86_64-win32      x86_64-linux     arm64-linux
arm64-macos    arm64-ios         armv7/arm64/x86_64-android   wasm-web, wasm_pthread-web
```

Generic CI shape (per target):

```bash
java -jar bob.jar --platform x86_64-win32 --archive --variant release \
  --bundle-output build/win --with-symbols resolve distclean build bundle
```

`--with-symbols` keeps debug symbols (needed for crash symbolication). Android keystore
instead: `--keystore my.keystore --keystore-pass <file.txt> --keystore-alias myAlias`.
iOS: `--identity "Developer ID Application: ..." --mobileprovisioning profile.mobileprovision`.

> Bundling only needs the network if the project has native extensions (ours doesn't),
> but Bob stores its build cache in the project folder; on a clean machine first build
> downloads the engine — that download needs network once.

### 2.3 Build variants

- **Debug** — profiler, hot reload, logging, open TCP services; never ship this.
- **Release** — no profiler, no print(), no record module. `sys.get_engine_info().is_debug` is `false`.
- **Headless** — no graphics/sound; CI/NFR/servers only.

### 2.4 Global prerequisites before any release

1. `TUNING.DEBUG = false` (drop the whole debug row from `game.script` ideally).
2. App icons per platform (§7.1) — sources must be square PNGs; the `.ico`/`.icns`/`.car`
   containers are per-platform.
3. Version bump: `[project] version = 0.1` → next release number; platform-specific
   version codes (Android) / build numbers (iOS) are set separately.
4. A real `game.project` display/icon/title story — done per platform below.

---

## 3. Platform by platform

### 3.1 Windows

**Steps**

1. `Project ▸ Bundle… ▸ Windows Application…`. Nothing else to install.
2. Icon `.ico` (Project settings → `[windows] app_icon`), at least 16, 24, 32, 48, 256 px:
   ```bash
   magick icon_256x256.png -compress None -define icon:auto-resize=256,128,96,64,48,32,24,16 favicon.ico
   ```
3. Release-signing: unlike Android/iOS, Windows has no mandatory signing gate for a
   plain `.exe` (SmartScreen will warn on unpacked binaries — normal; code-signing
   removes the warning — buy an OV/EV certificate, not required).
4. Graphics backend: OpenGL by default; choose Vulkan or DirectX 12 via the application
   manifest (`[graphics] windows = vulkan | directx12`… verify exact key in the editor —
   the manual documents *Graphics (Windows)* in the app manifest).
5. Distribution: zip `ElementRoguelike.exe` + `game.arcd` + `game.arci` + `game.dmanifest`,
   or hand it to Steam/itch.io.

**Pitfalls from the manual**

- AMD Radeon + GUI box nodes transparent in editor but fine in builds — update drivers.
- Intel UHD integrated GPUs older than driver 27.20.100.8280 render broken; require driver update.
- `Access is denied` opening atlases — run editor as administrator.
- Write `[project] write_log_file = 2` (already set) writes a log next to the exe for field reports.

### 3.2 Linux

**Steps**

1. `Project ▸ Bundle… ▸ Linux Application…`. No platform-specific `game.project` fields exist.
2. Test on the *oldest* distro you care about. The bundle itself has no bundled OpenAL —
   installers on targets need: `sudo apt-get install libopenal-dev` (Debian/Ubuntu) or
   Fedora `openal-devel`, and on distros older than Debian 10 / Ubuntu 20.04, `libffi.so.6/7`
   matching `LD_PRELOAD` (`libffi7_3.3-6_amd64.deb` per the manual).
3. Distribution: AppImage (recommended), distro packages, Steam, itch.io. Steam Linux
   runtime is Debian-9-ish — that's why you test on an old box first.

**Pitfalls:** HiDPI rendering of the *editor* (not the game) on 4K → `GDK_SCALE=2` or
`glass.gtk.uiScale` in `Defold/config`. Qtile/i3 users get menu flicker → set `GDK_DISPLAY=1`.

**Verify on device:** run on one real Linux machine (the .arcd loads, `\n` line endings —
issue if you commit built archives with wrong line endings, see HTML5 §3.6 FAQ).

### 3.3 macOS

**Steps**

1. Bundle: `Project ▸ Bundle… ▸ macOS Application…` on **any** OS.
2. Icon: `.icns` — create `game.iconset` folder with `icon_16x16.png`…`icon_512x512@2x.png`,
   then `iconutil -c icns -o game.icns game.iconset`. Reference it in
   `[macos] app_icon = /path/to/game.icns`.
3. Zip & publish: Apple requires notarization for any download outside the App Store:

   ```bash
   chmod +x Game.app/Contents/MacOS/Game
   # entitlements (minimal, un-signed-jit + unsigned-memory) in entitlements.plist
   codesign --force --sign "Developer ID Application: Company Name" \
     --options runtime --deep --timestamp \
     --entitlements entitlements.plist Game.app
   xcrun altool --notarize-app --primary-bundle-id "com.you.roguelike" \
     --username "AC_USERNAME" --password "@keychain:AC_PASSWORD" \
     --asc-provider <ProviderShortname> --file Game.zip
   xcrun altool --notarization-info <RequestUUID> -u "AC_USERNAME"
   xcrun stapler staple "Game.app"
   ```
   Good entitlements (no Steam, no camera/mic): `allow-jit`, `allow-unsigned-executable-memory`,
   `allow-dyld-environment-variables`. Steamworks extension needs `disable-library-validation` too.
4. Mac App Store route: same signing + App Review submission instead of notarization; the
   `game.project` bundle id + version must match the App Store record; icons via `Assets.car`
   like iOS (below). Uncheck R8 etc. — this is App Store vs direct download, either works.

**Reality check:** you need a Mac for steps 3 onwards. Cross-bundling from Windows or Linux
produces the unsigned `.app`; signing/notarization is macOS-only tooling.

### 3.4 Android

The cheapest mobile target for this game. Everything below is `game.project`, no code.

**Bundle & sign costs you nothing extra** (no native extensions):

1. Bundle: `Project ▸ Bundle… ▸ Android Application…`. Choose **AAB** for Google Play (recommended,
   9a9: with Play App Signing you never re-sign — Google signs) or **APK** for everywhere else
   (itch.io, direct).
2. SDK/NDK — you do **not** need them locally: Defold compiles native code in its cloud build
   service. `adb` is only for install/debug (`platform-tools`).
3. Keystore (create once, keep forever):
   ```bash
   keytool -genkey -v -noprompt -dname "CN=You, OU=R, O=Company, L=City, ST=State, C=IN" \
     -keystore element-release.keystore -storepass 5Up3r_53cR3t -alias element_key \
     -keyalg RSA -validity 9125
   ```
   Point `[android] keystore` at the `.keystore` and `[android] keystore_pass` at a `.txt` with the password.
   Leave empty for a debug build. **Losing this keystore means you can never update the app on Play
   again** (unless you use Play App Signing).
4. `game.project` `[android]`: `package` (e.g. `com.example.elementroguelike`, 2+ dot segments),
   `version_code` (integer, bump every upload), `min_sdk_version`, `target_sdk_version`, `app_icon_36`…`app_icon_192`,
   `immersive_mode = 1` (hide status/nav bars — strongly recommended; the HUD is edge-docked on a
   notched phone), `debuggable = 0` for release, `app_category = game` (in the manifest for games).
5. Install & test:
   ```bash
   adb devices                        # with USB debugging enabled
   adb install element.apk            # or: editor's "Install on connected device" tick-box
   ```

**Release-quality extras**

- **R8 shrinking** (Defold 1.14+): `[android] r8_keep_rules = /builtins/manifests/android/dmengine.keep`
  plus extension `.keep` files if any; deletes unused Java/resources. This project has none — the
  default file alone shrinks nothing useful; skip it, revisit only if APK exceeds Play size limits.
- **Download size**: check the *Estimate download size* box in the bundle dialog (bundletool report, e.g. `25.0 MB (arm64-v8a)`) or pass Bob `--download-size-report` in CI to keep an eye on app size.
- **Architecture**: APK/AAB default armv7+arm64; `x86_64-android` only for emulators — not needed.
- **Safe area / cutout**: set `[display] …` + `gui.safe_area_mode` (see §6.2) or use the base
  safe-area APIs; `[android] display_cutout = long/both` extends into the cutout — **leave off** until the HUD is notched-aware.
- **Orientation**: the engine decides at the manifest; the game is 960×640 landscape — disable
  portrait in the manifest (custom `AndroidManifest.xml` replaces built-in — copy it first) or
  `[display] dynamic_orientation = 0` (editor toggle). Verify in the editor — the manual documents
  only the dynamic-orientation flag and no direct orientation control; the concrete orientation
  lives in the (custom) manifest. **VERIFY the exact behavior on your device before release.**
- **R8/Art sanity**: after any manifest merge, run one release build on a real device and read
  the first error — nothing renders silently otherwise.

### 3.5 iOS

**Only from macOS**, and you need Apple's Developer Program ($99/yr) for anything except a
7-day free-profile test app.

1. Enroll → Certificates, Identifiers & Profiles → create a cert + provisioning profile
   (Xcode can do all three if you don't want to do it manually; the manual's free-Apple-ID
   route is fine for one device for a week, and needs the same `embedded.mobileprovision`).
2. Bundle: `Project ▸ Bundle… ▸ iOS Application…`. Set code signing identity + the `.mobileprovision`.
   `Simulator` checkbox builds `arm64_sim-ios` (no signing) for local simulator under Apple Silicon.
   Deployment target ≥ iOS 15.0.
3. Icons: `.car` asset catalog (Xcode project → drop 1024px + legacy sizes → build → copy
   `Assets.car` from DerivedData into the project) **and** the simple `[ios] app_icon_*` PNGs
   (`57…180` px) — everything that an App Store listing needs comes from the `.car`.
4. Launch screen: `.storyboard` from Xcode → copy `LaunchScreen.storyboardc` → `[ios] launch_screen = /path/LaunchScreen.storyboardc`.
   Without it the app launches to a black screen, which App Review dislikes.
5. `[ios] bundle_id` unique string, `version` (build number), `privacy_manifest` (default
   built-in `PrivacyInfo.xcprivacy` — Apple requires it; Defold ships one that covers the engine's
   required-reason APIs — do not delete), `ITSAppUsesNonExemptEncryption = False` in a custom
   Info.plist or the App Store will block the upload every build (the engine's encryption use is
   exempt), and `home_indicator_mode = auto_hide` (`[ios] home_indicator_mode = auto_hide`).
6. Keep `NSLocalNetworkUsageDescription` + Bonjour keys out of release builds unless you need
   them (the built-in non-release manifest has them for hot-reload discovery; keep if present).
7. Upload via Xcode/Transporter → TestFlight → App Store. App Store review takes 1–3 days;
   keep the bundle reproducible for crash symbolication.
8. Install for local dev: `ios-deploy` (`brew install ios-deploy`) or editor's Install tick-box.

**Architecture**: iOS 15+, arm64 only. No bitcode anymore but nothing special to set.

### 3.6 HTML5

1. Bundle: `Project ▸ Bundle… ▸ HTML5 Application…`. Serving rule: `file://` doesn't work —
   serve the bundle over HTTP (e.g. `python -m http.server`); Defold creates one for
   `Project ▸ Build HTML5`.
2. WebGL2 by default (`webgl_version_hint` in `[graphics]`); WebGL1 fallback only if you must —
   note it needs `[shader] exclude_gles_sm100 = 0`.
3. Canvas behaviour on any screen: `[html5] scale_mode` — use **Downscale Fit** (same as this
   game's letterbox: never stretches, never upscales, black bars otherwise). **Not Stretch.**
4. **Audio starts only after a user gesture** (browsers policy) — the game's music plays on
   the title screen after you click START, which *is* a gesture; any sfx triggered from
   `init()` before that will be silently blocked on HTML5. Make sure no critical feedback SFX
   fires before the first click.
5. `.wasm` needs `application/wasm` MIME if you self-host, and use **HTTPS** or localhost; the
   loader retries failed downloads per `html5.retry_count` / `html5.retry_time`. If hosting them
   on a CDN that rewrites sizes, set `html5.verify_downloaded_file_size = 0`.
6. Size: HTML5 has hard expectations (fast load, low memory). This game is small (pixel art,
   OGG/WAV) — still run Build Report and consider `[display] high_dpi = 1` with
   `[html5] max_pixel_ratio = 1.5` to cap super-sampled pixels on 3× phones.
7. Save files ride IndexedDB: `sys.save()` works but there is a write→persist delay; keep
   save files small and don't spam-write.
8. No hot reload, no debug overlays, no profiler on shipped HTML5. `print()` compiles out fine.
9. Tester's trap: **wrong line endings from Windows ↔ Linux git will corrupt `.wasm`/`.arcd`**
   and you'll get `Unexpected data size` crashes — check `.gitattributes` if this happens.
10. Distribution: itch.io, CrazyGames, Poki, GameMonetize — each web portal documents its own
    SDK; porting to a portal SDK is out of scope of this doc.

### 3.7 Consoles

Not reachable without being an approved Sony/Microsoft/Nintendo partner (NDA, dev kits,
per-platform extensions). Defold does support Switch (Vulkan backend), PS4/5 and Xbox — sign the
NDA first. Xbox is ultimately handled through GDK. Not a same-quarter activity; ignore for now.

---

## 4. Per-platform shipping matrix

| Item | Win | mac | Linux | Android | iOS | HTML5 |
|---|---|---|---|---|---|---|
| Needs Mac? | no | no (tool) / yes (sign) | no | no | **yes** | no |
| Signing required? | no | yes (notarize) | no | yes (keystore) | yes (cert+profile) | no |
| Store fee | none | $99/yr | none | $25 once | $99/yr | none |
| Store review | none (Steam optional) | optional | optional | Play review | review (1–3 days) | none |
| App icon | `.ico` | `.icns` | `.png` | 36…192 px | Assets.car + pngs | splash = `index.html` CSS |
| Build time (this repo) | ~1 min | ~1 min | ~1 min | ~1–2 min (cloud) | ~1–2 min (cloud) | ~2 min |

---

## 5. What is expected to *just work* the moment you bundle

Because this game is **pure Defold** (Lua, engine resources, one render script, no native
extensions, no networking), these things carry over to every platform for free:

- All existing visuals, particles, shaders, fonts (Cascadia Code OTF is licensed for redistribution per `OFL.txt` in assets/fonts).
- `sys.save`/`sys.load` anywhere including HTML5/IndexedDB.
- `sys.get_save_file(app_id, name)` for per-platform paths.
- The input rebind engine, `self.bind`/`bind_hash` — but read §6.3.
- The 960×640 world with the letterbox render script — black bars instead of stretch, any resolution, any Hz.
- The `[sound]` config (linear gain, 64 voices) — same everywhere (audio cuts out identically).

---

## 6. What does NOT just work — this game's actual porting cost

### 6.1 Touch is the blocker. The whole control scheme is mouse.

Current bindings (`input/game.input_binding`): WASD, `MOUSE_BUTTON_1 → basic`,
`MOUSE_BUTTON_2 → basic_rmb` (used only when the user flips the Settings basic to RMB),
plus Q/R/E/Space etc.

On touch:

- `MOUSE_BUTTON_1` doubles as a **single tap** — so basic fire already works as a tap.
- Movement/aim events arrive with `action_id == nil` and positions; `action.source` tells you
  `mouse` vs `touch`. The aim works from touches **only if** the game continuously receives
  movement events — a finger that is still gets no events. So holding still and shooting where
  you last touched works; aiming by dragging works.
- `MOUSE_BUTTON_2` is **unreachable on touch** → the Settings LMB↔RMB toggle is a dead end on
  a phone; force `basic = "basic"` on touch or rebind basic to tap.
- The pause/menu buttons are GUI nodes — `gui.pick_node` works the same for touch.
- **You cannot interact without touch directives.** As a minimum the Android/iOS/HTML5 builds
  need: a tap = fire, a drag/finger-hold = continuous aim (or virtual aim joystick), plus
  multi-touch if you want move-and-fire independently (`touch_trigger → touch_multi`; do NOT
  share the action with MOUSE_BUTTON_1).
- The [Defold-Input](https://defold.com/assets/defoldinput/) asset provides virtual buttons
  and sticks — evaluate before hand-rolling.

Multi-touch must not be assigned the same action id as `MOUSE_BUTTON_1` — it overrides single-touch.

### 6.2 Safe areas & notched screens

The HUD pins its bars/buttons to the window's edges. On a notched phone they sit under the notch.

- `window.get_safe_area()` / `window.get_reserved_areas()` — call on init and on every
  `window.WINDOW_EVENT_RESIZED` (iOS also fires it on rotation even when size doesn't change).
- `[display] gui.safe_area_mode = long|both` in `game.project` decides which opposing insets
  are applied automatically to GUI layout; `none` (default) ignores them.
- Your HUD is hand-authored for 960×640 — the minimal honest fix is a margin constant for the top HUD elements and the corner quit/settings buttons, or `gui.safe_area_mode = both` with the HUD laid out with that in mind.
- `window.get_reserved_areas()` coordinates are bottom-left origin, in window pixels, unaffected by GUI transforms — account for the `to_design()` scaling if you use them for node positions.

### 6.3 Debug build shipped to users

`TUNING.DEBUG = true` right now (`src/core/data.lua` presumably — wherever `TUNING.DEBUG` is
defined). It enables the 1-5/6-0 shape swap, `[`/`]` compound cycling, F1 audit, O/P/L/K audio
audition row. A release build keeps these live until you flip the flag. Flip it, rebuild,
re-run `tools/run_smoke_test.py` and `ART_TEST=1` — the smoke harness tolerates `DEBUG=false`
for the parts it checks (it asserts the debug row works, so expect those specific assertions
to be updated or the flag kept true — check the harness before shipping).

### 6.4 16:9+ screens — arguably the biggest art-res concern

All portrait/tall screens render this game with black bars (letterbox) — correct but wasteful;
on a phone in portrait it is *unplayable tiny*. Either:

- lock to landscape only (manifest/plist + `dynamic_orientation = 0`), or
- design this game for landscape-only from day one of any mobile port (recommended — it is a 960×640 side-view roguelite, not a portrait game).

### 6.5 Fonts / glyph combinations

`assets/fonts/CascadiaCode-*.ttf` (OFL) + a `.font` file with `/builtins/fonts/font.material`.
English UI only — not a risk yet; if localized to Russian/Polish/Japanese, verify glyphs or
swap font files, and set `[ios] localizations` + `[android] configChanges` appropriately.

### 6.6 Audio in the browser / autoplay

Music starts on TITLE after a click (a user gesture) — good. But if you add any banner SFX at
`init()` on HTML5 it will be silently dropped. Keep an eye on it when building the web port.

### 6.7 Save files on consoles

If you ever reach consoles, `sys.save` is per-controller context there; keep the save path behind
one function now so the console swap stays a one-file change.

### 6.8 Performance & battery on mobile

- Fixed 60 Hz is the default; `[display] update_frequency = 60` and `swap_interval = 1` — good.
- 2048 sprites + hundreds of particles is fine; avoid `print()` spam in release.
- Battery: `optimization-battery` manual — no timers at 120 Hz, prefer engine timers; 2D has no light probes. Coarse check first, micro-optimize later.
- `TUNING.DEBUG` also disables R8/d8 benefits on Android (debug Java won't matter — there is none) — still set it false before release.

---

## 7. Release checklists

### 7.1 Assets to produce once

| Artifact | Windows | macOS | Linux | Android | iOS | HTML5 |
|---|---|---|---|---|---|---|
| 1024×1024 master icon | yes | yes | yes | yes | yes | yes |
| `.ico` 16–256px | yes | | | | | |
| `.icns` (all sizes) | | yes | | | | |
| `.car` asset catalog | | | | | yes | |
| 36…192 px icon set | | | | yes | | |
| Launch storyboard | | | | | yes | |
| Splash image (optional) | | | | | | yes |
| Version/build numbers | [project] | [project] | [project] | [android] version_code | [ios] version | [project] |

### 7.2 Order of operations for a v1.0 everywhere

1. Lock orientation landscape; disable dynamic orientation; rebuild and verify on an Android emulator and iOS simulator.
2. Touch controls (§6.1) behind a platform check — `sys.get_sys_info().device_model` or just: if `touch` is detected, show the touch hint layout.
3. Safe area + letterbox margins on the HUD (§6.2).
4. `TUNING.DEBUG = false`; rerun `check_lua`, `ART_TEST=1` smoke, `validate_ui.py`.
5. Per platform: build bundle → smoke test on real hardware → fix first-crash → store it.

### 7.3 Reproducible builds for debugging

- Keep every `.apk`/`.ipa`/`.app`/bundle **with** symbols (`--with-symbols`) and its store id in
  a folder per version. Android R8 symbols = `mapping.txt` **per build** — reuse maps nothing.
- Linux: ship the bundle unmodified (the `game.arcd` is compressed already; recompressing
  breaks size verification on HTML5 and the SHA-1 checks that loaders rely on).

---

## 8. What I could not verify (and how to close it)

1. **Exact `game.project` key spelling for every listed option** — I read them from the manual
   (project-settings); the editor's own settings UI is authoritative. Cross-check each as you set it.
2. **How orientation is actually locked** — the manual documents only `[display] dynamic_orientation`;
   the manifest/plist keys are platform docs, not Defold's. Verify the built `.apk`'s manifest and
   the iOS app's `UISupportedInterfaceOrientations` on-device.
3. **Note/section**: the Windows section says `Graphics (Windows)` in the *application
   manifest* selects OpenGL/Vulkan/DX12 — I could not read the shipping manifest list from here;
   open the editor's manifest editor to see exact options for your 1.14.0 install.
4. **Linux runtime needs** — `libopenal1`, `libffi7` (older distros) are from the manual, but
   your target distro may differ; check `ldd` on the final binary on a clean VM.
5. **Whether the Simulacran sizes hold** — the 2048 sprite / 4096 instance values are fine on
   modern phones but were only ever run at 60 Hz on Windows; nothing about this game has run
   on a phone or tablet at all. No performance claim survives first contact with a real device.
6. **HTML5 audio autoplay** — assumed OK because the game starts music after a click; untested.
7. **Console SDK specifics** — unavailable to me; NDA-gated. Ask your Defold account manager.
8. **R8 resource keep rules** — untested; this project has no Java code, so it shouldn't matter,
   but if you add native extensions, re-audit.
9. **App Store review specifics** (age rating IAP category, export compliance text) — Apple's
   questionnaire is per-account; ask Apple directly or check App Store Connect docs.
10. **iOS/Android notch behavior** — unverified on this build; `window.get_safe_area()` semantics
    are documented but the HUD integration was designed for a 960×640 rectangular window.
11. **`.icns`/`.car`/`.ico` binaries cannot be authored from this Windows sandbox** — you need a Mac
    (or Xcode's `actool` equivalents) / the ImageMagick one-liner above + `iconutil`.
12. **The smoke harness and any debug assets were built for Windows** — they are not part of the
    shipping bundle; verifying them on other platforms is unnecessary and meaningless.

---

## 9. Sources

All links verified reachable Nov 2026:

- Bundling overview — https://defold.com/manuals/bundling/
- Android — https://defold.com/manuals/android/
- iOS — https://defold.com/manuals/ios/
- macOS — https://defold.com/manuals/macos/
- Linux — https://defold.com/manuals/linux/
- Windows — https://defold.com/manuals/windows/
- HTML5 — https://defold.com/manuals/html5/
- Bob (CLI builder, platform list, `--with-symbols`) — https://defold.com/manuals/bob/
- Porting and release guidelines (safe area, input, localization) — https://defold.com/manuals/porting-guidelines/
- Adapting graphics to different screen sizes (GUI adjust/layouts) — https://defold.com/manuals/adapting-graphics-to-screen-size/
- Project settings (all sections) — https://defold.com/manuals/project-settings/
- Input: mouse & touch (single-touch, multi-touch rules, `action.source`) — https://defold.com/manuals/input-mouse-and-touch/
- Build variants — https://defold.com/manuals/android/#build-variants/ (same for all platforms)

Consoles: https://defold.com/manuals/nintendo-switch/ · https://defold.com/manuals/sony-playstation/ · https://defold.com/manuals/microsoft-xbox/
