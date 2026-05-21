import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:byd_launcher/main.dart';

void main() {
  testWidgets('launcher home renders', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const BydLauncherApp());

    expect(find.text('SEALION 6'), findsNothing);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('FL'), findsWidgets);
    expect(find.text('FR'), findsWidgets);
    expect(find.text('RL'), findsWidgets);
    expect(find.text('RR'), findsWidgets);
    expect(find.text('Doors'), findsNothing);
    expect(find.text('Windows'), findsNothing);
    expect(find.text('Sunroof'), findsNothing);
    expect(find.text('TPMS'), findsOneWidget);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Navigation'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No map app installed'), findsOneWidget);
    expect(
      find.text('Install Google Map or Waze, then tap reload above.'),
      findsOneWidget,
    );
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('TPMS'), findsOneWidget);

    expect(find.text('Settings'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
