import Toybox.Lang;
import Toybox.Test;

// Minimal host-side test so the "Run No Evil" suite has something to pass in CI.
// Real engine tests (ReaderEngine, SyncManager, ...) arrive with Epic 3/4.
(:test)
function smokeTest(logger as Test.Logger) as Boolean {
    logger.debug("PaceTurner watch scaffold smoke test");
    return true;
}
