import 'package:agent_repository/agent_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:property_repository/property_repository.dart';

const _property = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
  constructionYear: 1990,
  stepNotes: {'technical': 'Grenier'},
);

PendingAnswer _answer(
  String id, {
  PendingKind kind = PendingKind.field,
  String? field,
  Object? value,
  String label = 'Label',
}) => PendingAnswer(
  id: id,
  propertyId: 'p',
  targetStep: 'technical',
  kind: kind,
  field: field,
  value: value,
  label: label,
  quote: 'q',
  sourceStep: 'context',
  turnId: 't0',
);

final PendingAnswer _year = _answer(
  'a1',
  field: PropertyColumns.constructionYear,
  value: 1998,
  label: 'Construction 1998',
);
final PendingAnswer _heating = _answer(
  'a2',
  field: PropertyColumns.heatingSystems,
  value: const ['gaz'],
  label: 'Chauffage gaz',
);
final PendingAnswer _note = _answer(
  'a3',
  kind: PendingKind.note,
  value: 'Combles isolés',
  label: 'Note',
);

AgentTurn _turn(String id, {List<String> notes = const []}) =>
    AgentTurn(turnId: id, transcript: '', reply: '', notes: notes);

/// A step form counting the turns it applied.
class _Form implements VoiceForm {
  final applied = <AgentTurn>[];
  final undone = <String>[];
  final pills = <(String, String)>[];
  int undoneFrom = -1;
  bool ignore = false;
  bool prefilled = false;

  @override
  Future<void> voiceTurnApplied(AgentTurn turn) async {
    if (!ignore) applied.add(turn);
  }

  @override
  void undoVoiceTurn(String turnId) => undone.add(turnId);

  @override
  void undoVoicePill(String turnId, String key) => pills.add((turnId, key));

  @override
  int get voiceTurnCount => applied.length;

  @override
  void undoVoiceTurnsFrom(int index) => undoneFrom = index;

  @override
  AgentTurnContext get voiceContext => const AgentTurnContext(draft: {'a': 1});

  @override
  bool confirmPrefilled() => prefilled;
}

void main() {
  final at = DateTime.utc(2026, 10, 2);

  group(StepTraceState, () {
    test('starts from the saved note and the pending answers', () {
      final state = StepTraceState.fromProperty(
        _property,
        noteKey: 'technical',
        pending: [_year, _heating, _note],
      );
      expect(state.notes, 'Grenier · Combles isolés');
      expect(state.savedNotes, 'Grenier');
      expect(state.notesToConfirm, isTrue);
      expect(state.toConfirmLabels, [
        'Construction 1998',
        'Chauffage gaz',
        'Note',
      ]);
      expect(state.prefilledField(PropertyColumns.constructionYear), _year);
      expect(state.prefilledOf(PendingKind.note), [_note]);
      expect(state.toConfirm(PropertyColumns.constructionYear, 1998), isTrue);
      expect(state.toConfirm(PropertyColumns.constructionYear, 1999), isFalse);
      expect(state.toConfirm(PropertyColumns.roofYear, 1999), isFalse);
      expect(state.isConfirmed(PropertyColumns.constructionYear), isFalse);
      final prefilled = state.prefilledProperty(_property);
      expect(prefilled.constructionYear, 1998);
      expect(prefilled.heatingSystems, [HeatingSystem.gas]);
      // Without a note key nor pending answers.
      final bare = StepTraceState.fromProperty(_property, noteKey: null);
      expect(bare.notes, isEmpty);
      expect(bare.prefilledProperty(_property), same(_property));
      final confirmed = state.copyWith(confirmed: {'a1', 'a2', 'a3'});
      expect(confirmed.isConfirmed(PropertyColumns.constructionYear), isTrue);
      expect(
        confirmed.toConfirm(PropertyColumns.constructionYear, 1998),
        isFalse,
      );
      expect(confirmed.notesToConfirm, isFalse);
      expect(confirmed.toConfirmLabels, isEmpty);
      expect(state.props, hasLength(7));
      expect(const StepTraceSave(patch: {'a': 1}).props, [
        {'a': 1},
        <PendingResolution, List<String>>{},
      ]);
    });

    test('a long note is cut to 1 000 characters', () {
      final state = StepTraceState.fromProperty(
        Property(id: 'p', ownerId: 'u', stepNotes: {'rooms': 'x' * 1200}),
        noteKey: 'rooms',
      );
      expect(state.notes, hasLength(1000));
    });

    test('saveFor: origins, notes and resolutions', () {
      final state = StepTraceState.fromProperty(
        _property,
        noteKey: 'technical',
        pending: [
          _year,
          _heating,
          _answer('a4', field: PropertyColumns.roofYear, value: 2010),
          _answer(
            'a5',
            field: PropertyColumns.sanitation,
            value: 'tout_a_l_egout',
          ),
          _answer('a6', field: PropertyColumns.wallMaterial, value: 'pierre'),
          _note,
        ],
      ).copyWith(confirmed: {'a2'});
      final save = state.saveFor(
        property: _property,
        patch: {
          PropertyColumns.currentStep: 5,
          // As said (continuer), confirmed by « oui », said again by voice,
          // erased, typed differently, and an unchanged and a typed column.
          PropertyColumns.constructionYear: 1998,
          PropertyColumns.heatingSystems: [HeatingSystem.gas],
          PropertyColumns.roofYear: 2011,
          PropertyColumns.sanitation: null,
          PropertyColumns.wallMaterial: WallMaterial.brick,
          PropertyColumns.levels: PropertyLevels.singleStorey,
          PropertyColumns.orientation: null,
          PropertyColumns.livingAreaM2: 120.0,
        },
        voiceSource: (column, value) => column == PropertyColumns.roofYear
            ? FieldSource(
                kind: FieldSourceKind.dictated,
                at: at,
                turnId: 't9',
                evidenceKey: column,
              )
            : null,
        now: at,
        kinds: {PropertyColumns.livingAreaM2: FieldSourceKind.extracted},
      );
      expect(save.resolutions, {
        PendingResolution.continueTapped: ['a1', 'a3'],
        PendingResolution.yes: ['a2'],
        PendingResolution.replaced: ['a4'],
        PendingResolution.erased: ['a5'],
        PendingResolution.modified: ['a6'],
      });
      final sources = save.patch[PropertyColumns.fieldSources]! as Map;
      String kind(String column) => (sources[column] as Map)['s'] as String;
      expect(kind(PropertyColumns.constructionYear), 'dicte_autre_etape');
      expect(
        (sources[PropertyColumns.constructionYear] as Map)['c'],
        'continuer',
      );
      expect((sources[PropertyColumns.heatingSystems] as Map)['c'], 'oui');
      expect(kind(PropertyColumns.roofYear), 'dicte');
      expect(kind(PropertyColumns.wallMaterial), 'saisi');
      expect(kind(PropertyColumns.levels), 'saisi');
      expect(kind(PropertyColumns.livingAreaM2), 'extrait');
      expect(sources.containsKey(PropertyColumns.orientation), isFalse);
      expect(sources.containsKey(PropertyColumns.currentStep), isFalse);
      expect(kind('step_notes.technical'), 'dicte_autre_etape');
      expect(save.patch[PropertyColumns.stepNotes], {
        'technical': 'Grenier · Combles isolés',
      });
    });

    test('saveFor: dictated, typed and erased notes', () {
      final dictated =
          const StepTraceState(
            noteKey: 'context',
            notes: 'Vendu meublé',
            dictatedNotes: 'Vendu meublé',
            notesTurnId: 't1',
          ).saveFor(
            property: _property,
            patch: const {},
            voiceSource: (_, _) => null,
            now: at,
          );
      final sources = dictated.patch[PropertyColumns.fieldSources]! as Map;
      expect(sources['step_notes.context'], {
        's': 'dicte',
        't': 't1',
        'k': 'note:0',
        'at': '2026-10-02T00:00:00.000Z',
      });
      final typed = const StepTraceState(noteKey: 'context', notes: 'Tapé')
          .saveFor(
            property: _property,
            patch: const {},
            voiceSource: (_, _) => null,
            now: at,
          );
      expect(
        (typed.patch[PropertyColumns.fieldSources]!
            as Map)['step_notes.context'],
        FieldSource.typed(at).toJson(),
      );
      // The pending note erased (empty notes) or changed (other text).
      final erased =
          StepTraceState(
            noteKey: 'technical',
            prefilled: [_note],
            savedNotes: 'Grenier',
          ).saveFor(
            property: _property,
            patch: const {},
            voiceSource: (_, _) => null,
            now: at,
          );
      expect(erased.resolutions, {
        PendingResolution.erased: ['a3'],
      });
      final changed =
          StepTraceState(
            noteKey: 'technical',
            prefilled: [_note],
            notes: 'Grenier',
            savedNotes: 'Grenier',
            confirmed: const {'a3'},
          ).saveFor(
            property: _property,
            patch: const {},
            voiceSource: (_, _) => null,
            now: at,
          );
      expect(changed.resolutions, {
        PendingResolution.modified: ['a3'],
      });
      expect(changed.patch, isEmpty);
      final kept =
          StepTraceState(
            noteKey: 'technical',
            prefilled: [_note],
            notes: 'Grenier · Combles isolés',
            savedNotes: 'Grenier',
            confirmed: const {'a3'},
          ).saveFor(
            property: _property,
            patch: const {},
            voiceSource: (_, _) => null,
            now: at,
          );
      expect(kept.resolutions, {
        PendingResolution.yes: ['a3'],
      });
    });
  });

  group(StepTraceCubit, () {
    blocTest<StepTraceCubit, StepTraceState>(
      'notes typed are cut to 1 000 characters',
      build: () => StepTraceCubit(const StepTraceState(noteKey: 'rooms')),
      act: (cubit) => cubit.notesChanged('x' * 1001),
      expect: () => [StepTraceState(noteKey: 'rooms', notes: 'x' * 1000)],
    );

    test('appends the notes said, undoes and replays them', () {
      final cubit = StepTraceCubit(
        const StepTraceState(noteKey: 'context', notes: 'Saisi'),
      )..turnApplied(_turn('t1', notes: ['Un']));
      expect(cubit.state.notes, 'Saisi · Un');
      expect(cubit.state.dictatedNotes, 'Saisi · Un');
      expect(cubit.state.notesTurnId, 't1');
      cubit
        ..turnApplied(_turn('t2'))
        ..turnApplied(_turn('t3#c1', notes: ['Deux', 'Trois']));
      expect(cubit.state.notes, 'Saisi · Un · Deux · Trois');
      expect(cubit.state.notesTurnId, 't3');
      // Undo t1, replaying t2 and t3.
      cubit.undoFrom(
        't1',
        replay: [
          _turn('t2'),
          _turn('t3#c1', notes: ['Deux', 'Trois']),
        ],
      );
      expect(cubit.state.notes, 'Saisi · Deux · Trois');
      cubit
        ..undoFrom('unknown')
        ..undoFrom('t2');
      expect(cubit.state.notes, 'Saisi');
      expect(cubit.state.dictatedNotes, isNull);
    });

    test(
      'a step without notes ignores them; closed, nothing changes',
      () async {
        final cubit = StepTraceCubit(const StepTraceState())
          ..turnApplied(_turn('t1', notes: ['Un']));
        expect(cubit.state.notes, isEmpty);
        await cubit.close();
        cubit
          ..turnApplied(_turn('t2'))
          ..undoFrom('t1')
          ..confirmPrefilled();
        expect(cubit.state.confirmed, isEmpty);
      },
    );

    test('confirmPrefilled confirms every pre-filled answer once', () {
      final cubit = StepTraceCubit(StepTraceState(prefilled: [_year, _note]))
        ..confirmPrefilled();
      expect(cubit.state.confirmed, {'a1', 'a3'});
      cubit.confirmPrefilled();
      expect(cubit.state.confirmed, {'a1', 'a3'});
    });
  });

  group(TracedVoiceForm, () {
    test('gives the answers to the form and the notes to the trace', () async {
      final form = _Form();
      final trace = StepTraceCubit(const StepTraceState(noteKey: 'context'));
      final traced = TracedVoiceForm(form: form, trace: trace);
      await traced.voiceTurnApplied(_turn('t1', notes: ['Un', 'Deux']));
      await traced.voiceTurnApplied(_turn('t2', notes: ['Trois']));
      expect(form.applied, hasLength(2));
      expect(traced.voiceTurnCount, 2);
      expect(trace.state.notes, 'Un · Deux · Trois');
      expect(traced.voiceContext.draft, {'a': 1});
      // A note pill: the trace only.
      traced.undoVoicePill('t1', 'note:0');
      expect(trace.state.notes, 'Deux · Trois');
      expect(form.pills, isEmpty);
      traced
        ..undoVoicePill('unknown', 'note:0')
        ..undoVoicePill('t1', 'purchase_year');
      expect(form.pills, [('t1', 'purchase_year')]);
      // A whole turn.
      traced.undoVoiceTurn('t1');
      expect(form.undone, ['t1']);
      expect(trace.state.notes, 'Trois');
      traced.undoVoiceTurn('unknown');
      expect(form.undone, ['t1', 'unknown']);
      // The session.
      traced.undoVoiceTurnsFrom(0);
      expect(form.undoneFrom, 0);
      expect(trace.state.notes, isEmpty);
      traced.undoVoiceTurnsFrom(5);
      expect(form.undoneFrom, 5);
    });

    test('a turn ignored by the form is ignored here too', () async {
      final form = _Form()..ignore = true;
      final trace = StepTraceCubit(const StepTraceState(noteKey: 'context'));
      await TracedVoiceForm(
        form: form,
        trace: trace,
      ).voiceTurnApplied(_turn('t1', notes: ['Un']));
      expect(trace.state.notes, isEmpty);
    });

    test('confirmPrefilled: the trace first, then the form', () {
      final form = _Form()..prefilled = true;
      final traced = TracedVoiceForm(
        form: form,
        trace: StepTraceCubit(StepTraceState(prefilled: [_year])),
      );
      expect(traced.confirmPrefilled(), isTrue);
      expect(form.prefilled, isTrue);
      expect(traced.confirmPrefilled(), isTrue);
    });
  });
}
