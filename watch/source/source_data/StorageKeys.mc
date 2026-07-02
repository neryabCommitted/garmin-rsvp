import Toybox.Lang;

// Centralised Application.Storage key names — never inline a key string at a
// call site (mirrors the Protocol.* constant discipline, architecture AR8/AR16).
// Story 3.1 owns the per-device settings key; Story 3.6 adds the per-book
// position key + the schema-version key. Position lands here; the content-cache
// keys (chunk_<fp>_<n> / meta_<fp>) land with Epic 4's ChunkedWordSource — they
// have no writer in Epic 3. Settings are per-device and never cross the
// protocol (AR16) — only *position* syncs (as a message, Epic 4; the
// pos_<bookId> key itself is local state).
module StorageKeys {

    // AR16 — the per-device Settings model persists behind this single key.
    const SETTINGS = "settings";

    // Story 3.6 — the schema-version KEY governing the Storage layout
    // (architecture.md:258). The current layout VALUE lives in
    // Sync.SCHEMA_VERSION_CURRENT; a mismatch wipes the content cache
    // (re-fetchable), never position.
    const SCHEMA_VERSION = "schemaVersion";

    // Story 3.6 — the per-book position key. bookId is the book's content
    // fingerprint (8 lowercase hex, Protocol.FINGERPRINT_LENGTH — FR20), so a
    // position never bleeds across books. SyncManager is the single owner of
    // this namespace (architecture.md:453).
    function posKey(bookId as String) as String {
        return "pos_" + bookId;
    }
}
