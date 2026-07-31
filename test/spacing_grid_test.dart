import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Holds every gap and inset in the app to a 4pt grid.
///
/// Before this, 481 of 1210 spacing values sat off the grid — 2, 3, 5, 6, 7, 9,
/// 10, 14, 18, 22, 26, 30 — so nothing lined up with anything and no screen had
/// a rhythm. The grid is what makes spacing read as deliberate; a bare 13 next
/// to a 14 next to an 18 reads as three accidents.
void main() {
  test('every gap and inset is a multiple of 4', () {
    final offenders = _offGridSpacing();

    final report = offenders
        .map((o) => '  ${o.file}:${o.line}  ${o.value}  ${o.source}')
        .join('\n');

    expect(
      offenders,
      isEmpty,
      reason: '${offenders.length} spacing value(s) sit off the 4pt grid. '
          'Round to the nearest multiple of 4, or use a Spacing constant.\n'
          '$report',
    );
  });
}

const List<String> _scannedRoots = ['lib'];

class _OffGrid {
  final String file;
  final int line;
  final int value;
  final String source;

  const _OffGrid(this.file, this.line, this.value, this.source);
}

/// Constructors whose numeric arguments are spacing.
///
/// `SizedBox` is included only when its sole argument is a height or a width —
/// then it is a spacer. A two-argument SizedBox is sizing a box, so its numbers
/// are dimensions and are left alone.
final RegExp _spacingCall =
    RegExp(r'(EdgeInsets\.(?:all|symmetric|only|fromLTRB)|SizedBox)\(');
final RegExp _number = RegExp(r'(?<![\w.])(\d+)(?![\w.])');
final RegExp _namedArgument = RegExp(r'(\w+):');

List<_OffGrid> _offGridSpacing() {
  final offenders = <_OffGrid>[];
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
      final source = file.readAsStringSync();
      for (final call in _spacingCall.allMatches(source)) {
        final body = _argumentsOf(source, call.end - 1);
        if (body == null) continue;
        if (call.group(1) == 'SizedBox' && !_isSpacer(body)) continue;
        for (final n in _number.allMatches(body)) {
          final value = int.parse(n.group(1)!);
          if (value % 4 == 0) continue;
          offenders.add(_OffGrid(
            file.path,
            _lineOf(source, call.start),
            value,
            '${call.group(1)}(${body.replaceAll(RegExp(r'\s+'), ' ').trim()})',
          ));
        }
      }
    }
  }
  return offenders;
}

/// A SizedBox is a spacer when it names exactly one of height or width. Anything
/// else — two dimensions, or a child — is a box, not a gap.
bool _isSpacer(String body) {
  final named = _namedArgument.allMatches(body).map((m) => m.group(1)).toSet();
  return named.length == 1 &&
      (named.contains('height') || named.contains('width'));
}

/// The text between the parenthesis at [open] and its match, so an argument list
/// wrapped over several lines is read whole. Null if unbalanced.
String? _argumentsOf(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  return null;
}

int _lineOf(String source, int offset) {
  return source.substring(0, offset).split('\n').length;
}
