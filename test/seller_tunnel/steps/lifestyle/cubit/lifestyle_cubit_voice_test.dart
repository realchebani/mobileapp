import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _property = Property(id: 'p', ownerId: 'u');

void main() {
  var ids = 0;
  LifestyleCubit build({List<LifestyleItem> items = const []}) =>
      LifestyleCubit(
        propertyRepository: MockPropertyRepository(),
        property: _property,
        items: items,
        newId: () => 'id${ids++}',
      );

  setUp(() => ids = 0);

  test('adds the voice items, noise, overlooking and a suggestion', () async {
    final cubit = build(
      items: const [
        LifestyleItem(
          id: 'a1',
          propertyId: 'p',
          kind: LifestyleItemKind.asset,
          label: 'Calme',
        ),
      ],
    );
    await cubit.voiceTurnApplied(
      const AgentTurn(
        turnId: 't',
        transcript: '',
        reply: '',
        lifestyleItems: [
          AgentLifestyleItem(isAsset: true, label: 'calme'),
          AgentLifestyleItem(isAsset: true, label: ' École proche '),
          AgentLifestyleItem(isAsset: false, label: 'Bus rare'),
          AgentLifestyleItem(isAsset: false, label: 'x'),
        ],
        patch: {'noise_level': 12, 'overlooking': 'leger'},
        suggestions: {'secret_note': ' Vendre avant la rentrée '},
      ),
    );
    final state = cubit.state;
    expect(state.assets.map((a) => a.label), ['Calme', 'École proche']);
    expect(state.assets.last.fromVoice, isTrue);
    expect(state.assets.first.fromVoice, isFalse);
    expect(state.watchPoints.single.label, 'Bus rare');
    expect(
      state.watchPoints.single.toItem(propertyId: 'p', sortOrder: 0).source,
      LifestyleItemSource.voice,
    );
    expect(state.noiseLevel, 10);
    expect(state.overlooking, Overlooking.slight);
    expect(state.secretNoteSuggestion, 'Vendre avant la rentrée');
  });

  test('ignores full lists and unknown values', () async {
    final cubit = build(
      items: [
        for (var i = 0; i < lifestyleItemsMax; i++)
          LifestyleItem(
            id: 'a$i',
            propertyId: 'p',
            kind: LifestyleItemKind.asset,
            label: 'Atout $i',
          ),
      ],
    );
    await cubit.voiceTurnApplied(
      const AgentTurn(
        turnId: 't',
        transcript: '',
        reply: '',
        lifestyleItems: [AgentLifestyleItem(isAsset: true, label: 'Vue mer')],
        patch: {'overlooking': 'x'},
        suggestions: {'secret_note': '  '},
      ),
    );
    expect(cubit.state.assets, hasLength(lifestyleItemsMax));
    expect(cubit.state.overlooking, isNull);
    expect(cubit.state.noiseLevel, isNull);
    expect(cubit.state.secretNoteSuggestion, isNull);
  });

  test('the suggested secret note is used or dismissed', () async {
    final cubit = build()..secretNoteSuggestionUsed(); // nothing to use
    expect(cubit.state.secretNote, '');
    Future<void> suggest(String note) => cubit.voiceTurnApplied(
      AgentTurn(
        turnId: 't',
        transcript: '',
        reply: '',
        suggestions: {'secret_note': note},
      ),
    );
    await suggest('Pressés');
    cubit.secretNoteSuggestionUsed();
    expect(cubit.state.secretNote, 'Pressés');
    expect(cubit.state.secretNoteSuggestion, isNull);
    await suggest('Divorce');
    cubit.secretNoteSuggestionUsed();
    expect(cubit.state.secretNote, 'Pressés\nDivorce');
    await suggest('Autre');
    cubit.secretNoteSuggestionDismissed();
    expect(cubit.state.secretNoteSuggestion, isNull);
    expect(cubit.state.secretNote, 'Pressés\nDivorce');
  });

  test('an edited voice item stays from voice', () {
    const draft = LifestyleItemDraft(
      id: 'i',
      kind: LifestyleItemKind.asset,
      label: 'Calme',
      source: LifestyleItemSource.voice,
    );
    expect(draft.copyWith(label: 'Très calme').fromVoice, isTrue);
    expect(
      LifestyleItemDraft.fromItem(
        const LifestyleItem(
          id: 'i',
          propertyId: 'p',
          kind: LifestyleItemKind.asset,
          label: 'Calme',
          source: LifestyleItemSource.voice,
        ),
      ).fromVoice,
      isTrue,
    );
  });
}
