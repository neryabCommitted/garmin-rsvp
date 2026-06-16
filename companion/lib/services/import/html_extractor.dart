/// Shared plain-text extractor (Story 2.3): the front of the import pipeline
/// (`extract → sanitize → tokenize → bake`). It turns a source document into the
/// plain text the [sanitize]/[tokenize] stages expect, with **one blank line
/// (`\n\n`) between block-level units** so the tokenizer's paragraph boundary
/// (`\n\s*\n`, `tokenizer.dart:52`) fires exactly at real paragraph breaks.
///
/// Two inputs for this story:
/// - `.txt` (`isMarkdown == false`): returned unchanged — the file's own blank
///   lines already encode paragraphs.
/// - `.md` (`isMarkdown == true`): rendered to HTML with `package:markdown`,
///   parsed with `package:html`, then walked block-by-block. Each text-bearing
///   block becomes one paragraph; its internal whitespace (markdown soft line
///   breaks, source newlines) is collapsed to single spaces so the ONLY `\n\n`
///   in the output are the boundaries this extractor emits.
///
/// **Why the blank-line separation is load-bearing:** `tokenize()` derives
/// `paragraphStart` *only* from `\n\s*\n`. If markdown blocks were joined
/// without a blank line, every `paragraphStart` flag would be silently lost →
/// wrong FR pacing/rewind boundaries baked permanently into the stream (the
/// watch never recomputes — `tokenizer.dart:7-9`).
///
/// This is the **shared core** Story 2.4's `epub_extractor` reuses for EPUB
/// spine HTML — an additive pure module (same rationale as
/// `word_stream_baker.dart`, not enumerated in `architecture.md`'s leaf list).
/// The richer DOM pre-filter (noteref/footnote anchors, `<rt>`/`<rp>` ruby
/// readings, image `alt`/`title`, table linearization) is opt-in via
/// [extractFromHtml]'s `epubFilter` flag (Story 2.4, AC1); the `.md`/`.txt` path
/// leaves it off so 2.3 behaviour is byte-for-byte unchanged.
///
/// Pure Dart: `package:markdown` and `package:html` are pure Dart — no
/// `package:flutter/*`, no async I/O, no global mutable state (AR19), so this
/// runs unchanged inside the `compute` isolate.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

/// Block-level elements whose text becomes a single paragraph. Their subtree
/// text is taken whole — we do NOT recurse past them.
const Set<String> _textBlocks = <String>{
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'pre', 'dd', 'dt',
};

/// Container elements that hold block children: recurse into them so each inner
/// block becomes its own paragraph.
const Set<String> _containers = <String>{
  'html', 'body', 'div', 'blockquote', 'ul', 'ol', 'dl', 'section', 'article',
};

/// Non-prose elements dropped entirely (inline HTML can smuggle these through
/// markdown's raw-HTML passthrough).
const Set<String> _dropped = <String>{'script', 'style'};

/// Ruby pronunciation elements dropped under [epubFilter] — the base reading
/// (`<rb>` / bare text) is kept; only the parenthetical pronunciation goes.
const Set<String> _rubyReadings = <String>{'rt', 'rp'};

/// `epub:type` values that mark a note reference whose subtree is dropped.
const Set<String> _noterefTypes = <String>{
  'noteref', 'footnote', 'rearnote', 'endnote',
};

/// `class`/`role` tokens on an `<a>` that mark it a footnote/endnote reference.
const Set<String> _footnoteClasses = <String>{
  'footnote', 'noteref', 'endnote', 'footnote-ref', 'fnref',
};

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Extracts plain text from [raw], inserting a blank line between block-level
/// units when [isMarkdown] is true (see library doc).
String extractPlainText(String raw, {required bool isMarkdown}) {
  if (!isMarkdown) {
    return raw;
  }
  return extractFromHtml(md.markdownToHtml(raw));
}

/// Walks [html] block-by-block into plain text with `\n\n` between blocks (the
/// shared core; see library doc). When [epubFilter] is true the AC1 DOM
/// pre-filter is applied: noteref/footnote anchors are dropped subtree-and-all,
/// `<rt>`/`<rp>` ruby readings are dropped (base kept), image `alt`/`title` is
/// never read (text nodes only), and `<table>`s are **linearized** (each `<tr>`
/// → one block, its `<td>`/`<th>` cells joined inline) so tabular prose survives.
String extractFromHtml(String html, {bool epubFilter = false}) {
  final document = html_parser.parse(html);
  final blocks = <String>[];
  final body = document.body;
  if (body != null) {
    _visit(body, blocks, epubFilter);
  }
  return blocks.join('\n\n');
}

void _visit(dom.Element element, List<String> blocks, bool epubFilter) {
  for (final node in element.nodes) {
    if (node is! dom.Element) {
      continue;
    }
    final tag = node.localName;
    if (tag == null || _dropped.contains(tag)) {
      continue;
    }
    if (epubFilter && _isNoteRef(node)) {
      continue; // drop the whole footnote-reference subtree
    }
    if (epubFilter && tag == 'table') {
      _linearizeTable(node, blocks);
      continue;
    }
    if (_textBlocks.contains(tag)) {
      final text = _collapse(_blockText(node, epubFilter));
      if (text.isNotEmpty) {
        blocks.add(text);
      }
    } else if (_containers.contains(tag)) {
      _visit(node, blocks, epubFilter);
    } else {
      // Unknown element (e.g. a bare inline wrapper at block level): treat its
      // text as a paragraph so nothing prose-bearing is dropped.
      final text = _collapse(_blockText(node, epubFilter));
      if (text.isNotEmpty) {
        blocks.add(text);
      }
    }
  }
}

/// AC1 table policy = **linearize**: emit each `<tr>` as one block, its cells'
/// text joined inline by a space. Keeps tabular prose rather than dropping it.
void _linearizeTable(dom.Element table, List<String> blocks) {
  for (final row in table.querySelectorAll('tr')) {
    final cells = <String>[];
    for (final cell in row.children) {
      final tag = cell.localName;
      if (tag == 'td' || tag == 'th') {
        final text = _collapse(_blockText(cell, true));
        if (text.isNotEmpty) {
          cells.add(text);
        }
      }
    }
    final rowText = cells.join(' ');
    if (rowText.isNotEmpty) {
      blocks.add(rowText);
    }
  }
}

/// A block's text. With [epubFilter] off this is `element.text` (verbatim 2.3
/// behaviour); with it on, only text nodes are read and ruby readings /
/// note-reference subtrees / dropped elements are skipped — so image `alt`/
/// `title` attributes are never seen (text nodes only).
String _blockText(dom.Element element, bool epubFilter) {
  if (!epubFilter) {
    return element.text;
  }
  final buffer = StringBuffer();
  _collectText(element, buffer);
  return buffer.toString();
}

void _collectText(dom.Node node, StringBuffer buffer) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      buffer.write(child.text);
    } else if (child is dom.Element) {
      final tag = child.localName;
      if (tag == null ||
          _dropped.contains(tag) ||
          _rubyReadings.contains(tag) ||
          _isNoteRef(child)) {
        continue;
      }
      _collectText(child, buffer);
    }
  }
}

/// True when [el] is a note reference to drop: it carries an `epub:type`
/// containing a noteref keyword, or it is an `<a>` whose `class`/`role` marks it
/// a footnote reference.
bool _isNoteRef(dom.Element el) {
  final epubType = _attr(el, 'epub:type');
  if (epubType != null) {
    final lower = epubType.toLowerCase();
    if (_noterefTypes.any(lower.contains)) {
      return true;
    }
  }
  if (el.localName == 'a') {
    final classes = (_attr(el, 'class') ?? '').toLowerCase().split(_whitespaceRun);
    if (classes.any(_footnoteClasses.contains)) {
      return true;
    }
    final role = (_attr(el, 'role') ?? '').toLowerCase();
    if (role == 'doc-noteref') {
      return true;
    }
  }
  return false;
}

/// Reads an attribute by its literal (possibly namespaced, e.g. `epub:type`)
/// name. `package:html` keeps unrecognized namespaced attributes as literal
/// string keys, but be defensive about non-string keys too.
String? _attr(dom.Element el, String name) {
  for (final entry in el.attributes.entries) {
    if (entry.key.toString() == name) {
      return entry.value;
    }
  }
  return null;
}

/// Collapses every run of whitespace (incl. newlines) to a single space and
/// trims, so the only `\n\n` in the output are the block separators this
/// extractor emits.
String _collapse(String text) => text.replaceAll(_whitespaceRun, ' ').trim();
