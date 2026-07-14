import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Position persistence — resume-never-lies (Story 3.6, FR14/NFR4). Two halves,
// deliberately separated (the Settings pure/adapter pattern, architecture.md:451):
//
//   1. Pure free functions — shouldCommit / encodePosition / decodeIndex — the
//      host-testable persistence POLICY. Lang-only, no Storage/System/Time.
//   2. The SyncManager class — the thin Storage/clock adapter and the SINGLE
//      writer/reader of the pos_<bookId> key namespace (architecture.md:453).
//      PlaybackView and the App only call commitPosition; nothing else touches
//      a position key (AC1).
//
// Every Storage read/write is guarded: a persistence failure degrades (word 0 on
// read, a logged skip on write), never crashes a reading session or app exit
// (bounds-check-and-degrade, NFR8/AR24). Epic 4 grows this module the protocol-
// client half (the `position` BLE message + LWW reconcile, Story 4.5) and fills
// migrateIfNeeded's wipe list with the chunk_/meta_ content-cache keys (4.1).
module Sync {

    // Debounce window while playing (AR14/NFR4: position may trail live reading
    // by at most ~one persistence interval; every catchable transition is a
    // force-save, so the trail is only ever behind, never ahead).
    const DEBOUNCE_MS = 15000;

    // The current Storage-layout version, written under StorageKeys.SCHEMA_VERSION.
    const SCHEMA_VERSION_CURRENT = 1;

    // ── pure persistence policy (host-tested, never touches Storage) ─────────

    // Gate a position write. force ⇒ always; never written ⇒ yes; a clock
    // wraparound (now < lastWriteMs, System.getTimer() rolls over) ⇒ yes
    // (resync — mirrors the engine's onTick wraparound guard); otherwise only
    // once the debounce window has elapsed.
    function shouldCommit(lastWriteMs as Number?, now as Number, force as Boolean) as Boolean {
        if (force) {
            return true;
        }
        if (lastWriteMs == null) {
            return true;
        }
        var last = lastWriteMs as Number;
        if (now < last) {
            return true;
        }
        return now - last >= DEBOUNCE_MS;
    }

    // The stored position record. `ts` is epoch SECONDS — the unit Epic-4's LWW
    // reconcile compares on (architecture.md:241); storing it now is
    // forward-compatible and free.
    function encodePosition(index as Number, tsEpochSec as Number) as Dictionary {
        return { "pos" => index, "ts" => tsEpochSec };
    }

    // Bounds-check-and-degrade decode of a stored position (AC2/AC4). null ⇒ the
    // caller starts at word 0. A too-large index clamps DOWN to the last word
    // (a re-baked-shorter book or corrupt large value restores at-or-before the
    // end — never past it, never a crash).
    function decodeIndex(value as Object?, wordCount as Number) as Number? {
        if (wordCount <= 0) {
            return null;
        }
        if (!(value instanceof Lang.Dictionary)) {
            return null;
        }
        var pos = (value as Dictionary)["pos"];
        if (!(pos instanceof Lang.Number)) {
            return null;
        }
        var p = pos as Number;
        if (p < 0) {
            return null;
        }
        if (p > wordCount - 1) {
            return wordCount - 1;
        }
        return p;
    }

    // ── the thin Storage/clock adapter (the ONLY pos_* Storage access) ───────

    class SyncManager {

        private var _bookId as String;
        private var _lastWriteMs as Number?;
        private var _lastWrittenIndex as Number?;

        // migrateIfNeeded runs HERE, before any position read, so a schema bump
        // can never run over the position (AC3).
        function initialize(bookId as String) {
            _bookId = bookId;
            _lastWriteMs = null;
            _lastWrittenIndex = null;
            migrateIfNeeded();
        }

        // The restore index for this book, or null (nothing/malformed saved ⇒
        // start at word 0). Guarded: a throwing read degrades to null (AC4).
        function loadPosition(wordCount as Number) as Number? {
            var value = null;
            try {
                value = Storage.getValue(StorageKeys.posKey(_bookId));
            } catch (e) {
                System.println("Sync: position read failed");
                return null;
            }
            return decodeIndex(value, wordCount);
        }

        // The single position write path (AC1). The debounce/force gate is the
        // pure shouldCommit; a throwing write (e.g. StorageFullException on
        // exit) is swallowed-and-logged — a failed save must never crash a
        // reading session or app exit (AC4). Same-index suppression (review
        // 2026-07-14): an index already persisted is never rewritten — exit's
        // back-to-back onHide+onStop, rewind's explicit-force+settling-tick,
        // and context-view round-trips would otherwise each rewrite an
        // identical record to flash. (Skipping also leaves `ts` = when the
        // position last CHANGED, the honest LWW timestamp.) On failure the
        // debounce clock still advances — retry after one window, not on every
        // ~85 ms tick against a persistently-throwing store (AR25) — while a
        // force retry stays immediate (force bypasses the gate) and
        // _lastWrittenIndex stays unset so the retry is not suppressed.
        function commitPosition(index as Number, force as Boolean, nowMs as Number) as Void {
            if (_lastWrittenIndex != null && (_lastWrittenIndex as Number) == index) {
                return; // already persisted — nothing new to write
            }
            if (!shouldCommit(_lastWriteMs, nowMs, force)) {
                return;
            }
            try {
                Storage.setValue(StorageKeys.posKey(_bookId),
                    encodePosition(index, Time.now().value()) as Storage.ValueType);
                _lastWrittenIndex = index;
            } catch (e) {
                System.println("Sync: position write failed");
            }
            _lastWriteMs = nowMs; // success or failure: back off one debounce window
        }

        // Schema-version governance (AC3), before any position read. null ⇒
        // fresh install, just stamp. A mismatch wipes the CONTENT CACHE
        // (re-fetchable) and re-stamps — NEVER a pos_* key (position is the
        // only sacred state, architecture.md:181). Epic 3 has no content-cache
        // keys yet, so the wipe body is a documented structured no-op; Epic 4
        // fills it with the chunk_/meta_ deletions (Story 4.1). All guarded.
        // A THROWING schema read aborts the migration entirely (review
        // 2026-07-14): treating it as fresh-install would stamp CURRENT over a
        // possibly-mismatched layout and launder a real mismatch past the wipe
        // — an unreadable version must leave the stamp alone (retry next
        // launch); position reads proceed regardless.
        private function migrateIfNeeded() as Void {
            var stored = null;
            try {
                stored = Storage.getValue(StorageKeys.SCHEMA_VERSION);
            } catch (e) {
                System.println("Sync: schema read failed — migration skipped");
                return;
            }
            if (stored instanceof Lang.Number && (stored as Number) == SCHEMA_VERSION_CURRENT) {
                return; // layout is current — the common path
            }
            if (stored != null) {
                // Version mismatch: wipe the content cache here. Epic 3 stores
                // no content-cache keys — nothing to delete yet. Epic 4 (4.1)
                // deletes the chunk_<fp>_<n>/meta_<fp> keys at this exact spot.
                // Position keys are deliberately untouched.
            }
            try {
                Storage.setValue(StorageKeys.SCHEMA_VERSION, SCHEMA_VERSION_CURRENT);
            } catch (e) {
                System.println("Sync: schema stamp failed");
            }
        }
    }
}
