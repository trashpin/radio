import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/core/theme/app_theme.dart';
import 'package:explorer_os_mobile/features/admin/presentation/csv_import_page.dart';

void main() {
  // Uses the real AppTheme, whose buttons are full-width by default — this is
  // what surfaced the "infinite width" crash the default test theme hid.
  testWidgets('CSV tab initial state inside TabBarView ancestor chain',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: DefaultTabController(
                  length: 1,
                  child: Column(
                    children: const [
                      TabBar(tabs: [Tab(text: 'CSV')]),
                      Expanded(
                        child: TabBarView(children: [CsvImporterTab()]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('CSV Importer'), findsOneWidget);
  });
}
