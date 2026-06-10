# Development Setup

How to build PaceTurner. Captures the working toolchain (Linux / Ubuntu 24.04).

## Companion (Flutter)

- Flutter **stable 3.44.x**, Dart 3.x.
- `cd companion && flutter pub get`
- Analyze / test: `flutter analyze` and `flutter test` (strict `analysis_options.yaml`).

## Watch (Connect IQ / Monkey C)

- **Connect IQ SDK 9.1.0**, targets **CIQ API 6.0**, device **`fenix847mm`** (Fenix 8, 47 mm).
- **JDK 17 required** (SDK 9.x will not run on Java 8). A self-contained Temurin 17 lives at
  `~/.local/jdk/jdk-17.0.19+10/`; point `monkeyc` at it via `JAVA_HOME`.
- **Developer key** (4096-bit RSA, generated via the VS Code Monkey C extension): `~/.Garmin/developer_key.der`.
  Never commit it (see `.gitignore`).

### Build the watch app

```bash
export JAVA_HOME=~/.local/jdk/jdk-17.0.19+10
export PATH="$JAVA_HOME/bin:$PATH"
SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b
"$SDK/bin/monkeyc" \
  -f watch/monkey.jungle \
  -d fenix847mm \
  -y ~/.Garmin/developer_key.der \
  -o watch/bin/PaceTurner.prg \
  -l 3            # Strict type-check level (mandatory — see architecture AR4)
```

### Run on hardware (preferred over the simulator)

Per architecture **AR15**, sideload to the real Fenix 8 early (the simulator misreports
memory/watchdog). Verified end-to-end on the Fenix 8 47 mm on 2026-06-10.

**One-time watch setting:** the MTP switch is driven entirely by the watch — the host
cannot trigger it. `091e:0003` is the watch's "Garmin" (vendor protocol) USB mode. On the
watch: hold the middle-left button → **Watch Settings → System → Advanced → USB Mode →
MTP**. (In Garmin mode the watch instead asks per-connection whether to enter MTP, and any
open on-watch dialog blocks the switch.)

In MTP mode the watch enumerates as `091e:51b8` (Fenix 8 AMOLED) and GNOME's gvfs
auto-mounts it — the stock Ubuntu 24.04 `libmtp` 1.1.21 predates the Fenix 8 device IDs
(added in libmtp 1.1.23), so tools may label it "UNKNOWN device", but mounting and
transfers work fine. Sideload:

```bash
# <serial> is the watch's USB serial, e.g. 0000d7710494 — tab-complete the gvfs dir
gio copy watch/bin/PaceTurner.prg \
  "/run/user/$UID/gvfs/mtp:host=091e_51b8_<serial>/Internal Storage/GARMIN/Apps/"
gio mount -u "mtp://091e_51b8_<serial>/"
```

Unplug the watch — it installs sideloaded apps on disconnect; the app then appears in the
activity list. Full diagnosis trail:
`_bmad-output/implementation-artifacts/investigations/fenix8-mtp-sideload-investigation.md`.

> The CIQ GUI tools (SDK Manager, simulator) don't run natively on Ubuntu 24.04 (they need
> 22.04-era libs). The SDK was downloaded by running the official SDK Manager inside an
> Ubuntu 22.04 Docker container (`~/garmin-sdk-docker/Dockerfile`). The CLI compiler runs fine
> on the host with JDK 17, so day-to-day builds need no container.

## Garmin developer verification

**Not required for PaceTurner.** Garmin's developer (trader) verification is driven by the EU
Digital Services Act and applies only to developers who collect payment (paid apps,
subscriptions, tips, donations) for distribution in the EEA. PaceTurner is free and MIT, so it
publishes worldwide without verification. (This supersedes the planning docs' assumption that
verification must be initiated early.)
