import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// What the member dialog returns.
class MemberForm {
  const new({
    required this.email,
    required this.role,
    required this.displayName,
    required this.initials,
    this.organisation,
  });

  final String email;
  final StaffRole role;
  final String displayName;
  final String initials;
  final String? organisation;
}

/// Adds a member (e-mail of an existing account) or edits one.
class MemberDialog extends StatefulWidget {
  const new({this.member, super.key});

  final StaffMember? member;

  @override
  State<MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<MemberDialog> {
  late final _email = TextEditingController(text: widget.member?.email);
  late final _name = TextEditingController(text: widget.member?.displayName);
  late final _initials = TextEditingController(text: widget.member?.initials);
  late final _organisation = TextEditingController(
    text: widget.member?.organisation,
  );
  late StaffRole _role = widget.member?.role ?? StaffRole.expert;
  bool _invalid = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _initials.dispose();
    _organisation.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    final name = _name.text.trim();
    final initials = _initials.text.trim().toUpperCase();
    if (!email.contains('@') ||
        name.isEmpty ||
        initials.isEmpty ||
        initials.length > 3) {
      setState(() => _invalid = true);
      return;
    }
    final organisation = _organisation.text.trim();
    Navigator.of(context).pop(
      MemberForm(
        email: email,
        role: _role,
        displayName: name,
        initials: initials,
        organisation: organisation.isEmpty ? null : organisation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const gap = SizedBox(height: RealestySpacing.sm);
    return AlertDialog(
      title: Text(
        widget.member == null ? l10n.teamFormTitleAdd : l10n.teamFormTitleEdit,
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RealestyTextField(
              label: l10n.teamFormEmail,
              controller: _email,
              enabled: widget.member == null,
              keyboardType: TextInputType.emailAddress,
            ),
            gap,
            DropdownButtonFormField<StaffRole>(
              initialValue: _role,
              decoration: InputDecoration(labelText: l10n.teamFormRole),
              items: [
                for (final role in StaffRole.values)
                  DropdownMenuItem(value: role, child: Text(role.label(l10n))),
              ],
              onChanged: (role) => setState(() => _role = role!),
            ),
            gap,
            RealestyTextField(label: l10n.teamFormName, controller: _name),
            gap,
            RealestyTextField(
              label: l10n.teamFormInitials,
              controller: _initials,
            ),
            if (_role == StaffRole.partnerExpert) ...[
              gap,
              RealestyTextField(
                label: l10n.teamFormOrganisation,
                controller: _organisation,
              ),
              gap,
              InlineBanner(
                message: l10n.teamFormPartnerNote,
                variant: InlineBannerVariant.info,
              ),
            ],
            if (_invalid) ...[gap, InlineBanner(message: l10n.teamFormInvalid)],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
