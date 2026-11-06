import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// Where a subscription's QR code can be read: phones, tablets and Macs.
///
/// Linux and Windows machines rarely have a camera, and pointing one at a
/// code on the same machine's screen is not a thing anybody does; the
/// invitation link is pasted there (#142).
bool get qrSignInSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// The link a scanned code carries, or null when it is not an invitation.
///
/// Only an https link is taken, the same rule a pasted one is held to: a QR
/// code is somebody else's text, and a code from anywhere else should be
/// refused here rather than sent to a server as though it were a
/// subscription.
String? invitationFromCode(String? raw) {
  final value = raw?.trim() ?? '';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return value;
}

/// Reads the subscription's QR code from the panel and returns its link.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _wrongCode = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final link = invitationFromCode(code.rawValue);
      if (link != null) {
        _done = true;
        Navigator.of(context).pop(link);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && !_wrongCode) {
      setState(() => _wrongCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      // Dark over the camera picture, light text on it: a light bar above a
      // dark viewfinder left the title unreadable.
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF000000),
        border: null,
        brightness: Brightness.dark,
        middle: Text(
          l10n.qrLogin,
          style: const TextStyle(color: Color(0xFFFFFFFF)),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(CaeloSpace.lg),
                  child: Text(
                    l10n.qrCameraUnavailable,
                    textAlign: TextAlign.center,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(color: const Color(0xFFFFFFFF)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: CaeloSpace.lg,
            right: CaeloSpace.lg,
            bottom: CaeloSpace.lg,
            child: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: CaeloRadius.controlAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(CaeloSpace.md),
                  child: Text(
                    _wrongCode ? l10n.qrNotInvitation : l10n.qrPointCamera,
                    key: const ValueKey('qr-hint'),
                    textAlign: TextAlign.center,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(color: const Color(0xFFFFFFFF), height: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
