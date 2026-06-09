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
memory/watchdog). Connect the watch by USB and copy the build into its app folder:

```bash
cp watch/bin/PaceTurner.prg "<FENIX8_MOUNT>/GARMIN/APPS/"
```

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
