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
    expect(find.text('Vehicle'), findsNothing);
    expect(find.text('Doors'), findsOneWidget);
    expect(find.text('Windows'), findsNothing);
    expect(find.text('Sunroof'), findsOneWidget);
    expect(find.text('Lock All'), findsOneWidget);
    expect(find.text('Trunk'), findsOneWidget);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
