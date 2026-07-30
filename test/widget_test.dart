// Smoke test for the ExplorerOS app shell.
//
// Boots the app inside a Riverpod ProviderScope and verifies the redesigned
// five-tab bottom navigation (Radio, Explore, Map, Stories, More) is present.
// Guards the core foundation (theme + navigation + Riverpod) against regressions.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots with the redesigned five tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // The five bottom-navigation tabs are present.
    expect(find.text('Radio'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Stories'), findsWidgets);
    expect(find.text('More'), findsWidgets);
  });
}
