import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/router/routes.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';
import 'package:realesty_backoffice/app/widgets/widgets.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Below this width the back-office shows « Écran trop étroit ».
const minDesktopWidth = 1024.0;

/// Sidebar (Dossiers, Équipe, Journal, account) around the pages.
class BoShell extends StatelessWidget {
  const new({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < minDesktopWidth) {
            return const NarrowScreen();
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(location: location),
              Expanded(child: SelectionArea(child: child)),
            ],
          );
        },
      ),
    );
  }
}

class NarrowScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BoMessage(
    title: context.l10n.narrowScreenTitle,
    body: context.l10n.narrowScreenBody,
  );
}

class _Sidebar extends StatelessWidget {
  const new({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final me = context.select<SessionCubit, StaffMe?>(
      (cubit) => cubit.state.me,
    );
    return Container(
      width: 240,
      color: c.nuit,
      padding: const EdgeInsets.all(RealestySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RealestyLogo(size: 24, onDark: true, showWordmark: true),
          const SizedBox(height: RealestySpacing.xxl),
          _NavItem(
            label: l10n.navQueue,
            icon: RealestyIcons.grid,
            path: BoRoutes.queue,
            selected: location.startsWith(BoRoutes.queue),
          ),
          if (me?.can(BackOfficeCapability.team) ?? false)
            _NavItem(
              label: l10n.navTeam,
              icon: RealestyIcons.users,
              path: BoRoutes.team,
              selected: location.startsWith(BoRoutes.team),
            ),
          if (me?.can(BackOfficeCapability.auditAll) ?? false)
            _NavItem(
              label: l10n.navAudit,
              icon: RealestyIcons.shield,
              path: BoRoutes.audit,
              selected: location.startsWith(BoRoutes.audit),
            ),
          const Spacer(),
          if (me != null) ...[
            Row(
              children: [
                InitialsAvatar(me.initials ?? '', onDark: true),
                const SizedBox(width: RealestySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me.displayName ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: RealestyTextStyles.label.copyWith(
                          color: c.nuitTexte,
                        ),
                      ),
                      Text(
                        me.role?.label(l10n) ?? '',
                        style: RealestyTextStyles.bodySmall.copyWith(
                          color: c.nuitTexteDiscret,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RealestySpacing.md),
          ],
          TextButton(
            onPressed: () => context.read<SessionCubit>().signOut(),
            child: Text(
              l10n.signOut,
              style: RealestyTextStyles.label.copyWith(
                color: c.nuitTexteDiscret,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.path,
    required this.selected,
  });

  final String label;
  final RealestyIcons icon;
  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final color = selected ? c.nuitTexte : c.nuitTexteDiscret;
    return Padding(
      padding: const EdgeInsets.only(bottom: RealestySpacing.xxs),
      child: Material(
        color: selected ? c.nuit2 : Colors.transparent,
        borderRadius: BorderRadius.circular(RealestyRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(RealestyRadius.button),
          onTap: () => context.go(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RealestySpacing.sm,
              vertical: RealestySpacing.sm,
            ),
            child: Row(
              children: [
                RealestyIcon(icon, color: color),
                const SizedBox(width: RealestySpacing.sm),
                Text(
                  label,
                  style: RealestyTextStyles.label.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
