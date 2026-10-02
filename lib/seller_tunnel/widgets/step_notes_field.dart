import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// « Notes complémentaires » of a step (EPIC-16): what fits no field,
/// typed or dictated (appended by the voice sheet), up to 1 000
/// characters. Bound to the [StepTraceCubit] above; « Dicté » when the
/// text is the one said, « À confirmer » when it holds a note said on
/// another step.
class StepNotesField extends StatefulWidget {
  const new({this.enabled = true, super.key});

  final bool enabled;

  @override
  State<StepNotesField> createState() => _StepNotesFieldState();
}

class _StepNotesFieldState extends State<StepNotesField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<StepTraceCubit>().state.notes,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trace = context.watch<StepTraceCubit>().state;
    if (trace.noteKey == null) return const SizedBox.shrink();
    final dictated =
        trace.dictatedNotes != null && trace.notes == trace.dictatedNotes;
    final Widget? tag = trace.notesToConfirm
        ? ToConfirmTag(
            quote: trace.prefilledOf(PendingKind.note).firstOrNull?.quote,
          )
        : dictated
        ? const DictatedTag()
        : null;
    return BlocListener<StepTraceCubit, StepTraceState>(
      // A voice turn (or its undo) changed the notes: the field follows.
      listenWhen: (previous, current) => previous.notes != current.notes,
      listener: (context, state) {
        if (_controller.text != state.notes) _controller.text = state.notes;
      },
      child: RealestyTextField(
        label: l10n.stepNotesLabel,
        hint: l10n.stepNotesHint,
        controller: _controller,
        enabled: widget.enabled,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        inputFormatters: [
          LengthLimitingTextInputFormatter(StepNoteKeys.maxLength),
        ],
        onChanged: context.read<StepTraceCubit>().notesChanged,
        footer: tag,
      ),
    );
  }
}
