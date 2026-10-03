import 'package:equatable/equatable.dart';

/// {@template validation_error}
/// A validation error of a valuation draft: [path] (`value_eur`,
/// `comparables[0].street`…) and [code] (`required`, `not_integer`,
/// `out_of_range`, `not_number`, `not_text`, `too_long`, `not_bool`,
/// `invalid_choice`, `invalid_date`, `invalid_uuid`, `unknown_field`,
/// `range_order`, `not_list`, `too_many`, `not_object`, `street_number`;
/// from the database only: `unknown_signatory`).
/// {@endtemplate}
class ValidationError extends Equatable {
  /// {@macro validation_error}
  const new(this.path, this.code);

  final String path;
  final String code;

  /// Errors from the JSON list returned by `bo_validate_draft`.
  static List<ValidationError> listFrom(Object? json) => [
    if (json is List)
      for (final item in json)
        if (item is Map)
          ValidationError('${item['path'] ?? ''}', '${item['code'] ?? ''}'),
  ];

  Map<String, String> toJson() => {'path': path, 'code': code};

  @override
  List<Object?> get props => [path, code];

  @override
  String toString() => '$path: $code';
}

/// The rules of `_bo_valuation_errors` (migration `*_back_office.sql`), in
/// pure Dart so the form shows the same errors as the database. Parity
/// fixture: `supabase/functions/tests/fixtures/valuation_drafts.json`.
abstract final class ValuationDraftValidator {
  static const maxEur = 100000000;
  static const minEur = 1000;
  static const maxListItems = 50;

  /// Top-level keys of a draft.
  static const fields = [
    'value_eur',
    'low_eur',
    'high_eur',
    'price_m2_eur',
    'estimated_delay_weeks',
    'valid_until',
    'expert_user_id',
    'expert_display_name',
    'expert_initials',
    'method_steps',
    'reasons',
    'delay_curve',
    'expert_quote',
    'description',
    'technical_sheet',
    'comparables',
    'comparables_note',
    'competitors_summary',
    'competitors',
    'risks_note',
    'adjustments',
    'method_summary',
    'works_label',
    'works_estimate_eur',
    'sources',
  ];

  /// Lists of a draft and the keys of their items.
  static const listItemKeys = {
    'method_steps': ['label', 'detail', 'amount_eur', 'is_delta'],
    'reasons': ['text', 'positive'],
    'delay_curve': ['price_eur', 'label'],
    'technical_sheet': ['label', 'value', 'provenance'],
    'comparables': [
      'street',
      'sold_on',
      'area_m2',
      'land_m2',
      'price_eur',
      'excluded',
    ],
    'competitors': ['label', 'price_eur', 'note', 'days_online', 'retained'],
    'adjustments': ['label', 'amount_eur', 'kind'],
    'method_summary': ['label', 'amount_eur', 'kind'],
  };

  static const provenances = ['declared', 'document', 'external', 'verified'];
  static const lineKinds = ['base', 'line', 'total', 'control'];

  static final _uuid = RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );
  static final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _blank = RegExp(r'^ *$');
  static final _leadingDigit = RegExp('^ *[0-9]');

  /// Errors of [payload]; empty when the draft can be certified.
  static List<ValidationError> validate(Object? payload) {
    final p = payload ?? const <String, dynamic>{};
    if (p is! Map) return const [ValidationError('', 'not_object')];
    final e = <ValidationError>[
      ..._keys('', p, fields),
      ..._int('value_eur', p['value_eur'], required: true, min: minEur),
      ..._int('low_eur', p['low_eur'], required: true, min: minEur),
      ..._int('high_eur', p['high_eur'], required: true, min: minEur),
      ..._int('price_m2_eur', p['price_m2_eur'], min: 1, max: 1000000),
      ..._int(
        'estimated_delay_weeks',
        p['estimated_delay_weeks'],
        min: 1,
        max: 104,
      ),
      ..._int('works_estimate_eur', p['works_estimate_eur'], min: 0),
      ..._dateOf('valid_until', p['valid_until']),
      ..._text('expert_display_name', p['expert_display_name'], max: 100),
      ..._text('expert_initials', p['expert_initials'], max: 3),
      ..._text('expert_quote', p['expert_quote'], max: 2000),
      ..._text('description', p['description'], max: 4000),
      ..._text('comparables_note', p['comparables_note'], max: 1000),
      ..._text('competitors_summary', p['competitors_summary'], max: 500),
      ..._text('risks_note', p['risks_note'], max: 1000),
      ..._text('works_label', p['works_label'], max: 200),
      ..._text('sources', p['sources'], max: 1000),
    ];

    final expert = p['expert_user_id'];
    if (expert != null && !(expert is String && _uuid.hasMatch(expert))) {
      e.add(const ValidationError('expert_user_id', 'invalid_uuid'));
    }

    final value = p['value_eur'];
    final low = p['low_eur'];
    final high = p['high_eur'];
    if (value is num && low is num && high is num) {
      if (!(low <= value && value <= high)) {
        e.add(const ValidationError('value_eur', 'range_order'));
      }
    }

    for (final MapEntry(key: list, value: keys) in listItemKeys.entries) {
      final items = p[list];
      if (items == null) continue;
      if (items is! List) {
        e.add(ValidationError(list, 'not_list'));
        continue;
      }
      if (items.length > maxListItems) {
        e.add(ValidationError(list, 'too_many'));
        continue;
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final at = '$list[$i].';
        if (item is! Map) {
          e.add(ValidationError('$list[$i]', 'not_object'));
          continue;
        }
        e
          ..addAll(_keys(at, item, keys))
          ..addAll(_item(list, at, item));
      }
    }
    return e;
  }

  static List<ValidationError> _item(
    String list,
    String at,
    Map<dynamic, dynamic> v,
  ) => switch (list) {
    'method_steps' => [
      ..._text('${at}label', v['label'], required: true, max: 120),
      ..._text('${at}detail', v['detail'], max: 200),
      ..._int('${at}amount_eur', v['amount_eur'], required: true, min: -maxEur),
      ..._bool('${at}is_delta', v['is_delta']),
    ],
    'reasons' => [
      ..._text('${at}text', v['text'], required: true, max: 300),
      ..._bool('${at}positive', v['positive']),
    ],
    'delay_curve' => [
      ..._int('${at}price_eur', v['price_eur'], required: true, min: minEur),
      ..._text('${at}label', v['label'], required: true, max: 60),
    ],
    'technical_sheet' => [
      ..._text('${at}label', v['label'], required: true, max: 60),
      ..._text('${at}value', v['value'], required: true, max: 200),
      ..._choice('${at}provenance', v['provenance'], provenances),
    ],
    'comparables' => [
      ..._text('${at}street', v['street'], required: true, max: 120),
      ..._dateOf('${at}sold_on', v['sold_on']),
      ..._num('${at}area_m2', v['area_m2'], min: 1, max: 100000),
      ..._int('${at}land_m2', v['land_m2'], min: 0),
      ..._int('${at}price_eur', v['price_eur'], required: true, min: minEur),
      ..._bool('${at}excluded', v['excluded']),
      if (v['street'] case final String street
          when _leadingDigit.hasMatch(street))
        ValidationError('${at}street', 'street_number'),
    ],
    'competitors' => [
      ..._text('${at}label', v['label'], required: true, max: 120),
      ..._int('${at}price_eur', v['price_eur'], min: minEur),
      ..._text('${at}note', v['note'], max: 300),
      ..._int('${at}days_online', v['days_online'], min: 0, max: 3650),
      ..._bool('${at}retained', v['retained']),
    ],
    _ => [
      ..._text('${at}label', v['label'], required: true, max: 200),
      ..._int('${at}amount_eur', v['amount_eur'], required: true, min: -maxEur),
      ..._choice('${at}kind', v['kind'], lineKinds),
    ],
  };

  static List<ValidationError> _keys(
    String prefix,
    Map<dynamic, dynamic> object,
    List<String> allowed,
  ) {
    final unknown = [
      for (final key in object.keys)
        if (!allowed.contains(key)) '$key',
    ]..sort();
    return [
      for (final key in unknown)
        ValidationError('$prefix$key', 'unknown_field'),
    ];
  }

  static List<ValidationError> _int(
    String path,
    Object? value, {
    required num min,
    bool required = false,
    num max = maxEur,
  }) {
    if (value == null) {
      return required ? [ValidationError(path, 'required')] : const [];
    }
    if (value is! num || value != value.truncate()) {
      return [ValidationError(path, 'not_integer')];
    }
    if (value < min || value > max) {
      return [ValidationError(path, 'out_of_range')];
    }
    return const [];
  }

  static List<ValidationError> _num(
    String path,
    Object? value, {
    required num min,
    required num max,
  }) {
    if (value == null) return const [];
    if (value is! num) return [ValidationError(path, 'not_number')];
    if (value < min || value > max) {
      return [ValidationError(path, 'out_of_range')];
    }
    return const [];
  }

  static List<ValidationError> _text(
    String path,
    Object? value, {
    required int max,
    bool required = false,
  }) {
    if (value == null || (value is String && _blank.hasMatch(value))) {
      return required ? [ValidationError(path, 'required')] : const [];
    }
    if (value is! String) return [ValidationError(path, 'not_text')];
    if (value.runes.length > max) return [ValidationError(path, 'too_long')];
    return const [];
  }

  static List<ValidationError> _bool(String path, Object? value) =>
      value == null || value is bool
      ? const []
      : [ValidationError(path, 'not_bool')];

  static List<ValidationError> _choice(
    String path,
    Object? value,
    List<String> choices,
  ) => value == null || (value is String && choices.contains(value))
      ? const []
      : [ValidationError(path, 'invalid_choice')];

  static List<ValidationError> _dateOf(String path, Object? value) {
    if (value == null) return const [];
    if (value is String) {
      final match = _date.firstMatch(value);
      if (match != null) {
        final year = int.parse(match[1]!);
        final month = int.parse(match[2]!);
        final day = int.parse(match[3]!);
        final date = DateTime.utc(year, month, day);
        if (year >= 1 &&
            date.year == year &&
            date.month == month &&
            date.day == day) {
          return const [];
        }
      }
    }
    return [ValidationError(path, 'invalid_date')];
  }
}
