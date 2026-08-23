// Smoke test for the ExplorerOS app shell.
//
// Boots the app inside a Riverpod ProviderScope and verifies Sunshine Travel
// Radio's two-tab bottom navigation (Explore, Discover) is present. Guards
// the core foundation (theme + navigation + Riverpod) against regressions.
// Map, Wildlife Guide, and everything else live one tap away via More —
// see lib/core/navigation/app_shell.dart.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots with the two-tab Explore/Discover navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // The two bottom-navigation tabs are present.
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Discover'), findsWidgets);

    // Map, Wildlife Guide, and More are no longer bottom-navigation tabs —
    // they live one tap away via More instead.
    expect(find.text('Wildlife Guide'), findsNothing);
  });
}
