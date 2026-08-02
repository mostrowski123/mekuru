import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('SettingsSectionHeader', () {
    testWidgets('renders its title', (tester) async {
      await tester.pumpWidget(
        _wrap(const SettingsSectionHeader(title: 'EPUB')),
      );
      expect(find.text('EPUB'), findsOneWidget);
    });
  });

  group('SettingsSliderRow', () {
    testWidgets('renders label, value and helper text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSliderRow(
            icon: Icons.text_fields,
            label: 'Font size',
            valueLabel: '18',
            value: 18,
            min: 12,
            max: 32,
            helperText: 'Applies to all books',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('Applies to all books'), findsOneWidget);
      expect(find.byIcon(Icons.text_fields), findsOneWidget);
    });

    testWidgets('fires onChanged and onChangeEnd on drag', (tester) async {
      double? changed;
      double? changeEnded;
      await tester.pumpWidget(
        _wrap(
          SettingsSliderRow(
            value: 0.5,
            min: 0,
            max: 1,
            onChanged: (value) => changed = value,
            onChangeEnd: (value) => changeEnded = value,
          ),
        ),
      );
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      expect(changed, isNotNull);
      expect(changeEnded, isNotNull);
    });

    testWidgets('renders flanking icons and trailing widget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSliderRow(
            value: 0.5,
            min: 0,
            max: 1,
            leadingSliderIcon: Icons.brightness_low,
            trailingSliderIcon: Icons.brightness_high,
            trailing: const Icon(Icons.brightness_auto),
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.brightness_low), findsOneWidget);
      expect(find.byIcon(Icons.brightness_high), findsOneWidget);
      expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
    });
  });

  group('SettingsSegmentedRow', () {
    testWidgets('reports the tapped value', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _wrap(
          SettingsSegmentedRow<String>(
            label: 'Direction',
            segments: const [
              ButtonSegment(value: 'rtl', label: Text('Right to left')),
              ButtonSegment(value: 'ltr', label: Text('Left to right')),
            ],
            selected: 'rtl',
            onSelected: (value) => selected = value,
          ),
        ),
      );
      expect(find.text('Direction'), findsOneWidget);
      await tester.tap(find.text('Left to right'));
      expect(selected, 'ltr');
    });
  });

  group('SettingsSwitchRow', () {
    testWidgets('toggles and reports the new value', (tester) async {
      bool? toggled;
      await tester.pumpWidget(
        _wrap(
          SettingsSwitchRow(
            icon: Icons.link_off,
            title: 'Disable links',
            subtitle: 'Tap linked text to look it up',
            value: false,
            onChanged: (value) => toggled = value,
          ),
        ),
      );
      await tester.tap(find.byType(SwitchListTile));
      expect(toggled, isTrue);
    });

    testWidgets('renders disabled when onChanged is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettingsSwitchRow(title: 'Split vertical text', value: false),
        ),
      );
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNull);
    });
  });
}
