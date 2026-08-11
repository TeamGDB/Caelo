import 'package:caelo/core/account_gateway.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/theme/palette.dart';
import 'package:caelo/ui/welcome_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements AccountGateway {
  String? invitation;
  int qrCalls = 0;

  @override
  Future<AccountSession> acceptInvitation(String invitation) async {
    this.invitation = invitation;
    if (!invitation.startsWith('https://')) throw const InvalidInvitation();
    return const AccountSession(displayName: 'Test');
  }

  @override
  Future<AccountSession> signInWithQr() async {
    qrCalls++;
    return const AccountSession(displayName: 'Test');
  }
}

Future<void> _pumpWelcome(
  WidgetTester tester, {
  required AccountGateway gateway,
  required Future<void> Function() onGranted,
  Locale locale = const Locale('en'),
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
        home: WelcomeScreen(gateway: gateway, onGranted: onGranted),
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

  testWidgets('uses the account gateway for QR when it becomes available', (
    tester,
  ) async {
    final gateway = _Gateway();
    var granted = false;
    await _pumpWelcome(
      tester,
      gateway: gateway,
      onGranted: () async => granted = true,
    );

    await tester.tap(find.text('Sign in with QR'));
    await tester.pumpAndSettle();
    expect(gateway.qrCalls, 1);
    expect(granted, isTrue);
  });

  testWidgets('does not create a demo account when QR is unavailable', (
    tester,
  ) async {
    var granted = false;
    await _pumpWelcome(
      tester,
      gateway: const SubscriptionAccountGateway(),
      onGranted: () async => granted = true,
    );

    await tester.tap(find.text('Sign in with QR'));
    await tester.pumpAndSettle();

    expect(find.textContaining('QR sign-in is not available'), findsOneWidget);
    expect(granted, isFalse);
  });
}
