# Investigation: Fenix 8 never exposes MTP on Ubuntu 24.04 — .prg sideload blocked

## Hand-off Brief

1. **What happened.** The Fenix 8 stayed in Garmin vendor-protocol USB mode (`091e:0003`, class 255) because the MTP switch is driven entirely on the watch (USB Mode setting + on-watch prompt), not by the host — the host was never going to flip it (Confirmed live 2026-06-10).
2. **Where the case stands.** CONCLUDED. Watch-side action flipped the device to `091e:51b8`; gvfs auto-mounted it on stock libmtp 1.1.21; `PaceTurner.prg` (98,524 bytes) copied to `GARMIN/Apps` and the volume unmounted cleanly.
3. **What's needed next.** Nothing for the case. Project-side: un-gate stories 1.3–1.5 (sideload is no longer a blocker).

## Case Info

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| Ticket           | N/A (gates stories 1.3–1.5)                                                 |
| Date opened      | 2026-06-10                                                                  |
| Status           | Concluded — root cause Confirmed live 2026-06-10                            |
| System           | Ubuntu 24.04, kernel 6.8.0-124-generic, libmtp 1.1.21-3.1ubuntu1, gvfs 1.54.4 |
| Evidence sources | Prior-session USB observations, live `lsusb`/`dpkg` inventory, Garmin owner's manual, Garmin forums, libmtp GitHub issues/releases |

## Problem Statement

Fenix 8 47mm connected over USB to this Ubuntu 24.04 box enumerates as `091e:0003` with interface class 255 (Garmin vendor protocol mode) and never flips to MTP. The watch shows an "allow MTP?" prompt but ~~the host never drives the switch~~ (premise refuted — see Deduction 1); libmtp detects nothing; no `GARMIN/` volume mounts, so `.prg` sideload to the real watch is blocked.

## Evidence Inventory

| Source                                   | Status    | Notes                                                            |
| ---------------------------------------- | --------- | ---------------------------------------------------------------- |
| Live `lsusb` with watch connected        | Missing   | Watch not plugged in during this session; prior-session obs only |
| Local MTP stack versions                 | Available | libmtp 1.1.21-3.1ubuntu1, gvfs 1.54.4, kernel 6.8.0-124          |
| Fenix 8 owner's manual (USB Mode)        | Available | Confirms watch-side USB Mode setting under System → Advanced     |
| Garmin forums (Enduro 2/Fenix 7 MTP+Linux) | Available | Confirms switch is watch-side; on-watch prompt blocks detection  |
| libmtp releases + issues #221/#251       | Available | Fenix 8 PIDs 51b8/51b5; absent from 1.1.21; added by 1.1.23      |
| `dmesg` / `journalctl` at plug-in time   | Missing   | Needs watch connected                                            |
| Watch firmware version                   | Missing   | Check on watch: Settings → System → About                        |

## Investigation Backlog

| # | Path to Explore                                                              | Priority | Status  | Notes                                                            |
| - | ---------------------------------------------------------------------------- | -------- | ------- | ---------------------------------------------------------------- |
| 1 | libmtp 1.1.21 device DB: does it contain Fenix 8 PIDs?                       | High     | Done    | No — Fenix 7 IDs landed in 1.1.22; Fenix 8 (51b5) in 1.1.23; 51b8 via issue #251 |
| 2 | What PID does Fenix 8 use in MTP mode, and what drives the 0003→MTP switch? | High     | Done    | `091e:51b8` (AMOLED) / `091e:51b5` (Solar Sapphire); switch is watch-side |
| 3 | Known Fenix 8 + Linux MTP threads                                            | High     | Done    | Enduro 2 thread: dismissing on-watch prompt makes device mount   |
| 4 | Watch-side USB mode/prompt semantics on Fenix 8                              | Medium   | Done    | Garmin mode → per-connection "enter MTP?" prompt; MTP mode → direct |
| 5 | Live re-confirmation: lsusb -v, dmesg, mtp-detect with watch plugged in     | High     | Blocked | Watch not connected this session — the verification step          |
| 6 | Cable/port variable (data vs charge-only)                                   | Low      | Open    | Only if watch-side fix fails                                     |
| 7 | If mount fails post-switch: does gvfs/mtp-probe handle unknown PID 51b8?    | Medium   | Open    | Expect yes (mtp-probe reads descriptors); else libmtp ≥1.1.23 or local ID add |

## Timeline of Events

| Time                  | Event                                                                  | Source              | Confidence |
| --------------------- | ---------------------------------------------------------------------- | ------------------- | ---------- |
| 2023-10               | libmtp 1.1.21 released (no Fenix 7/8 IDs)                              | libmtp releases     | Confirmed  |
| 2024-08               | Fenix 8 launches; MTP PIDs 51b8/51b5 not yet in any libmtp release     | libmtp releases     | Confirmed  |
| 2024-11-20            | libmtp 1.1.22: Fenix 7 family IDs added                                | libmtp releases     | Confirmed  |
| 2024-12-30            | libmtp issue #251: Fenix 8 AMOLED `091e:51b8` "UNKNOWN in v1.1.22"     | github.com/libmtp/libmtp/issues/251 | Confirmed |
| 2025-02-15            | libmtp 1.1.23: "Garmin fenix 8 solar sapphire" (51b5) + many Garmins   | libmtp releases     | Confirmed  |
| ~2026-06 (prior sess.) | Watch enumerated as 091e:0003, class 255; "allow MTP?" prompt; no mount | Prior session       | Confirmed (prior session) |
| 2026-06-10            | Local stack inventoried: libmtp 1.1.21, gvfs 1.54.4, kernel 6.8.0-124 | `dpkg -l`, `uname`  | Confirmed  |

## Confirmed Findings

### Finding 1: Host MTP stack is Ubuntu 24.04 stock — libmtp 1.1.21

**Evidence:** `dpkg -l` 2026-06-10: `libmtp-runtime 1.1.21-3.1ubuntu1`, `gvfs 1.54.4-0ubuntu1~24.04.2`.

**Detail:** 1.1.21 (2023-10) predates the Fenix 8 (2024-08). Fenix 8 MTP PIDs are absent from this host's libmtp device DB.

### Finding 2: Fenix 8 has a watch-side USB Mode setting (MTP vs Garmin)

**Evidence:** Fenix 8 Owner's Manual, Advanced System Settings: "USB Mode — Sets the watch to use MTP (media transfer protocol) or Garmin mode when connected to a computer." Path: hold middle-left button → Watch Settings → System → Advanced → USB Mode.

### Finding 3: In Garmin mode, the watch prompts per-connection to enter MTP

**Evidence:** Garmin support FAQ ("Entering File Transfer Mode when Connected to a Computer"): in Garmin mode the watch asks whether to enter Media Transfer Mode on each computer connection.

**Detail:** This matches the observed "allow MTP?" prompt — the prompt is a *symptom of Garmin mode*, not a broken host handshake.

### Finding 4: The Garmin→MTP switch is driven entirely on the watch

**Evidence:** Garmin forums Enduro 2 thread "MTP with linux": Fenix 7/Enduro 2 on Linux were undetectable while an on-watch dialog ("Start maps download?") was open; "Once I decline the download then the device is detected as an MTP and I can mount it." No host-side action involved.

### Finding 5: Fenix 8 MTP PIDs are `091e:51b8` (AMOLED) and `091e:51b5` (Solar Sapphire)

**Evidence:** libmtp `music-players.h` (master) + issue #251 (51b8, "UNKNOWN in v1.1.22", reported 2024-12-30) + 1.1.23 release notes (51b5 added). Entries carry `DEVICE_FLAGS_ANDROID_BUGS`.

## Deduced Conclusions

### Deduction 1: The host never had a role — the watch's USB Mode kept it in vendor mode

**Based on:** Findings 2, 3, 4 + prior-session observation (`091e:0003`, class 255, persistent).

**Reasoning:** `091e:0003` is Garmin's legacy vendor-protocol PID — exactly what "Garmin mode" presents. The Fenix 8 only enumerates as an MTP device (PID 51b8/51b5) when the watch itself switches: either USB Mode = MTP, or the per-connection prompt is *accepted on the watch* with no other dialog blocking. There is no host-driven mode switch in this protocol; waiting for libmtp/udev to "flip" the watch could never work.

**Conclusion:** Root cause of the blocked sideload is watch-side USB mode state, not the Ubuntu MTP stack. The original premise ("host never drives the switch") is refuted as a fault model — the host *isn't supposed to* drive it.

### Deduction 2: libmtp 1.1.21's missing Fenix 8 entry is a secondary risk, not the blocker

**Based on:** Findings 1, 5; issue #221/#251 pattern.

**Reasoning:** Devices "UNKNOWN in libmtp" (as in issues #221/#251) are still *detected* — mtp-probe identifies MTP capability from USB descriptors, and gvfs mounts unknown MTP devices. The DB entry mainly supplies the display name and quirk flags (`DEVICE_FLAGS_ANDROID_BUGS`). Since the watch never even left vendor mode, libmtp's DB was never reached.

**Conclusion:** After the watch-side fix, mounting will probably work on stock 1.1.21; if transfers misbehave (quirk flags missing), upgrade libmtp to ≥1.1.23 or add the ID locally.

## Hypothesized Paths

### Hypothesis 1: The host never drives the vendor-mode→MTP switch (user's premise as fault model)

**Status:** Refuted

**Theory:** Something on the host should trigger/accept the MTP switch and doesn't.

**Resolution:** Findings 2–4: the switch is watch-side by design (USB Mode setting + on-watch prompt). No host handshake exists to be broken. The observation was accurate; the fault model was not.

### Hypothesis 2: libmtp 1.1.21 lacks Fenix 8 device IDs, so the MTP interface is never claimed

**Status:** Confirmed (fact) / Refuted (as root cause)

**Theory:** Fenix 8 MTP PID unknown to libmtp 1.1.21 → no mount even if the watch switches.

**Resolution:** The IDs are confirmed absent (Finding 5, Timeline). But unknown-ID MTP devices still mount via mtp-probe/gvfs descriptor detection, and the watch never reached MTP mode anyway. Downgraded to secondary risk (Deduction 2). Backlog #7 tracks live verification.

### Hypothesis 3: 091e:0003 vendor mode reflects watch-side USB mode state

**Status:** Confirmed (Deduced — live test pending for formal closure)

**Theory:** The watch presents `091e:0003` because its USB Mode is Garmin (or the MTP prompt was never successfully accepted / was blocked by another dialog).

**Resolution:** Findings 2–4 establish the mechanism. Formal confirmation = live test: set USB Mode → MTP, replug, observe `091e:51b8` in `lsusb` and a gvfs mount.

## Missing Evidence

| Gap                                    | Impact                                              | How to Obtain                                  |
| -------------------------------------- | --------------------------------------------------- | ---------------------------------------------- |
| Live lsusb/dmesg after USB Mode → MTP  | Formally confirms root cause + closes the case      | Plug watch in after setting change; `lsusb -d 091e:`, `journalctl -k -f` |
| Current USB Mode value on the watch    | Distinguishes "set to Garmin" vs "prompt mis-answered" sub-cause | Watch: hold middle-left → Watch Settings → System → Advanced → USB Mode |
| Mount behavior with unknown PID on 1.1.21 | Settles Backlog #7 (quirk-flag risk)              | `mtp-detect` + try gvfs mount after switch     |

## Source Code Trace

| Element       | Detail                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| Error origin  | Device-side: Fenix 8 USB Mode state machine (Garmin mode → PID 0003)   |
| Trigger       | USB connect while USB Mode = Garmin (or MTP prompt blocked/declined)   |
| Condition     | Watch never re-enumerates; host sees only vendor class-255 interface   |
| Related files | Host side (post-fix): libmtp `music-players.h` IDs 51b8/51b5, mtp-probe/udev, gvfs-mtp |

## Follow-up: 2026-06-10 (live verification)

### New Evidence

- 12:12:57 — watch connected, enumerated `091e:0003` (kernel log) — failure reproduced.
- 12:13:29–34 — after watch-side action (USB Mode → MTP), device disconnected and re-enumerated as `idVendor=091e, idProduct=51b8`, SerialNumber `0000d7710494` (kernel log) — exactly the predicted Fenix 8 AMOLED MTP PID.
- gvfs auto-mounted `mtp://091e_51b8_0000d7710494/` on stock libmtp 1.1.21 (`gio mount -li`); `Internal Storage/GARMIN/Apps` reachable via the fuse path.
- `gio copy watch/bin/PaceTurner.prg` → `GARMIN/Apps/PaceTurner.prg` (98,524 bytes); volume unmounted cleanly.

### Updated Hypotheses

- Hypothesis 3 → **Confirmed** (live re-enumeration after watch-side change; no host-side change made).
- Deduction 2 → **Confirmed** (unknown PID 51b8 mounted fine on libmtp 1.1.21; Backlog #7 Done).

### Updated Conclusion

Root cause Confirmed with deterministic repro. Case Concluded.

## Conclusion

**Confidence:** High (root cause Confirmed live; deterministic repro: Garmin mode → `0003`/no mount, MTP mode → `51b8`/gvfs mount/sideload works)

The `.prg` sideload was blocked because the Fenix 8 was in **Garmin (vendor protocol) USB mode** — `091e:0003` is that mode's PID, and the mode switch to MTP happens **only on the watch** (USB Mode setting, or accepting the per-connection prompt with no other dialog open). The host-side MTP stack was never in the causal path. Secondary, confirmed-but-non-blocking: Ubuntu 24.04's libmtp 1.1.21 predates the Fenix 8 IDs (`091e:51b8`/`51b5`, libmtp ≥1.1.23); expect an "UNKNOWN device" label and possibly missing quirk flags — mount should still work.

## Recommended Next Steps

### Fix direction

1. **Watch-side (root cause):** Hold middle-left button → Watch Settings → System → Advanced → USB Mode → **MTP**. Replug. Dismiss any on-watch dialog (e.g., maps download) — an open dialog blocks enumeration (Finding 4).
2. **Host-side (only if mount fails after #1):** upgrade libmtp ≥1.1.23 (source build or newer packages) or add `091e:51b8` locally; verify with `mtp-detect`.

### Diagnostic

With the watch connected after the setting change: `lsusb -d 091e:` (expect `51b8`), `journalctl -k -f` during plug-in, `gio mount -li | grep -A2 -i mtp`, then check for the `GARMIN/` tree under `gvfs`.

## Reproduction Plan

1. Watch in Garmin mode + plug in → observe `091e:0003`, no mount (reproduces the failure).
2. Set USB Mode → MTP, replug, unlock watch, dismiss dialogs → expect re-enumeration as `091e:51b8` and gvfs MTP mount exposing `GARMIN/APPS` for `.prg` drop.

## Side Findings

- Watch was not connected during this session — all prior-session observations carried forward with that caveat.
- `091e:0003` is also claimable by the legacy `garmin_gps` kernel module (creates ttyUSB) — irrelevant once in MTP mode, but explains odd serial-device appearances in Garmin mode.
- libmtp Fenix entries use `DEVICE_FLAGS_ANDROID_BUGS` — Garmin's MTP stack follows Android MTP conventions.
