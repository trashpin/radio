// Smoke test for the ExplorerOS app shell.
//
// Boots the app inside a Riverpod ProviderScope and verifies it opens to the
// "Around Me" primary experience and that the bottom navigation exposes its
// tabs. Guards the core foundation (theme + navigation + Riverpod) against
// regressions.

import 'package:explorer_os_mobile/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots to Around Me with the expected tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExplorerApp()));
    await tester.pumpAndSettle();

    // Opens to the Around Me experience (screen header + nav label).
    expect(find.text('Around Me'), findsWidgets);

    // Bottom-navigation tabs are present.
    expect(find.text('Radio'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Stories'), findsWidgets);
    expect(find.text('More'), findsWidgets);
  });
}
