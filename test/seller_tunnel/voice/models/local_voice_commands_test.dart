import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';

void main() {
  group(LocalVoiceCommand, () {
    test('recognises the short answers, accents and punctuation ignored', () {
      expect(LocalVoiceCommand.match('Oui.'), LocalVoiceCommand.yes);
      expect(LocalVoiceCommand.match('Oui, c’est ça !'), LocalVoiceCommand.yes);
      expect(LocalVoiceCommand.match("D'accord"), LocalVoiceCommand.yes);
      expect(LocalVoiceCommand.match('Exactement'), LocalVoiceCommand.yes);
      expect(LocalVoiceCommand.match('Non merci'), LocalVoiceCommand.no);
      expect(LocalVoiceCommand.match('Annule'), LocalVoiceCommand.cancel);
      expect(LocalVoiceCommand.match('Efface ça.'), LocalVoiceCommand.cancel);
      expect(LocalVoiceCommand.match('C’est faux'), LocalVoiceCommand.cancel);
      expect(LocalVoiceCommand.match('Terminé'), LocalVoiceCommand.finish);
      expect(LocalVoiceCommand.match('J’ai fini'), LocalVoiceCommand.finish);
      expect(LocalVoiceCommand.match("C'est tout."), LocalVoiceCommand.finish);
    });

    test('anything else goes to the agent', () {
      expect(LocalVoiceCommand.match(''), isNull);
      expect(LocalVoiceCommand.match('Oui elle date de 1998'), isNull);
      expect(
        LocalVoiceCommand.match('non pas du tout le séjour fait 40'),
        isNull,
      );
      expect(LocalVoiceCommand.match('cuisine'), isNull);
    });

    test('normalize', () {
      expect(
        LocalVoiceCommand.normalize(' Ça  ÉTAIT  l’œuvre ! '),
        'ca etait l oeuvre',
      );
    });
  });
}
