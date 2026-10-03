import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';

/// French message of a validation error code.
String validationMessage(AppLocalizations l10n, String code) => switch (code) {
  'required' => l10n.errRequired,
  'not_integer' => l10n.errNotInteger,
  'not_number' => l10n.errNotNumber,
  'out_of_range' => l10n.errOutOfRange,
  'not_text' => l10n.errNotText,
  'too_long' => l10n.errTooLong,
  'not_bool' => l10n.errNotBool,
  'invalid_choice' => l10n.errInvalidChoice,
  'invalid_date' => l10n.errInvalidDate,
  'invalid_uuid' => l10n.errInvalidUuid,
  'range_order' => l10n.errRangeOrder,
  'not_list' => l10n.errNotList,
  'too_many' => l10n.errTooMany,
  'not_object' => l10n.errNotObject,
  'street_number' => l10n.errStreetNumber,
  _ => l10n.errUnknownField,
};

/// The first error message at [path], if any.
String? errorAt(
  AppLocalizations l10n,
  List<ValidationError> errors,
  String path,
) {
  for (final error in errors) {
    if (error.path == path) return validationMessage(l10n, error.code);
  }
  return null;
}
