import Toybox.Lang;

// Centralised Application.Storage key names — never inline a key string at a
// call site (mirrors the Protocol.* constant discipline, architecture AR8/AR16).
// Story 3.1 owns ONLY the per-device settings key; the full key set (position,
// active book, fingerprint, …) lands with Story 3.6 / Epic 4. Settings are
// per-device and never cross the protocol (AR16) — only *position* syncs.
module StorageKeys {

    // AR16 — the per-device Settings model persists behind this single key.
    const SETTINGS = "settings";
}
