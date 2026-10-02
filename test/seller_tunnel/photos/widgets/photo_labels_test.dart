import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_labels.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  final l10n = AppLocalizationsFr();

  test('labels every defect', () {
    expect(
      [for (final i in PhotoQualityIssue.values) photoIssueLabel(l10n, i)],
      ['Sombre', 'Surexposée', 'Floue', 'Penchée', 'Encombrée'],
    );
    expect(
      photoIssuesLabel(l10n, const [
        PhotoQualityIssue.dark,
        PhotoQualityIssue.blurry,
      ]),
      'sombre, floue',
    );
  });

  test('photoIssues merges the device checks and the vision AI', () {
    final photo = testRoomPhoto(
      'a',
      quality: const PhotoQuality(issues: [PhotoQualityIssue.tilted]),
      analysis: const RoomPhotoAnalysis(
        qualityIssues: [PhotoQualityIssue.dark, PhotoQualityIssue.tilted],
      ),
    );
    expect(photoIssues(photo), [
      PhotoQualityIssue.dark,
      PhotoQualityIssue.tilted,
    ]);
    expect(photoIssues(testRoomPhoto('b')), isEmpty);
  });
}
