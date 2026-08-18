// Smoke test for the ExplorerOS app shell.
//
// Boots the app inside a Riverpod ProviderScope and verifies the simplified
// four-tab bottom navigation (Radio, Map, Wildlife Guide, More) is present.
// Guards the core foundation (theme + navigation + Riverpod) against regressions.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots with the simplified four tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // The four bottom-navigation tabs are present.
    expect(find.text('Radio'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Wildlife Guide'), findsWidgets);
    expect(find.text('More'), findsWidgets);

    // Explore and Stories are no longer bottom-navigation tabs.
    expect(find.text('Explore'), findsNothing);
    expect(find.text('Stories'), findsNothing);
  });
}
