import 'package:mobileapp/l10n/l10n.dart';
import 'package:property_repository/property_repository.dart';

/// Label of a photo defect ("Sombre", "Floue"…).
String photoIssueLabel(AppLocalizations l10n, PhotoQualityIssue issue) =>
    switch (issue) {
      PhotoQualityIssue.dark => l10n.photosIssueDark,
      PhotoQualityIssue.overexposed => l10n.photosIssueOverexposed,
      PhotoQualityIssue.blurry => l10n.photosIssueBlurry,
      PhotoQualityIssue.tilted => l10n.photosIssueTilted,
      PhotoQualityIssue.cluttered => l10n.photosIssueCluttered,
    };

/// The defects of a photo, in a sentence ("sombre, floue").
String photoIssuesLabel(
  AppLocalizations l10n,
  List<PhotoQualityIssue> issues,
) =>
    [for (final issue in issues) photoIssueLabel(l10n, issue).toLowerCase()]
        .join(', ');

/// The defects of [photo]: those found on the device and by the vision AI.
List<PhotoQualityIssue> photoIssues(RoomPhoto photo) => [
  for (final issue in PhotoQualityIssue.values)
    if ((photo.quality?.issues.contains(issue) ?? false) ||
        (photo.analysis?.qualityIssues.contains(issue) ?? false))
      issue,
];
