import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// The choice of the assignment dialog: a member ([userId]) or none (remove
/// the assignment).
class AssignChoice {
  const new({this.userId, this.note});

  final String? userId;
  final String? note;
}

Future<AssignChoice?> showAssignDialog(
  BuildContext context, {
  required List<StaffMember> team,
  String? current,
}) => showDialog<AssignChoice>(
  context: context,
  builder: (_) => AssignDialog(team: team, current: current),
);

class AssignDialog extends StatefulWidget {
  const new({required this.team, this.current, super.key});

  final List<StaffMember> team;
  final String? current;

  @override
  State<AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<AssignDialog> {
  late String? _selected = widget.current;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return AlertDialog(
      title: Text(l10n.assignTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assignBody,
              style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
            ),
            const SizedBox(height: RealestySpacing.md),
            if (widget.team.isEmpty) Text(l10n.assignNoTeam),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (value) => setState(() => _selected = value),
              child: Column(
                children: [
                  for (final member in widget.team)
                    RadioListTile<String>(
                      value: member.userId,
                      title: Text(member.displayName),
                      subtitle: Text(
                        [
                          member.role.label(l10n),
                          ?member.organisation,
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RealestySpacing.sm),
            RealestyTextField(label: l10n.assignNote, controller: _note),
          ],
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const AssignChoice()),
            child: Text(l10n.assignRemove),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(
                  AssignChoice(
                    userId: _selected,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ),
                ),
          child: Text(l10n.queueAssign),
        ),
      ],
    );
  }
}
