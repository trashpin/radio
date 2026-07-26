import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/core/theme/app_theme.dart';
import 'package:explorer_os_mobile/features/admin/presentation/csv_import_page.dart';

void main() {
  testWidgets('CsvImporterTab builds without throwing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: CsvImporterTab()),
    ));
    await tester.pump();
    expect(find.text('CSV Importer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CsvImporterTab renders loaded state (mapping + preview) without '
      'layout errors', (tester) async {
    // Tall viewport so the whole ListView builds (no lazy cutoff) and any
    // layout error in the preview/import cards is caught.
    tester.view.physicalSize = const Size(1000, 3000);
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
                        child: TabBarView(children: [
                          CsvImporterTab(
                            debugHeaders: [
                              'Common Name',
                              'Scientific Name',
                              'Description',
                            ],
                            debugRows: [
                              ['Saw Palmetto', 'Serenoa repens', 'A fan palm.'],
                              ['Longleaf Pine', 'Pinus palustris', 'A pine.'],
                            ],
                          ),
                        ]),
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
    expect(find.text('2. Map columns'), findsOneWidget);
    expect(find.text('3. Preview & validate'), findsOneWidget);
    expect(find.text('4. Import'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
