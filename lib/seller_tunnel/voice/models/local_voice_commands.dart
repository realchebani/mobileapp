/// A short answer recognised in the app, without the agent (plan §5.4):
/// no cost, no latency.
enum LocalVoiceCommand {
  /// "Oui", "c’est ça", "exact"… (a confirmation is waiting).
  yes,

  /// "Non", "non merci"… (a confirmation is waiting).
  no,

  /// "Annule", "efface", "c’est faux": undoes the last turn.
  cancel,

  /// "Terminé", "c’est tout", "j’ai fini": ends the sheet.
  finish;

  /// The command said in [transcript] (exact match of a short phrase,
  /// accents, case and punctuation ignored), or null: the agent answers.
  static LocalVoiceCommand? match(String transcript) {
    final text = normalize(transcript);
    if (text.isEmpty || text.split(' ').length > maxWords) return null;
    for (final MapEntry(key: command, value: phrases) in _phrases.entries) {
      if (phrases.contains(text)) return command;
    }
    return null;
  }

  /// Longest phrase recognised.
  static const maxWords = 4;

  static const Map<LocalVoiceCommand, Set<String>> _phrases = {
    yes: {
      'oui',
      'ouais',
      'oui oui',
      'oui merci',
      'oui c est ca',
      'oui c est correct',
      'oui c est bon',
      'oui tout a fait',
      'c est ca',
      'c est correct',
      'c est bon',
      'exact',
      'exactement',
      'tout a fait',
      'd accord',
      'ok',
      'okay',
      'parfait',
      'valide',
      'je confirme',
      'confirme',
    },
    no: {
      'non',
      'non non',
      'non merci',
      'non pas du tout',
      'pas du tout',
      'surtout pas',
      'non c est pas ca',
      'ce n est pas ca',
    },
    cancel: {
      'annule',
      'annuler',
      'annule ca',
      'annule le',
      'efface',
      'efface ca',
      'effacer',
      'c est faux',
      'non c est faux',
      'retire ca',
      'supprime ca',
    },
    finish: {
      'termine',
      'terminer',
      'c est tout',
      'c est fini',
      'j ai fini',
      'j ai termine',
      'fini',
      'stop',
      'on arrete',
      'ce sera tout',
    },
  };

  /// Lower case, no accents nor punctuation, single spaces.
  static String normalize(String text) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
      'œ': 'oe',
    };
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final char in lower.split('')) {
      buffer.write(accents[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp('[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(' +'), ' ');
  }
}
