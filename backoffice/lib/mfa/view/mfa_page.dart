import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/login/login.dart';
import 'package:realesty_backoffice/mfa/cubit/mfa_cubit.dart';
import 'package:realesty_ui/realesty_ui.dart';

class MfaPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = MfaCubit(
          auth: context.read(),
          factorId: context.read<SessionCubit>().state.mfa?.factorId,
        );
        unawaited(cubit.start());
        return cubit;
      },
      child: const MfaView(),
    );
  }
}

class MfaView extends StatelessWidget {
  const new({super.key});

  Future<void> _verify(BuildContext context) async {
    final session = context.read<SessionCubit>();
    if (await context.read<MfaCubit>().verify()) await session.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<MfaCubit>().state;
    final enrollment = state.enrollment;
    final body = RealestyTextStyles.bodySmall.copyWith(color: c.encre2);
    final error = switch (state.status) {
      MfaStatusValue.invalidCode => l10n.mfaInvalidCode,
      MfaStatusValue.failure => l10n.mfaError,
      _ => null,
    };
    return GateCard(
      title: l10n.mfaTitle,
      children: [
        Text(
          enrollment == null && state.factorId != null
              ? l10n.mfaVerifyBody
              : l10n.mfaEnrollBody,
          style: body,
        ),
        if (enrollment != null) ...[
          const SizedBox(height: RealestySpacing.lg),
          Center(
            child: SvgPicture.string(
              enrollment.qrCodeSvg,
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: RealestySpacing.sm),
          Text(l10n.mfaSecretLabel, style: body),
          SelectableText(
            enrollment.secret,
            style: RealestyTextStyles.label.copyWith(letterSpacing: 1.5),
          ),
        ],
        if (state.factorId == null &&
            state.status == MfaStatusValue.failure) ...[
          const SizedBox(height: RealestySpacing.md),
          RealestyButton(
            label: l10n.mfaStartEnroll,
            onPressed: context.read<MfaCubit>().start,
          ),
        ] else if (state.factorId != null) ...[
          const SizedBox(height: RealestySpacing.lg),
          RealestyTextField(
            label: l10n.mfaCodeLabel,
            leadingIcon: RealestyIcons.lock,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            autofocus: true,
            enabled: !state.isBusy,
            onChanged: context.read<MfaCubit>().codeChanged,
            onSubmitted: (_) => _verify(context),
          ),
          const SizedBox(height: RealestySpacing.md),
          RealestyButton(
            label: l10n.mfaSubmit,
            isLoading: state.isBusy,
            onPressed: () => _verify(context),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: RealestySpacing.md),
          InlineBanner(message: error),
        ],
        const SizedBox(height: RealestySpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.read<SessionCubit>().signOut(),
            child: Text(l10n.signOut),
          ),
        ),
      ],
    );
  }
}
