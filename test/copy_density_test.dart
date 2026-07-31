import 'dart:io';

import 'package:arth/widgets/premium_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against screens greeting the user with a paragraph.
///
/// Long-form copy is not banned — it is moved behind [ArthDisclosure], where it
/// costs nothing until the user asks for it. This test measures how much prose
/// is still rendered unconditionally and holds that number down. The baseline
/// only ever decreases. Raising it is the same as deleting the test.
void main() {
  test('screens render no more unconditional prose than the baseline', () {
    final offenders = _scanCopyBlobs();

    // Sorted worst-first so the next screen to fix is obvious from the failure.
    final report = offenders
        .take(12)
        .map((b) => '  ${b.file}:${b.line}  ${b.length}ch  ${b.preview}')
        .join('\n');

    expect(
      offenders.length,
      lessThanOrEqualTo(_baseline),
      reason: 'Unconditional prose count rose to ${offenders.length}, '
          'baseline is $_baseline. Move the detail into an ArthDisclosure '
          'instead of growing the line.\nWorst offenders:\n$report',
    );
  });

  test('baseline is not stale', () {
    // Keeps the ratchet honest: once screens improve, the baseline has to be
    // lowered in the same commit, or this fails and says by how much.
    final offenders = _scanCopyBlobs();
    expect(
      offenders.length,
      _baseline,
      reason: 'Prose count is now ${offenders.length}. Lower _baseline to '
          'match, in this commit.',
    );
  });
}

/// Current count of rendered strings over [ArthCopy.panelMessage].
///
/// Only ever goes down.
const int _baseline = 38;

const List<String> _scannedRoots = [
  'lib/screens',
  'lib/features',
  'lib/widgets'
];

class _Blob {
  final String file;
  final int line;
  final int length;
  final String preview;

  const _Blob(this.file, this.line, this.length, this.preview);
}

List<_Blob> _scanCopyBlobs() {
  final blobs = <_Blob>[];
  for (final root in _scannedRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final lines = _withoutComments(file.readAsStringSync()).split('\n');
      var i = 0;
      while (i < lines.length) {
        final literals = _stringLiterals(lines[i]).toList();
        if (literals.isEmpty) {
          i++;
          continue;
        }
        // Dart concatenates adjacent literals, so a paragraph wrapped over
        // several source lines is one string on screen. Join it back together
        // or every long blob measures as a set of harmless short ones.
        //
        // A trailing comma ends the expression, which is what separates a
        // wrapped paragraph from the elements of a list of short bullet
        // strings — those are rendered as separate rows and must not be joined.
        final buffer = StringBuffer(literals.join());
        var next = i + 1;
        while (next < lines.length && !_endsExpression(lines[next - 1])) {
          final continuation = _wholeLineLiteral(lines[next]);
          if (continuation == null) break;
          buffer.write(continuation);
          next++;
        }
        final joined = buffer.toString();
        final rendered = _renderedLength(joined);
        if (rendered > ArthCopy.panelMessage &&
            _looksLikeProse(joined) &&
            !_isDisclosedDetail(lines, i)) {
          blobs.add(_Blob(file.path, i + 1, rendered, _preview(joined)));
        }
        i = next;
      }
    }
  }
  blobs.sort((a, b) => b.length.compareTo(a.length));
  return blobs;
}

/// Strips `//` comments and `/* */` blocks so commented-out copy is not counted.
String _withoutComments(String source) {
  final withoutBlocks =
      source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks.split('\n').map((line) {
    final quote = _firstQuoteIndex(line);
    final comment = line.indexOf('//');
    if (comment < 0) return line;
    if (quote >= 0 && quote < comment) return line;
    return line.substring(0, comment);
  }).join('\n');
}

int _firstQuoteIndex(String line) {
  final single = line.indexOf("'");
  final double = line.indexOf('"');
  if (single < 0) return double;
  if (double < 0) return single;
  return single < double ? single : double;
}

/// Whether this copy is the collapsed detail of a disclosure, which is the
/// sanctioned home for long-form explanation and so is exempt.
///
/// `detail:` alone is not enough — it is also the argument name on several
/// ordinary row widgets whose subtitle the user sees immediately. The literal
/// has to be a `detail:` argument *of a disclosing widget*, so both the argument
/// name and the constructor are required.
bool _isDisclosedDetail(List<String> lines, int index) {
  if (!_isDetailArgument(lines, index)) return false;
  for (var back = index; back >= 0 && back >= index - 8; back--) {
    if (_disclosingWidget.hasMatch(lines[back])) return true;
  }
  return false;
}

/// Widgets that collapse their `detail` behind a tap.
final RegExp _disclosingWidget = RegExp(r'\b(ArthDisclosure|ArthStatePanel)\(');

bool _isDetailArgument(List<String> lines, int index) {
  if (lines[index].contains('detail:')) return true;
  for (var back = index - 1; back >= 0 && back >= index - 2; back--) {
    final previous = lines[back].trimRight();
    if (previous.isEmpty) continue;
    return previous.endsWith('detail:');
  }
  return false;
}

/// Whether the line closes the expression it is part of, so nothing after it
/// concatenates onto the same string.
bool _endsExpression(String line) {
  final trimmed = line.trimRight();
  return trimmed.endsWith(',') ||
      trimmed.endsWith(';') ||
      trimmed.endsWith(')') ||
      trimmed.endsWith(']');
}

/// The literal on a line that holds nothing but a literal, which is how the
/// formatter wraps a long piece of copy. Returns null for anything else.
String? _wholeLineLiteral(String line) {
  final trimmed = line.trim().replaceAll(RegExp(r',$'), '');
  final match = RegExp(r"^'((?:\\.|[^'\\])*)'$").firstMatch(trimmed) ??
      RegExp(r'^"((?:\\.|[^"\\])*)"$').firstMatch(trimmed);
  return match?.group(1);
}

/// Single- and double-quoted literals on one line, escapes tolerated.
Iterable<String> _stringLiterals(String line) {
  final pattern = RegExp(r"'((?:\\.|[^'\\])*)'" r'|"((?:\\.|[^"\\])*)"');
  return pattern
      .allMatches(line)
      .map((m) => m.group(1) ?? m.group(2) ?? '')
      .where((s) => s.isNotEmpty);
}

/// Length as the user sees it: interpolations collapse to a short value, since
/// `${money0(total)}` is a handful of characters on screen, not fourteen.
int _renderedLength(String literal) {
  final collapsed = literal
      .replaceAll(RegExp(r'\$\{[^{}]*\}'), 'XXXXXX')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_.]*'), 'XXXXXX')
      .replaceAll(r'\n', ' ');
  return collapsed.length;
}

/// Prose has spaces and lowercase words. Asset paths, keys, SQL and regexes do
/// not, and are long for reasons the user never sees.
bool _looksLikeProse(String literal) {
  if (literal.split(' ').length < 6) return false;
  if (literal.contains('assets/')) return false;
  if (literal.startsWith('http')) return false;
  return RegExp(r'[a-z]{3} [a-z]{3}').hasMatch(literal);
}

String _preview(String literal) {
  final flat = literal.replaceAll(RegExp(r'\s+'), ' ');
  return flat.length <= 56 ? flat : '${flat.substring(0, 53)}...';
}
