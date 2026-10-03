import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubits.dart';
import 'package:mobileapp/seller_tunnel/photos/photo_services.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shares a downloaded document with the iOS share sheet, from a
/// temporary file deleted once the sheet is closed (identity documents…).
Future<void> shareDocumentFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  final directory = await Directory.systemTemp.createTemp('realesty_share');
  try {
    final file = File('${directory.path}/${fileName.split('/').last}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

/// The message of a [notice] and whether it is an error.
(String, bool) vaultNoticeMessage(AppLocalizations l10n, VaultNotice notice) =>
    switch (notice) {
      VaultNotice.uploaded => (l10n.vaultNoticeUploaded, false),
      VaultNotice.replaced => (l10n.vaultNoticeReplaced, false),
      VaultNotice.deleted => (l10n.vaultNoticeDeleted, false),
      VaultNotice.uploadFailed => (l10n.vaultNoticeUploadFailed, true),
      VaultNotice.deleteFailed => (l10n.vaultNoticeDeleteFailed, true),
      VaultNotice.saveFailed => (l10n.vaultNoticeSaveFailed, true),
      VaultNotice.openFailed => (l10n.vaultNoticeOpenFailed, true),
      VaultNotice.shareFailed => (l10n.vaultNoticeShareFailed, true),
      VaultNotice.unsupportedType => (
        l10n.documentsNoticeUnsupportedType,
        true,
      ),
      VaultNotice.fileTooLarge => (l10n.documentsNoticeTooLarge, true),
      VaultNotice.metadataUnremovable => (
        l10n.documentsNoticeMetadataUnremovable,
        true,
      ),
      VaultNotice.accessDenied => (l10n.documentsNoticeAccessDenied, true),
      VaultNotice.pickFailed => (l10n.documentsNoticePickFailed, true),
      VaultNotice.reuseFailed => (l10n.documentsNoticeReuseFailed, true),
    };

/// The device services of the vault, replaceable in tests.
class VaultServices {
  const new({
    this.documentPicker,
    this.scanPdfBuilder,
    this.openUrl = launchUrl,
    this.share = shareDocumentFile,
  });

  /// Defaults to the scanner, photo library and files of the device.
  final DocumentPicker? documentPicker;

  /// Defaults to [IsolateScanPdfBuilder].
  final ScanPdfBuilder? scanPdfBuilder;

  /// Opens a document (its signed URL).
  final DocumentUrlOpener openUrl;

  /// Shares a downloaded document ("Télécharger").
  final DocumentSharer share;
}

/// Provides a [VaultCubit] (and the scanner of V7) to [child]; keeps the
/// dossiers of the seller space current after each change.
class VaultScope extends StatelessWidget {
  const new({
    required this.child,
    this.services = const VaultServices(),
    super.key,
  });

  final VaultServices services;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DocumentPicker>(
          create: (_) => services.documentPicker ?? PlatformDocumentPicker(),
        ),
        RepositoryProvider<ScanPdfBuilder>(
          create: (_) =>
              services.scanPdfBuilder ?? const IsolateScanPdfBuilder(),
        ),
      ],
      child: BlocProvider(
        create: (context) {
          final registry = context.read<SellerTunnelCubits?>();
          return VaultCubit(
            propertyRepository: context.read<PropertyRepository>(),
            valuationRepository: context.read<ValuationRepository>(),
            documentPicker: context.read<DocumentPicker>(),
            openUrl: services.openUrl,
            share: services.share,
            photoProcessor: PhotoServices.of(context).photoProcessor,
            onDocumentsChanged: registry == null
                ? null
                : (propertyId, documents) => registry
                      .of(propertyId)
                      .updateChildren(documents: documents),
          );
        },
        child: BlocListener<VaultCubit, VaultState>(
          listenWhen: (previous, current) =>
              current.notice != null && previous.notice != current.notice,
          listener: (context, state) {
            final notice = state.notice!;
            context.read<VaultCubit>().noticeShown();
            final (message, isError) = vaultNoticeMessage(context.l10n, notice);
            showRealestySnackBar(context, message, isError: isError);
          },
          child: child,
        ),
      ),
    );
  }
}
