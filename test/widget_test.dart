import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:byd_launcher/main.dart';

void main() {
  testWidgets('launcher home renders', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: LauncherHomePage(enable3dModel: false)),
    );

    expect(find.text('SEALION 6'), findsNothing);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('FL'), findsNothing);
    expect(find.text('FR'), findsNothing);
    expect(find.text('RL'), findsNothing);
    expect(find.text('RR'), findsNothing);
    expect(find.text('Doors'), findsNothing);
    expect(find.text('Windows'), findsNothing);
    expect(find.text('Sunroof'), findsNothing);
    expect(find.text('TPMS'), findsOneWidget);
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Trunk'), findsOneWidget);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Navigation'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Navigation app'), findsOneWidget);
    expect(find.text('BYD'), findsWidgets);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Waze'), findsOneWidget);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('TPMS'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Vehicle color'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Default launcher'), findsOneWidget);
    expect(find.text('System permissions'), findsOneWidget);
    expect(find.text('System overlay'), findsOneWidget);
    expect(find.text('TPMS'), findsNothing);
  });
}
