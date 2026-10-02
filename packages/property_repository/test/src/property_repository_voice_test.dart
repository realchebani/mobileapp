import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:property_repository/property_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 2, 10);

  group('FieldSource', () {
    test('round-trips and merges', () {
      final source = FieldSource(
        kind: FieldSourceKind.dictatedElsewhere,
        at: at,
        turnId: 't1',
        evidenceKey: 'x:0',
        pendingId: 'p1',
        confirmation: FieldConfirmation.yes,
      );
      expect(source.toJson(), {
        's': 'dicte_autre_etape',
        't': 't1',
        'k': 'x:0',
        'p': 'p1',
        'c': 'oui',
        'at': '2026-10-02T10:00:00.000Z',
      });
      expect(FieldSource.tryParse(source.toJson()), source);
      expect(FieldSource.typed(at).toJson(), {
        's': 'saisi',
        'at': '2026-10-02T10:00:00.000Z',
      });
      expect(FieldSource.tryParse('x'), isNull);
      expect(FieldSource.tryParse({'s': 'nope', 'at': '2026'}), isNull);
      expect(FieldSource.tryParse({'s': 'saisi', 'at': 'x'}), isNull);
      expect(FieldSource.tryParse({'s': 'saisi', 'at': 3}), isNull);
      expect(
        mergeFieldSourceMaps({'a': 1, 'b': 2}, {'b': FieldSource.typed(at)}),
        {'a': 1, 'b': FieldSource.typed(at).toJson()},
      );
      expect(StepNoteKeys.all, hasLength(5));
      expect(StepNoteKeys.sourceKey('rooms'), 'step_notes.rooms');
    });
  });

  group('Property', () {
    test('reads and writes the step notes and the field sources', () {
      final property = Property.fromJson({
        'id': 'p',
        'owner_id': 'o',
        'step_notes': const {'context': 'Vendu meublé', 'bad': 3},
        'field_sources': {'purchase_year': FieldSource.typed(at).toJson()},
      });
      expect(property.stepNotes, {'context': 'Vendu meublé'});
      expect(property.stepNoteOf('context'), 'Vendu meublé');
      expect(property.stepNoteOf('rooms'), isNull);
      expect(property.fieldSourceOf('purchase_year'), FieldSource.typed(at));
      expect(property.fieldSourceOf('roof_year'), isNull);
      expect(property.withStepNote('rooms', ' Combles '), {
        'context': 'Vendu meublé',
        'rooms': 'Combles',
      });
      expect(property.withStepNote('context', '  '), isEmpty);
      expect(property.withStepNote('context', null), isEmpty);
      expect(
        property.mergeFieldSources({'roof_year': FieldSource.typed(at)}),
        hasLength(2),
      );
      expect(property.toJson()['step_notes'], property.stepNotes);
      expect(property.toJson()['field_sources'], property.fieldSources);
      const empty = Property(id: 'p', ownerId: 'o');
      expect(Property.fromJson(const {'id': 'p', 'owner_id': 'o'}), empty);
    });
  });

  group('children', () {
    test('keep their field sources and send them only when known', () {
      final sources = {'name': FieldSource.typed(at).toJson()};
      final room = Room.fromJson({
        'property_id': 'p',
        'name': 'Séjour',
        'area_m2': 20,
        'field_sources': sources,
      });
      expect(room.fieldSources, sources);
      expect(room.toJson()['field_sources'], sources);
      expect(Room.descriptionMaxLength, 600);
      const bare = Room(propertyId: 'p', name: 'S', areaM2: 1);
      expect(bare.toJson().containsKey('field_sources'), isFalse);

      final estimate = PreviousEstimate.fromJson({
        'property_id': 'p',
        'price_eur': 300000,
        'source': 'voice',
        'field_sources': sources,
      });
      expect(estimate.source, EstimateSource.voice);
      expect(estimate.toJson()['source'], 'voice');
      expect(estimate.toJson()['field_sources'], sources);
      expect(
        PreviousEstimate.fromJson(const {'property_id': 'p', 'price_eur': 1})
            .source,
        EstimateSource.manual,
      );

      final item = LifestyleItem.fromJson({
        'property_id': 'p',
        'kind': 'asset',
        'label': 'Calme',
        'field_sources': sources,
      });
      expect(item.fieldSources, sources);
      expect(item.toJson()['field_sources'], sources);
      expect(item.props, hasLength(7));
      expect(estimate.props, hasLength(7));
    });
  });

  group('PendingAnswer', () {
    test('parses a row', () {
      final answer = PendingAnswer.fromJson(const {
        'id': 'a1',
        'property_id': 'p',
        'target_step': 'technical',
        'kind': 'room',
        'value': {'name': 'Cuisine', 'area_m2': 12},
        'label_fr': 'Cuisine · 12 m²',
        'changed_fr': null,
        'quote': 'la cuisine fait 12',
        'confidence': 0.6,
        'source_step': 'context',
        'turn_id': 't1',
        'status': 'pending',
        'created_at': '2026-10-02T10:00:00Z',
      });
      expect(answer.kind, PendingKind.room);
      expect(answer.values, {'name': 'Cuisine', 'area_m2': 12});
      expect(answer.unsure, isTrue);
      expect(answer.createdAt, at);
      expect(answer.props, hasLength(14));
      final minimal = PendingAnswer.fromJson(const {
        'id': 'a2',
        'property_id': 'p',
        'target_step': 'context',
        'kind': 'nope',
        'field': 'purchase_year',
        'value': 2012,
        'status': 'nope',
      });
      expect(minimal.kind, PendingKind.note);
      expect(minimal.status, PendingStatus.pending);
      expect(minimal.values, isEmpty);
      expect(minimal.unsure, isFalse);
      expect(minimal.label, '');
      expect(minimal.quote, '');
      expect(minimal.sourceStep, '');
    });

    test('resolutions give their status', () {
      expect(PendingResolution.continueTapped.status, PendingStatus.accepted);
      expect(PendingResolution.yes.status, PendingStatus.accepted);
      expect(PendingResolution.no.status, PendingStatus.rejected);
      expect(PendingResolution.modified.status, PendingStatus.rejected);
      expect(PendingResolution.erased.status, PendingStatus.rejected);
      expect(PendingResolution.cancelled.status, PendingStatus.rejected);
      expect(PendingResolution.replaced.status, PendingStatus.superseded);
      expect(PendingResolution.submitted.status, PendingStatus.expired);
    });
  });

  group('repository', () {
    late List<http.Request> requests;
    late http.Request current;
    late http.Response Function(http.Request) respond;
    late SupabaseClient client;
    late PropertyRepository repository;

    http.Response json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: current,
    );

    setUp(() {
      requests = [];
      client = SupabaseClient(
        'https://project.supabase.co',
        'publishable-key',
        httpClient: MockClient((request) async {
          requests.add(current = request);
          return respond(request);
        }),
      );
      repository = PropertyRepository(client: client);
    });

    tearDown(() => client.dispose());

    test('getPendingAnswers lists the open answers', () async {
      respond = (_) => json([
        {
          'id': 'a1',
          'property_id': 'p',
          'target_step': 'technical',
          'kind': 'field',
          'field': 'construction_year',
          'value': 1998,
          'label_fr': 'Construction 1998',
          'quote': '1998',
          'source_step': 'context',
          'status': 'pending',
        },
      ]);
      final answers = await repository.getPendingAnswers('p');
      expect(answers.single.field, 'construction_year');
      final query = requests.single.url.queryParameters;
      expect(query['property_id'], 'eq.p');
      expect(query['status'], 'eq.pending');
      respond = (_) => json({'message': 'x'}, status: 500);
      await expectLater(
        repository.getPendingAnswers('p'),
        throwsA(isA<PropertyLoadFailure>()),
      );
    });

    test('resolvePendingAnswers closes only open answers', () async {
      expect(
        await repository.resolvePendingAnswers(const [], PendingResolution.yes),
        isEmpty,
      );
      expect(requests, isEmpty);
      respond = (_) => json([
        {'id': 'a1'},
      ]);
      final ids = await repository.resolvePendingAnswers(const [
        'a1',
        'a2',
      ], PendingResolution.modified);
      expect(ids, ['a1']);
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(jsonDecode(request.body), {
        'status': 'rejected',
        'resolution': 'modifie',
      });
      expect(request.url.queryParameters['status'], 'eq.pending');
      expect(request.url.queryParameters['id'], 'in.("a1","a2")');
      respond = (_) => json({'message': 'x'}, status: 500);
      await expectLater(
        repository.resolvePendingAnswers(const ['a1'], PendingResolution.yes),
        throwsA(isA<PropertySaveFailure>()),
      );
    });
  });
}
