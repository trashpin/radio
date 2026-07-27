import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';

void main() {
  test('DestinationCategory covers the requested set + round-trips', () {
    expect(DestinationCategory.values.length, 14);
    expect(DestinationCategory.fromDb('national_forest'),
        DestinationCategory.nationalForest);
    expect(DestinationCategory.fromDb('wildlife_refuge'),
        DestinationCategory.wildlifeRefuge);
    expect(DestinationCategory.fromDb('???'), DestinationCategory.nationalPark);
  });

  test('JobStatus round-trips and flags terminal states', () {
    expect(JobStatus.fromDb('waiting_for_review'), JobStatus.waitingForReview);
    expect(JobStatus.completed.isTerminal, isTrue);
    expect(JobStatus.failed.isTerminal, isTrue);
    expect(JobStatus.researching.isTerminal, isFalse);
    expect(JobStatus.values.length, 8);
  });

  test('JobType round-trips', () {
    expect(JobType.fromDb('full'), JobType.full);
    expect(JobType.fromDb('bulk'), JobType.bulk);
    expect(JobType.fromDb('x'), JobType.research);
  });

  test('KnowledgeFact parses and toInsert omits server fields', () {
    final f = KnowledgeFact.fromJson({
      'id': 'k1',
      'destination': 'Ocala National Forest',
      'destination_category': 'national_forest',
      'category': 'Geology',
      'title': 'Limestone aquifer',
      'description': 'Springs bubble up from the Floridan aquifer.',
      'confidence_score': 0.9,
      'approved': false,
    });
    expect(f.category, 'Geology');
    expect(f.confidenceScore, 0.9);
    final ins = f.toInsert();
    expect(ins['destination'], 'Ocala National Forest');
    expect(ins['category'], 'Geology');
    expect(ins.containsKey('id'), isFalse);
  });

  test('GenerationJob parses status/type and toInsert', () {
    final j = GenerationJob.fromJson({
      'id': 'j1',
      'destination': 'Silver Glen Springs',
      'destination_category': 'spring',
      'job_type': 'full',
      'status': 'pending',
      'state': 'Florida',
      'radius_m': 200,
    });
    expect(j.jobType, JobType.full);
    expect(j.status, JobStatus.pending);
    expect(j.radiusM, 200);
    final ins = j.toInsert();
    expect(ins['job_type'], 'full');
    expect(ins['status'], 'pending');
    expect(ins['state'], 'Florida');
  });
}
