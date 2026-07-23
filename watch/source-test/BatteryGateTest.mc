import Toybox.Lang;
import Toybox.Test;

// Host tests for the PURE half of the BatteryGate module (Story 3.9, AC1/AC2) —
// the %/hour extrapolation and the compact machine-readable evidence string.
// The Sampler class (the System/Timer adapter that reads getSystemStats) needs a
// device context and is proven by the on-device gate run (Task 4), exactly as
// SyncManager's adapter half and Settings' loadFrom/save are host-untestable.
// No Test.assert* API — conditionals + logger.error(...) + return false (mirrors
// SyncManagerTest / ReaderEngineTest).

// Float-equality within a small epsilon — extrapolation is Float arithmetic, so
// compare with tolerance rather than ==. A plain helper (NOT (:test)): the
// tester would otherwise invoke it as a zero-context test and error on the arity.
function batteryDrainPerHourClose(a as Float, b as Float, logger as Test.Logger, label as String) as Boolean {
    var d = a - b;
    if (d < 0.0) { d = -d; }
    if (d > 0.01) { logger.error(label + ": " + a.toString() + " != " + b.toString()); return false; }
    return true;
}

// ── AC1/AC2: drainPerHour — extrapolate an absolute drain to a %/hour rate ────

(:test)
function batteryDrainPerHourExtrapolates(logger as Test.Logger) as Boolean {
    // 9% over exactly one hour ⇒ 9.0 %/h (the ≤10%/hour target sits just above).
    if (!batteryDrainPerHourClose(BatteryGate.drainPerHour(88.0, 79.0, 3600000), 9.0, logger, "1h drain")) { return false; }
    // 5% over half an hour ⇒ 10.0 %/h — extrapolation, not raw drain (a 60-min
    // gate may be stopped early; the rate is what the ≤10%/h target compares on).
    if (!batteryDrainPerHourClose(BatteryGate.drainPerHour(90.0, 85.0, 1800000), 10.0, logger, "30m extrapolated")) { return false; }
    // Over-target: 12% over an hour ⇒ 12.0 %/h (AC2 flag territory).
    if (!batteryDrainPerHourClose(BatteryGate.drainPerHour(80.0, 68.0, 3600000), 12.0, logger, "over-target")) { return false; }
    return true;
}

(:test)
function batteryDrainPerHourDegrades(logger as Test.Logger) as Boolean {
    // Zero window ⇒ 0.0 (no basis to extrapolate — never divide by zero).
    if (!batteryDrainPerHourClose(BatteryGate.drainPerHour(88.0, 79.0, 0), 0.0, logger, "zero elapsed")) { return false; }
    // Negative window (getTimer() wraparound reached the pure fn) ⇒ 0.0.
    if (!batteryDrainPerHourClose(BatteryGate.drainPerHour(88.0, 79.0, -5), 0.0, logger, "negative elapsed")) { return false; }
    // Battery went UP (charger contamination) ⇒ negative rate, reported honestly
    // (never clamped to 0 — the sign is evidence the run is polluted).
    if (BatteryGate.drainPerHour(70.0, 75.0, 3600000) >= 0.0) { logger.error("gain not reported negative"); return false; }
    return true;
}

// ── AC1: evidenceString — compact, machine-readable, one line ────────────────

(:test)
function batteryEvidenceStringValidRun(logger as Test.Logger) as Boolean {
    var s = BatteryGate.evidenceString(88.0, 79.0, 78.5, 3600000, 60, false, 300);
    // Every field the record must carry (Nerya reads this off the log, verbatim).
    if (s.find("start:88.0") == null) { logger.error("missing start%: " + s); return false; }
    if (s.find("end:79.0") == null) { logger.error("missing end%: " + s); return false; }
    if (s.find("drain:9.0") == null) { logger.error("missing drain%: " + s); return false; }
    if (s.find("rate:9.0") == null) { logger.error("missing rate %/h: " + s); return false; }
    if (s.find("min:78.5") == null) { logger.error("missing min%: " + s); return false; }
    if (s.find("elapsedMs:3600000") == null) { logger.error("missing elapsedMs: " + s); return false; }
    if (s.find("samples:60") == null) { logger.error("missing samples: " + s); return false; }
    if (s.find("wpm:300") == null) { logger.error("missing wpm: " + s); return false; }
    if (s.find("charging:false") == null) { logger.error("missing charging flag: " + s); return false; }
    // A clean run must NOT carry the invalid prefix.
    if (s.find("INVALID") != null) { logger.error("clean run flagged invalid: " + s); return false; }
    return true;
}

(:test)
function batteryEvidenceStringChargingIsFlaggedInvalid(logger as Test.Logger) as Boolean {
    // charging seen at any sample ⇒ the run is INVALID (Task 3): a USB/charger
    // reading pollutes the measurement (V1's unusable 32% post-charger reading).
    // The flag must be PROMINENT — a leading token, not buried in the tail.
    var s = BatteryGate.evidenceString(88.0, 90.0, 88.0, 3600000, 60, true, 300);
    if (s.find("INVALID-CHARGING") == null) { logger.error("charging run not prominently flagged invalid: " + s); return false; }
    if (s.find("charging:true") == null) { logger.error("charging flag not true: " + s); return false; }
    return true;
}
