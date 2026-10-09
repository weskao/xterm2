import 'dart:math' show max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show HSVColor;
import 'package:flutter/widgets.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/painter.dart';
import 'package:xterm2/src/ui/palette_builder.dart';
import 'package:xterm2/xterm.dart';

const _lightBackgrounds = [
  ui.Color(0xFFF7F8FA),
  ui.Color(0xFFFDF6E3),
  ui.Color(0xFFFBF1C7),
  ui.Color(0xFFF4F9FF),
];
const _darkBackground = ui.Color(0xFF0A0C10);
const _lightBackground = ui.Color(0xFFF7F8FA);

void main() {
  group('ensureContrastRatio', () {
    test('returns the foreground unchanged when it already contrasts', () {
      const foreground = ui.Color(0xFF24292F);

      expect(
        ensureContrastRatio(foreground, _lightBackground, 4.5),
        same(foreground),
      );
    });

    test('reaches the ratio for palette and 24-bit colors', () {
      final palette = PaletteBuilder(TerminalThemes.defaultTheme);
      final foregrounds = [
        for (var i = 16; i < 256; i++) palette.paletteColor(i),
        const ui.Color(0xFFFFFFFF),
        const ui.Color(0xFFEEEEEE),
        const ui.Color(0xFFFFFF00),
        const ui.Color(0xFF00FFFF),
        const ui.Color(0xFFFF00FF),
        for (var i = 0; i < 64; i++)
          HSVColor.fromAHSV(1, i * 360 / 64, 1, 1).toColor(),
        for (var i = 0; i < 64; i++)
          ui.Color.from(alpha: 1, red: i / 63, green: i / 63, blue: i / 63),
      ];

      for (final background in [..._lightBackgrounds, _darkBackground]) {
        for (final foreground in foregrounds) {
          final result = ensureContrastRatio(foreground, background, 4.5);
          expect(
            _contrast(result, background),
            greaterThanOrEqualTo(4.5),
            reason: '$foreground on $background',
          );
          expect(result.a, foreground.a);
        }
      }
    });

    test('falls back to the best achievable extreme', () {
      const background = ui.Color(0xFF777777);
      final best = max(
        _contrast(const ui.Color(0xFF000000), background),
        _contrast(const ui.Color(0xFFFFFFFF), background),
      );

      final result =
          ensureContrastRatio(const ui.Color(0xFF808080), background, 7);

      expect(_contrast(result, background), closeTo(best, 0.001));
    });

    test('keeps the hue of an adjusted saturated color', () {
      const foreground = ui.Color(0xFFFF8800);

      final result = ensureContrastRatio(foreground, _lightBackground, 4.5);

      expect(result, isNot(foreground));
      expect(
        HSVColor.fromColor(result).hue,
        closeTo(HSVColor.fromColor(foreground).hue, 3),
      );
    });
  });

  group('TerminalPainter minimumContrastRatio', () {
    test('raises low-contrast glyph colors on a light theme', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final line = _line('█', CursorStyle()..setForegroundColor256(255));

      final pixel = await _pixel(painter, line, top: false);

      expect(_contrast(pixel, _lightBackground), greaterThanOrEqualTo(4.5));
      painter.dispose();
    });

    test('raises text glyph colors on a light theme', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final line = _line('X', CursorStyle()..setForegroundColor256(255));

      final pixel = await _pixel(painter, line, top: false);

      expect(_contrast(pixel, _lightBackground), greaterThanOrEqualTo(4.5));
      painter.dispose();
    });

    test('keeps cell background fills unchanged', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final style = CursorStyle()
        ..setForegroundColor256(255)
        ..setBackgroundColor256(254);
      final line = _line('▀', style);

      final glyph = await _pixel(painter, line, top: true);
      final fill = await _pixel(painter, line, top: false);

      expect(fill, const ui.Color(0xFFE4E4E4));
      expect(_contrast(glyph, fill), greaterThanOrEqualTo(4.5));
      painter.dispose();
    });

    test('paints as before when the ratio is 1', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final line = _line('█', CursorStyle()..setForegroundColor256(255));
      await _pixel(painter, line, top: false);

      painter.theme = _theme();
      final pixel = await _pixel(painter, line, top: false);

      expect(pixel, const ui.Color(0xFFEEEEEE));
      painter.dispose();
    });

    test('keeps faint text readable but dimmer than normal text', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final normal = await _pixel(
        painter,
        _line('█', CursorStyle()..setForegroundColor256(255)),
        top: false,
      );
      final faint = await _pixel(
        painter,
        _line(
          '█',
          CursorStyle()
            ..setForegroundColor256(255)
            ..setFaint(),
        ),
        top: false,
      );

      expect(_contrast(faint, _lightBackground), greaterThanOrEqualTo(3));
      expect(
        _contrast(faint, _lightBackground),
        lessThan(_contrast(normal, _lightBackground)),
      );
      painter.dispose();
    });

    test('measures inverse cells against their drawn background', () async {
      final painter = _painter(_theme(minimumContrastRatio: 4.5));
      final style = CursorStyle()
        ..setForegroundColor256(255)
        ..setInverse();
      final line = _line('▀', style);

      final glyph = await _pixel(painter, line, top: true);
      final fill = await _pixel(painter, line, top: false);

      expect(fill, const ui.Color(0xFFEEEEEE));
      expect(_contrast(glyph, fill), greaterThanOrEqualTo(4.5));
      painter.dispose();
    });
  });
}

TerminalTheme _theme({double minimumContrastRatio = 1}) {
  const base = TerminalThemes.defaultTheme;
  return TerminalTheme(
    cursor: base.cursor,
    selection: base.selection,
    foreground: const ui.Color(0xFF24292F),
    background: _lightBackground,
    black: base.black,
    white: base.white,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
    minimumContrastRatio: minimumContrastRatio,
  );
}

TerminalPainter _painter(TerminalTheme theme) {
  return TerminalPainter(
    theme: theme,
    textStyle: const TerminalStyle(fontSize: 20, height: 1),
    textScaler: TextScaler.noScaling,
  );
}

BufferLine _line(String char, CursorStyle style) {
  return BufferLine(1)..setCell(0, char.runes.single, 1, style);
}

/// Reads the color at the horizontal center of the first cell, a quarter of
/// the cell height from the [top] or the bottom.
Future<ui.Color> _pixel(
  TerminalPainter painter,
  BufferLine line, {
  required bool top,
}) async {
  final recorder = ui.PictureRecorder();
  painter.paintLine(ui.Canvas(recorder), ui.Offset.zero, line);
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 40);
  picture.dispose();
  final ByteData? bytes =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = image.width;
  image.dispose();
  if (bytes == null) fail('Expected line image bytes');

  final x = (painter.cellSize.width / 2).floor();
  final quarter = painter.cellSize.height / 4;
  final y = (top ? quarter : painter.cellSize.height - quarter).floor();
  final offset = (y * width + x) * 4;
  return ui.Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

double _contrast(ui.Color first, ui.Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}
