import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// One wrapped line of the context-on-pause paragraph (Story 3.4, AC2) — a
// CustomMenuItem rendered inside the PausedContextView CustomMenu, so it inherits the
// widget's native fluid scroll. It paints its line's words left-aligned; the CURRENT
// word (absolute index == currentIndex) is marked by BRIGHTNESS — COLOR_INK (bright)
// against the COLOR_INK_DIM body — never a second accent color (DESIGN: hierarchy is
// brightness "ink → ink-dim", "one red, one job"; brightness-only marking is also
// color-blind safe, UX-DR24).
//
// It is a passive, read-only row: no onSelect behaviour (the reading screen has
// nothing to select — BACK pops, handled by the delegate). Holds only its own words +
// indices (snapshot, paused) — no engine/view back-reference (AR15).
class PausedContextLine extends WatchUi.CustomMenuItem {

    // ── DESIGN palette (by name, no inline hex at draw sites; shared values with
    // PlaybackView). Marking is brightness, not a second color.
    private const COLOR_INK = 0xEAE6DF;       // the current word (bright)
    private const COLOR_INK_DIM = 0x8A867F;   // paragraph body (dim)

    private var _words as Array<String>;
    private var _indices as Array<Number>;    // parallel absolute word indices
    private var _currentIndex as Number;
    private var _font as Graphics.FontType;
    private var _margin as Number;            // left inset (matches the menu's wrap inset)

    function initialize(id as Number, words as Array<String>, indices as Array<Number>,
                        currentIndex as Number, font as Graphics.FontType, margin as Number) {
        CustomMenuItem.initialize(id, {});
        _words = words;
        _indices = indices;
        _currentIndex = currentIndex;
        _font = font;
        _margin = margin;
    }

    // Paint the line's words left-aligned, vertically centered in the item rect. The
    // menu owns scrolling/positioning; we only blit cached words (cheap — no decode,
    // no per-frame rebuild). Advancing x by measured width + a space keeps the single
    // current word the bright one.
    function draw(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var cy = h / 2;
        var spaceW = dc.getTextWidthInPixels(" ", _font);
        var x = _margin;
        for (var i = 0; i < _words.size(); i++) {
            var word = _words[i];
            dc.setColor(_indices[i] == _currentIndex ? COLOR_INK : COLOR_INK_DIM,
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, _font, word,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(word, _font) + spaceW;
        }
    }
}
