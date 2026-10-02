import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

const _note = PendingAnswer(
  id: 'n',
  propertyId: 'p',
  targetStep: 'context',
  kind: PendingKind.note,
  value: 'Vendu meublé',
  label: 'Note',
  quote: 'vendu meublé',
  sourceStep: 'technical',
);

const _year = PendingAnswer(
  id: 'y',
  propertyId: 'p',
  targetStep: 'context',
  kind: PendingKind.field,
  field: 'purchase_year',
  value: 2012,
  label: 'Achat 2012',
  quote: 'en 2012',
  sourceStep: 'technical',
);

/// EPIC-16: « Notes complémentaires » and the voice tags of a step.
void main() {
  Future<StepTraceCubit> pump(
    WidgetTester tester,
    StepTraceState state, {
    Widget Function(BuildContext context)? extra,
  }) async {
    final trace = StepTraceCubit(state);
    await tester.pumpTunnelPage(
      BlocProvider.value(
        value: trace,
        child: Scaffold(
          body: Column(
            children: [
              const StepNotesField(),
              if (extra != null) Builder(builder: extra),
            ],
          ),
        ),
      ),
    );
    return trace;
  }

  testWidgets('typed, dictated, or holding a note said elsewhere', (
    tester,
  ) async {
    final trace = await pump(
      tester,
      const StepTraceState(
        noteKey: 'context',
        notes: 'Vendu meublé',
        prefilled: [_note],
      ),
    );
    expect(find.text('Notes complémentaires (facultatif)'), findsOneWidget);
    expect(find.byType(ToConfirmTag), findsOneWidget);
    // A voice turn appends: the field follows, « Dicté ».
    trace.turnApplied(
      const AgentTurn(turnId: 't1', transcript: '', reply: '', notes: ['Cave']),
    );
    await tester.pump();
    expect(find.text('Vendu meublé · Cave'), findsOneWidget);
    trace.confirmPrefilled();
    await tester.pump();
    await tester.pump();
    expect(find.byType(DictatedTag), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Tapé');
    await tester.pump();
    await tester.pump();
    expect(trace.state.notes, 'Tapé');
    expect(find.byType(DictatedTag), findsNothing);
  });

  testWidgets('hidden on a step without notes', (tester) async {
    await pump(tester, const StepTraceState());
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tagOf: « À confirmer », then « Dicté » once confirmed', (
    tester,
  ) async {
    final trace = await pump(
      tester,
      const StepTraceState(prefilled: [_year]),
      extra: (context) => Column(
        children: [
          ?StepVoiceFirst.tagOf(
            context,
            'purchase_year',
            2012,
            dictated: false,
          ),
          ?StepVoiceFirst.tagOf(
            context,
            'purchase_price_eur',
            1,
            dictated: true,
          ),
          ?StepVoiceFirst.tagOf(context, 'sale_reason', null, dictated: false),
        ],
      ),
    );
    expect(find.byType(ToConfirmTag), findsOneWidget);
    expect(find.byType(DictatedTag), findsOneWidget);
    trace.confirmPrefilled();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ToConfirmTag), findsNothing);
    expect(find.byType(DictatedTag), findsNWidgets(2));
  });
}
