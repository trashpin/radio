import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/db_tools/db_tools.dart';

void main() {
  group('csvEncode', () {
    test('encodes header + rows with union of keys', () {
      final csv = csvEncode([
        {'id': 1, 'name': 'Alexander Springs'},
        {'id': 2, 'name': 'Juniper', 'extra': 'x'},
      ]);
      final lines = csv.split('\n');
      expect(lines.first, 'id,name,extra');
      expect(lines[1], '1,Alexander Springs,');
      expect(lines[2], '2,Juniper,x');
    });

    test('quotes values containing commas/quotes/newlines', () {
      final csv = csvEncode([
        {'a': 'hello, world', 'b': 'say "hi"'},
      ]);
      expect(csv.contains('"hello, world"'), isTrue);
      expect(csv.contains('"say ""hi"""'), isTrue);
    });

    test('empty input → empty string', () {
      expect(csvEncode([]), '');
    });
  });

  group('registries', () {
    test('dashboard + browsable tables are defined', () {
      expect(kDashboardTables, isNotEmpty);
      expect(kDbTables.any((t) => t.name == 'story_library'), isTrue);
      expect(kDbTables.any((t) => t.name == 'generation_jobs'), isTrue);
    });

    test('maintenance scripts: checks are non-destructive, fixes carry updates', () {
      final reset = kMaintenanceScripts.firstWhere((s) => s.id == 'reset_failed_jobs');
      expect(reset.isDestructive, isTrue);
      expect(reset.update, isNotNull);
      expect(reset.op, FilterOp.eq);
      expect(reset.value, 'failed');

      final missing = kMaintenanceScripts.firstWhere((s) => s.id == 'stories_missing_audio');
      expect(missing.isDestructive, isFalse);
      expect(missing.op, FilterOp.isNull);
      expect(missing.update, isNull);
    });
  });
}
