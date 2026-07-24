// Smoke test for the ExplorerOS app shell.
//
// Boots the app inside a Riverpod ProviderScope and verifies the dashboard
// renders and the bottom navigation exposes all five tabs. Guards the core
// foundation (theme + navigation + Riverpod) against regressions.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots to the dashboard with all five tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // Hero shows the product name on launch.
    expect(find.text('ExplorerOS'), findsWidgets);

    // All five bottom-navigation tabs are present.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Radio'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    // A dashboard card is rendered.
    expect(find.text('Start Exploring'), findsOneWidget);
  });
}
