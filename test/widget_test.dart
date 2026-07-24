// Basic smoke test for the ExplorerOS-Mobile foundation.
//
// It boots the app inside a Riverpod ProviderScope and verifies that the Home
// screen renders and the bottom navigation exposes all five tabs. This guards
// the core foundation (theme + navigation + Riverpod) against regressions.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots and shows all bottom navigation tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // Home landing content is visible on launch.
    expect(find.text('Welcome to ExplorerOS'), findsOneWidget);

    // All five bottom-navigation tabs are present.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Destinations'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Radio'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
