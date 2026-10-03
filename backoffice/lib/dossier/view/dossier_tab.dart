/// Tabs of a dossier (URL segment `/dossiers/<id>/<segment>`).
enum DossierTab {
  synthesis('synthese'),
  photos('photos'),
  documents('documents'),
  voice('voix'),
  valuation('avis'),
  journal('journal');

  new(this.segment);

  final String segment;

  static DossierTab fromSegment(String? segment) =>
      values.firstWhere((t) => t.segment == segment, orElse: () => synthesis);
}
