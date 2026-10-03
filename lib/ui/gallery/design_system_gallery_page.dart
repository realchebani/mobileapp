import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/action_card.dart';
import 'package:mobileapp/ui/components/agent_chat.dart';
import 'package:mobileapp/ui/components/hero_value_card.dart';
import 'package:mobileapp/ui/components/initials_avatar.dart';
import 'package:mobileapp/ui/components/inline_banner.dart';
import 'package:mobileapp/ui/components/key_value_row.dart';
import 'package:mobileapp/ui/components/offer_plan_card.dart';
import 'package:mobileapp/ui/components/price_range_slider.dart';
import 'package:mobileapp/ui/components/provenance_tag.dart';
import 'package:mobileapp/ui/components/realesty_badge.dart';
import 'package:mobileapp/ui/components/realesty_button.dart';
import 'package:mobileapp/ui/components/realesty_checkbox.dart';
import 'package:mobileapp/ui/components/realesty_choice_chip.dart';
import 'package:mobileapp/ui/components/realesty_icon_button.dart';
import 'package:mobileapp/ui/components/realesty_list_item.dart';
import 'package:mobileapp/ui/components/realesty_segmented_control.dart';
import 'package:mobileapp/ui/components/realesty_select.dart';
import 'package:mobileapp/ui/components/realesty_snack_bar.dart';
import 'package:mobileapp/ui/components/realesty_stepper.dart';
import 'package:mobileapp/ui/components/realesty_switch.dart';
import 'package:mobileapp/ui/components/realesty_tab_bar.dart';
import 'package:mobileapp/ui/components/realesty_text_field.dart';
import 'package:mobileapp/ui/components/segmented_progress.dart';
import 'package:mobileapp/ui/components/signature_pad.dart';
import 'package:mobileapp/ui/format/realesty_format.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/logo/realesty_logo.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Developer page showing every token and component of the design system.
class DesignSystemGalleryPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DesignSystemGalleryPage> createState() =>
      _DesignSystemGalleryPageState();
}

class _DesignSystemGalleryPageState extends State<DesignSystemGalleryPage> {
  late final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => _toast('Conditions générales');

  Timer? _loadingTimer;
  bool _loading = false;
  bool _checked = true;
  bool _unchecked = false;
  bool _chipGarden = true;
  bool _chipGarage = false;
  String _segment = 'maison';
  int _rooms = 3;
  String? _propertyType;
  int _tab = 0;
  bool _retouch = true;
  int _price = 525000;
  final _signature = SignaturePadController();

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _signature.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _startLoading() {
    setState(() => _loading = true);
    _loadingTimer = Timer(const Duration(seconds: 2), () {
      setState(() => _loading = false);
    });
  }

  void _toast(String message, {bool isError = false}) =>
      showRealestySnackBar(context, message, isError: isError);

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.md,
          RealestySpacing.gutter,
          RealestySpacing.xxxl,
        ),
        children: [
          const _Section('Logo'),
          Wrap(
            spacing: RealestySpacing.md,
            runSpacing: RealestySpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const RealestyLogo(size: 72),
              const RealestyLogo(size: 26, showWordmark: true),
              const RealestyLogo(showWordmark: true),
              Container(
                padding: const EdgeInsets.all(RealestySpacing.sm),
                color: c.nuit,
                child: const RealestyLogo(onDark: true),
              ),
            ],
          ),
          const _Section('Couleurs'),
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xs,
            children: [
              for (final (name, color) in _swatches(c))
                _Swatch(name: name, color: color),
            ],
          ),
          const _Section('Typographie'),
          const Text('Display', style: RealestyTextStyles.display),
          const Text('Titre 1', style: RealestyTextStyles.title1),
          const Text('Titre 2', style: RealestyTextStyles.title2),
          Text(
            '${frenchNumber(525000)}$noBreakSpace€',
            style: RealestyTextStyles.keyFigure,
          ),
          const Text('Corps — texte courant', style: RealestyTextStyles.body),
          const Text(
            'Corps S — texte secondaire',
            style: RealestyTextStyles.bodySmall,
          ),
          const Text('Libellé', style: RealestyTextStyles.label),
          const Text('LÉGENDE', style: RealestyTextStyles.caption),
          const _Section('Icônes'),
          Wrap(
            spacing: RealestySpacing.md,
            runSpacing: RealestySpacing.md,
            children: [
              for (final icon in RealestyIcons.values)
                Tooltip(
                  message: icon.fileName,
                  child: RealestyIcon(icon, size: 22),
                ),
            ],
          ),
          const _Section('Boutons'),
          ..._spaced([
            RealestyButton(
              label: 'Continuer',
              onPressed: () => _toast('Continuer'),
            ),
            RealestyButton(
              label: 'Parler à l’agent',
              variant: RealestyButtonVariant.accent,
              leadingIcon: RealestyIcons.mic,
              height: 56,
              onPressed: () => _toast('Accent'),
            ),
            RealestyButton(
              label: 'Envoyer mon dossier',
              variant: RealestyButtonVariant.accent,
              trailingIcon: RealestyIcons.chevronRight,
              onPressed: () => _toast('Icône à droite'),
            ),
            RealestyButton(
              label: 'Importer un document',
              variant: RealestyButtonVariant.secondary,
              leadingIcon: RealestyIcons.upload,
              onPressed: () => _toast('Secondaire'),
            ),
            RealestyButton(
              label: 'Passer cette étape',
              variant: RealestyButtonVariant.text,
              onPressed: () => _toast('Texte'),
            ),
            const RealestyButton(label: 'Désactivé', onPressed: null),
            RealestyButton(
              label: 'Envoyer (chargement au tap)',
              isLoading: _loading,
              onPressed: _startLoading,
            ),
          ]),
          const SizedBox(height: RealestySpacing.md),
          Row(
            spacing: RealestySpacing.sm,
            children: [
              RealestyIconButton(
                icon: RealestyIcons.chevronLeft,
                semanticLabel: 'Retour',
                onPressed: () => _toast('Retour'),
              ),
              RealestyIconButton(
                icon: RealestyIcons.close,
                semanticLabel: 'Fermer',
                dark: true,
                onPressed: () => _toast('Fermer'),
              ),
              RealestyMicButton(onPressed: () => _toast('Micro')),
            ],
          ),
          const _Section('Champs'),
          ..._spaced([
            const RealestyTextField(
              label: 'Adresse du bien',
              hint: '12 rue des Lilas, Nantes',
              leadingIcon: RealestyIcons.pin,
            ),
            const RealestyTextField(
              label: 'Surface habitable',
              hint: '0',
              suffixText: 'm²',
              keyboardType: TextInputType.number,
              footer: Align(
                alignment: Alignment.centerLeft,
                child: ProvenanceTag(ProvenanceKind.declared),
              ),
            ),
            const RealestyTextField(
              label: 'E-mail',
              hint: 'vous@exemple.fr',
              leadingIcon: RealestyIcons.mail,
              errorText: 'Adresse e-mail invalide',
            ),
            const RealestyTextField(
              label: 'Champ désactivé',
              hint: 'Non modifiable',
              enabled: false,
            ),
            RealestySelect<String>(
              label: 'Type de bien',
              hint: 'Choisir',
              leadingIcon: RealestyIcons.home,
              value: _propertyType,
              options: const [
                RealestySelectOption(value: 'maison', label: 'Maison'),
                RealestySelectOption(
                  value: 'appartement',
                  label: 'Appartement',
                ),
                RealestySelectOption(value: 'terrain', label: 'Terrain'),
              ],
              onChanged: (value) => setState(() => _propertyType = value),
            ),
          ]),
          const _Section('Sélection'),
          RealestyCheckbox(
            value: _checked,
            richLabel: TextSpan(
              children: [
                const TextSpan(text: 'J’accepte les '),
                TextSpan(
                  text: 'conditions générales',
                  style: RealestyCheckbox.linkStyle(context),
                  recognizer: _termsRecognizer,
                ),
                const TextSpan(text: ' de Realesty.'),
              ],
            ),
            onChanged: (value) => setState(() => _checked = value),
          ),
          RealestyCheckbox(
            value: _unchecked,
            label: 'Recevoir les actualités du marché',
            onChanged: (value) => setState(() => _unchecked = value),
          ),
          const RealestyCheckbox(
            value: false,
            label: 'Case désactivée',
            onChanged: null,
          ),
          const SizedBox(height: RealestySpacing.sm),
          Wrap(
            spacing: RealestySpacing.xs,
            children: [
              RealestyChoiceChip(
                label: 'Jardin',
                selected: _chipGarden,
                onSelected: (value) => setState(() => _chipGarden = value),
              ),
              RealestyChoiceChip(
                label: 'Garage',
                icon: RealestyIcons.car,
                selected: _chipGarage,
                onSelected: (value) => setState(() => _chipGarage = value),
              ),
              const RealestyChoiceChip(
                label: 'Indisponible',
                selected: false,
                onSelected: null,
              ),
            ],
          ),
          const SizedBox(height: RealestySpacing.sm),
          RealestySegmentedControl<String>(
            selected: _segment,
            segments: const [
              RealestySegment(
                value: 'maison',
                label: 'Maison',
                icon: RealestyIcons.home,
              ),
              RealestySegment(
                value: 'appartement',
                label: 'Appartement',
                icon: RealestyIcons.building,
              ),
            ],
            onChanged: (value) => setState(() => _segment = value),
          ),
          const SizedBox(height: RealestySpacing.sm),
          RealestyStepper(
            title: 'Chambres',
            subtitle: 'Pièces fermées de plus de 9 m²',
            value: _rooms,
            max: 10,
            onChanged: (value) => setState(() => _rooms = value),
          ),
          const _Section('Badges & provenance'),
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xs,
            children: [
              for (final variant in RealestyBadgeVariant.values)
                RealestyBadge(label: _badgeLabels[variant]!, variant: variant),
              for (final kind in ProvenanceKind.values) ProvenanceTag(kind),
            ],
          ),
          const _Section('Progression'),
          const SegmentedProgress(total: 5, completed: 2),
          const SizedBox(height: RealestySpacing.md),
          const LinearProgressIndicator(value: 0.6),
          const _Section('Liste'),
          const RealestyListItem(
            title: 'Titre de propriété',
            subtitle: 'Extrait par l’IA',
            leadingIcon: RealestyIcons.file,
            tone: RealestyListTileTone.success,
            trailing: RealestyBadge(
              label: 'Certifié',
              variant: RealestyBadgeVariant.certified,
            ),
          ),
          RealestyListItem(
            title: 'Pièce d’identité',
            subtitle: 'Obligatoire pour la certification',
            leadingIcon: RealestyIcons.user,
            tone: RealestyListTileTone.error,
            trailing: const RealestyBadge(
              label: 'Manquant',
              variant: RealestyBadgeVariant.missing,
            ),
            onTap: () => _toast('Document manquant', isError: true),
          ),
          const RealestyListItem(
            title: 'Diagnostics',
            leadingIcon: RealestyIcons.shield,
            showDivider: false,
          ),
          const _Section('Bannières'),
          ..._spaced(const [
            InlineBanner(
              message:
                  'Estimation automatisée, indicative tant qu’elle n’est pas '
                  'validée par un expert.',
            ),
            InlineBanner(
              message: 'Les données cadastrales proviennent de l’IGN.',
              variant: InlineBannerVariant.info,
            ),
          ]),
          const _Section('Agent'),
          ..._spaced(const [
            AgentBubble(
              message:
                  'J’ai localisé votre parcelle : section AB, n° 98, 540 m².',
            ),
            UserBubble(message: 'Oui, c’est bien ça.'),
          ]),
          const SizedBox(height: RealestySpacing.md),
          Container(
            padding: const EdgeInsets.all(RealestySpacing.md),
            decoration: BoxDecoration(
              color: c.nuit,
              borderRadius: BorderRadius.circular(RealestyRadius.card),
            ),
            child: const Column(
              spacing: RealestySpacing.sm,
              children: _nightBubbles,
            ),
          ),
          const _Section('Espace vendeur'),
          ..._spaced([
            HeroValueCard(
              caption: 'Avis de valeur certifié',
              badgeLabel: 'Certifié',
              value: '525 000 €',
              details: 'Fourchette 505 000 – 545 000 €',
              expertInitials: 'JM',
              expertLabel: 'Validé par Julien M., expert immobilier',
              actionLabel: 'Voir le rapport complet',
              actionIcon: RealestyIcons.file,
              onAction: () => _toast('Rapport'),
            ),
            ActionCard(
              icon: RealestyIcons.trending,
              title: 'Mettre mon bien en vente',
              subtitle: 'Choisissez votre formule, dès 1 % au succès',
              variant: ActionCardVariant.accent,
              onPressed: () => _toast('Mise en vente'),
            ),
            ActionCard(
              icon: RealestyIcons.clock,
              title: 'Suivi de mon dossier',
              subtitle: 'Un expert analyse votre dossier',
              onPressed: () => _toast('Suivi'),
            ),
            const Column(
              children: [
                KeyValueRow(label: 'Prix affiché', value: '525 000 €'),
                KeyValueRow(
                  label: 'Coût total',
                  value: '569 400 €',
                  emphasized: true,
                  divider: false,
                ),
              ],
            ),
            const Row(
              spacing: RealestySpacing.xs,
              children: [InitialsAvatar('SD'), InitialsAvatar('JM', size: 40)],
            ),
            RealestyTabBar(
              currentIndex: _tab,
              onTap: (index) => setState(() => _tab = index),
              tabs: const [
                RealestyTab(icon: RealestyIcons.home, label: 'Mon bien'),
                RealestyTab(
                  icon: RealestyIcons.calendar,
                  label: 'Visites',
                  badge: true,
                ),
                RealestyTab(icon: RealestyIcons.vault, label: 'Coffre-fort'),
                RealestyTab(icon: RealestyIcons.user, label: 'Compte'),
              ],
            ),
          ]),
          const _Section('Mise en vente'),
          ..._spaced([
            const OfferPlanCard(
              badgeLabel: 'L’Essentiel · 1 %',
              badgeVariant: RealestyBadgeVariant.essentiel,
              tagline: 'L’autonomie accompagnée',
              name: 'L’Essentiel',
              rate: '1 %',
              rateCaption: 'au succès',
              fees: 'Aucun frais de dossier · aucun abonnement',
              commission: 'Soit ~5 250 € de commission',
              features: ['Audit complet et dossier technique certifié'],
            ),
            SwitchRow(
              title: 'Retouche automatique',
              subtitle: 'Luminosité, perspectives',
              badge: const RealestyBadge(label: 'Bientôt'),
              value: _retouch,
              onChanged: (value) => setState(() => _retouch = value),
            ),
            PriceRangeSlider(
              low: 505000,
              high: 545000,
              value: _price,
              onChanged: (value) => setState(() => _price = value),
              lowLabel: '505 000 €',
              highLabel: '545 000 €',
              caption: 'Avis de valeur certifié',
              semanticLabel: 'Prix',
            ),
            SignaturePad(
              controller: _signature,
              hint: 'Signez du bout du doigt',
              clearLabel: 'Effacer',
              semanticLabel: 'Zone de signature',
            ),
          ]),
        ],
      ),
    );
  }

  static const _nightBubbles = <Widget>[
    AgentBubble(
      message: 'En quelle année la maison a-t-elle été construite ?',
      onDark: true,
    ),
    UserBubble(message: 'En 1998, en parpaing.', onDark: true),
  ];

  static const _badgeLabels = <RealestyBadgeVariant, String>{
    RealestyBadgeVariant.essentiel: 'Essentiel',
    RealestyBadgeVariant.premium: 'Premium',
    RealestyBadgeVariant.expert: 'Expert',
    RealestyBadgeVariant.compatibility: '94 % compatible',
    RealestyBadgeVariant.passVisite: 'Pass Visite',
    RealestyBadgeVariant.certified: 'Certifié',
    RealestyBadgeVariant.toComplete: 'À compléter',
    RealestyBadgeVariant.missing: 'Manquant',
    RealestyBadgeVariant.neutral: 'Neutre',
  };

  static List<Widget> _spaced(List<Widget> children) => [
    for (final (i, child) in children.indexed) ...[
      if (i > 0) const SizedBox(height: RealestySpacing.sm),
      child,
    ],
  ];

  static List<(String, Color)> _swatches(RealestyColors c) => [
    ('Encre', c.encre),
    ('Encre 2', c.encre2),
    ('Texte discret', c.texteDiscret),
    ('Placeholder', c.placeholder),
    ('Ligne', c.ligne),
    ('Bordure carte', c.bordureCarte),
    ('Ivoire', c.ivoire),
    ('Surface', c.surface),
    ('Surface 2', c.surface2),
    ('Image', c.imagePlaceholder),
    ('Vert', c.vert),
    ('Vert texte', c.vertTexte),
    ('Vert teinte', c.vertTeinte),
    ('Lien pressé', c.vertLienPresse),
    ('Nuit', c.nuit),
    ('Nuit 2', c.nuit2),
    ('Nuit 3', c.nuit3),
    ('Lueur', c.lueur),
    ('Premium', c.premium),
    ('Premium fond', c.premiumFond),
    ('Expert', c.expert),
    ('Expert fond', c.expertFond),
    ('Attention', c.attention),
    ('Attention fond', c.attentionFond),
    ('Erreur', c.erreur),
    ('Erreur fond', c.erreurFond),
  ];
}

class _Section extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: RealestySpacing.xxl,
        bottom: RealestySpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title.toUpperCase(),
          style: RealestyTextStyles.caption.copyWith(
            color: context.realestyColors.texteDiscret,
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const new({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return SizedBox(
      width: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RealestySpacing.xxs,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(RealestyRadius.field),
              border: Border.all(color: c.bordureCarte),
            ),
          ),
          Text(name, style: RealestyTextStyles.tag.copyWith(color: c.encre2)),
        ],
      ),
    );
  }
}
