import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Tests for the Gate V1 spike's pure helpers (Story 1.3). The spike itself is
// hardware-judged; only the extracted pure functions are unit-tested.

(:test)
function gateV1FormatElapsedTest(logger as Test.Logger) as Boolean {
    logger.debug("formatElapsed: zero, sub-minute, minute boundary, past the hour");
    Test.assertEqualMessage(GateV1.formatElapsed(0), "00:00", "0 s");
    Test.assertEqualMessage(GateV1.formatElapsed(9), "00:09", "9 s");
    Test.assertEqualMessage(GateV1.formatElapsed(59), "00:59", "59 s");
    Test.assertEqualMessage(GateV1.formatElapsed(60), "01:00", "60 s");
    Test.assertEqualMessage(GateV1.formatElapsed(75), "01:15", "75 s");
    // Minutes keep counting past 59:59 — the 60-min gate must stay readable.
    Test.assertEqualMessage(GateV1.formatElapsed(3600), "60:00", "3600 s");
    Test.assertEqualMessage(GateV1.formatElapsed(3661), "61:01", "3661 s");
    return true;
}

(:test)
function gateV1LogToStringTest(logger as Test.Logger) as Boolean {
    logger.debug("logToString: empty, single entry, multiple entries");
    Test.assertEqualMessage(
        GateV1.logToString([] as Array<Array<Number> >), "", "empty log");
    Test.assertEqualMessage(
        GateV1.logToString([[0, 0]] as Array<Array<Number> >), "0:0", "baseline entry");
    Test.assertEqualMessage(
        GateV1.logToString([[0, 0], [14, 1], [3599, 1]] as Array<Array<Number> >),
        "0:0,14:1,3599:1", "HIGH at start, LOW at 14 s, still LOW near the hour");
    return true;
}

(:test)
function gateV1DisplayModeLabelTest(logger as Test.Logger) as Boolean {
    logger.debug("displayModeLabel: the three DisplayMode values plus unknown");
    Test.assertEqualMessage(
        GateV1.displayModeLabel(System.DISPLAY_MODE_HIGH_POWER), "HIGH", "high power");
    Test.assertEqualMessage(
        GateV1.displayModeLabel(System.DISPLAY_MODE_LOW_POWER), "LOW", "low power");
    Test.assertEqualMessage(
        GateV1.displayModeLabel(System.DISPLAY_MODE_OFF), "OFF", "off");
    Test.assertEqualMessage(GateV1.displayModeLabel(99), "?", "unknown value");
    return true;
}
