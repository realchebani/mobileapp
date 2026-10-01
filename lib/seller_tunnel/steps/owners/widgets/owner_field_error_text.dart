import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';

/// The message of an [OwnerFieldError].
extension OwnerFieldErrorText on OwnerFieldError {
  String message(AppLocalizations l10n) => switch (this) {
    OwnerFieldError.required => l10n.ownersErrorRequired,
    OwnerFieldError.invalidPhone => l10n.ownersErrorPhone,
    OwnerFieldError.invalidEmail => l10n.ownersErrorEmail,
  };
}
