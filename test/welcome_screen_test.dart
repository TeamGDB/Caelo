import 'package:caelo/core/account_gateway.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/theme/palette.dart';
import 'package:caelo/ui/qr_scan_screen.dart';
import 'package:caelo/ui/welcome_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements AccountGateway {
  String? invitation;

  @override
  Future<AccountSession> acceptInvitation(String invitation) async {
    this.invitation = invitation;
    if (!invitation.startsWith('https://')) throw const InvalidInvitation();
    return const AccountSession(displayName: 'Test');
  }
}

Future<void> _pumpWelcome(
  WidgetTester tester, {
  required AccountGateway gateway,
  required Future<void> Function() onGranted,
  Locale locale = const Locale('en'),
  Future<String?> Function(BuildContext)? scanQr,
  bool showQr = true,
}) async {
  final palette = CaeloThemeMode.light.resolve(Brightness.light);
  await tester.pumpWidget(
    CaeloColors(
      palette: palette,
      child: CupertinoApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(
          gateway: gateway,
          onGranted: onGranted,
          scanQr: scanQr,
          showQr: showQr,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Russian first-run invitation flow', (tester) async {
    await _pumpWelcome(
      tester,
      gateway: _Gateway(),
      onGranted: () async {},
      locale: const Locale('ru'),
    );

    expect(find.text('Добро пожаловать'), findsOneWidget);
    expect(find.text('Войти по QR'), findsOneWidget);
    expect(find.text('Добавить свой файл конфигурации'), findsOneWidget);
  });

  testWidgets('validates an invitation before granting access', (tester) async {
    final gateway = _Gateway();
    var granted = false;
    await _pumpWelcome(
      tester,
      gateway: gateway,
      onGranted: () async => granted = true,
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Paste an invitation link'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField), 'https://invite');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(gateway.invitation, 'https://invite');
    expect(granted, isTrue);
  });

  testWidgets('a scanned QR code signs in with the link it carries (#142)', (
    tester,
  ) async {
    final gateway = _Gateway();
    var granted = false;
    await _pumpWelcome(
      tester,
      gateway: gateway,
      onGranted: () async => granted = true,
      scanQr: (_) async => 'https://sub.example.invalid/s/token',
    );

    await tester.tap(find.text('Sign in with QR'));
    await tester.pumpAndSettle();
    expect(gateway.invitation, 'https://sub.example.invalid/s/token');
    expect(granted, isTrue);
  });

  testWidgets('closing the scanner changes nothing', (tester) async {
    final gateway = _Gateway();
    var granted = false;
    await _pumpWelcome(
      tester,
      gateway: gateway,
      onGranted: () async => granted = true,
      scanQr: (_) async => null,
    );

    await tester.tap(find.text('Sign in with QR'));
    await tester.pumpAndSettle();
    expect(gateway.invitation, isNull);
    expect(granted, isFalse);
  });

  testWidgets('no QR button where there is no camera to speak of', (
    tester,
  ) async {
    await _pumpWelcome(
      tester,
      gateway: _Gateway(),
      onGranted: () async {},
      showQr: false,
    );
    expect(find.text('Sign in with QR'), findsNothing);
  });

  test('only an https link is taken from a code', () {
    expect(
      invitationFromCode(' https://a.example/sub/x '),
      'https://a.example/sub/x',
    );
    expect(invitationFromCode('http://a.example/sub/x'), isNull);
    expect(invitationFromCode('WIFI:S:home;P:secret;;'), isNull);
    expect(invitationFromCode('[Interface]\nPrivateKey = x'), isNull);
    expect(invitationFromCode(null), isNull);
  });
}
