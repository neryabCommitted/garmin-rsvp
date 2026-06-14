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
/// This is the **shared core** Story 2.4's `epub_extractor` will reuse for EPUB
/// spine HTML — an additive pure module (same rationale as
/// `word_stream_baker.dart`, not enumerated in `architecture.md`'s leaf list).
/// The richer DOM pre-filter (noteref/footnote/ruby/alt-text, table policy) is
/// **2.4's** job; here we only drop `script`/`style`.
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

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Extracts plain text from [raw], inserting a blank line between block-level
/// units when [isMarkdown] is true (see library doc).
String extractPlainText(String raw, {required bool isMarkdown}) {
  if (!isMarkdown) {
    return raw;
  }
  final html = md.markdownToHtml(raw);
  final document = html_parser.parse(html);
  final blocks = <String>[];
  final body = document.body;
  if (body != null) {
    _visit(body, blocks);
  }
  return blocks.join('\n\n');
}

void _visit(dom.Element element, List<String> blocks) {
  for (final node in element.nodes) {
    if (node is! dom.Element) {
      continue;
    }
    final tag = node.localName;
    if (tag == null || _dropped.contains(tag)) {
      continue;
    }
    if (_textBlocks.contains(tag)) {
      final text = _collapse(node.text);
      if (text.isNotEmpty) {
        blocks.add(text);
      }
    } else if (_containers.contains(tag)) {
      _visit(node, blocks);
    } else {
      // Unknown element (e.g. a bare inline wrapper at block level): treat its
      // text as a paragraph so nothing prose-bearing is dropped.
      final text = _collapse(node.text);
      if (text.isNotEmpty) {
        blocks.add(text);
      }
    }
  }
}

/// Collapses every run of whitespace (incl. newlines) to a single space and
/// trims, so the only `\n\n` in the output are the block separators this
/// extractor emits.
String _collapse(String text) => text.replaceAll(_whitespaceRun, ' ').trim();
