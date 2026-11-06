import 'dart:io';

import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_flow.dart';
import 'package:caelo/core/windows_updater.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/ui/update_prompt.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

AvailableUpdate get _update => AvailableUpdate(
  version: '0.3.1',
  build: 15,
  url: 'https://example.invalid/Caelo.apk',
  sizeBytes: 28 * 1048576,
  sha256: 'a' * 64,
  signature: 'c2ln',
  notesUrl: 'https://example.invalid/notes',
);

void main() {
  Future<void> pump(WidgetTester tester, UpdateFlow flow) async {
    await tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UpdatePrompt(
          flow: flow,
          enabled: true,
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a newer build on its own, without Settings (#133)', (
    tester,
  ) async {
    var downloads = 0;
    final flow = UpdateFlow(
      look: () async => _update,
      fetch: (_, _) async {
        downloads++;
        return File('unused');
      },
      canInstall: () async => true,
      install: (_) async {},
      readPending: () async => null,
      writePending: (_) async {},
    );
    await pump(tester, flow);

    expect(find.text('Доступна версия 0.3.1'), findsOneWidget);
    expect(downloads, 0, reason: 'asks before downloading');

    await tester.tap(find.byKey(const ValueKey('update-now')));
    await tester.pumpAndSettle();
    expect(downloads, 1);
    expect(flow.stage, UpdateStage.handedOver);
  });

  testWidgets('says nothing when this is the newest', (tester) async {
    final flow = UpdateFlow(
      look: () async => null,
      readPending: () async => null,
      writePending: (_) async {},
    );
    await pump(tester, flow);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets(
    'an early Windows setup exit offers a neutral explanation and retry',
    (tester) async {
      final flow = UpdateFlow(
        look: () async => _update,
        fetch: (_, _) async => File('verified.exe'),
        canInstall: () async => true,
        install: (_) async => throw const WindowsInstallerStopped(),
        readPending: () async => null,
        writePending: (_) async {},
      );
      await pump(tester, flow);
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pumpAndSettle();

      expect(find.text('Установка не началась'), findsOneWidget);
      expect(
        find.textContaining('вы отменили запрос разрешения Windows'),
        findsOneWidget,
      );
      expect(find.text('Скачивание не завершилось.'), findsNothing);
      expect(find.textContaining('Android'), findsNothing);
      await tester.tap(find.text('Попробовать снова'));
      await tester.pumpAndSettle();
      expect(find.text('Доступна версия 0.3.1'), findsOneWidget);
    },
  );

  testWidgets('later leaves the app alone', (tester) async {
    final flow = UpdateFlow(
      look: () async => _update,
      readPending: () async => null,
      writePending: (_) async {},
    );
    await pump(tester, flow);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('reports an update that did not install, once, at launch', (
    tester,
  ) async {
    int? pending = 99;
    final flow = UpdateFlow(
      look: () async => null,
      readPending: () async => pending,
      writePending: (build) async => pending = build,
      currentBuild: 14,
    );
    await pump(tester, flow);
    expect(find.text('Обновление не установилось'), findsOneWidget);
  });

  testWidgets('checks again on coming back, not only half a day later (#148)', (
    tester,
  ) async {
    var looks = 0;
    final flow = UpdateFlow(
      look: () async {
        looks++;
        return null;
      },
      readPending: () async => null,
      writePending: (_) async {},
    );
    await tester.pumpWidget(
      CupertinoApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UpdatePrompt(
          flow: flow,
          enabled: true,
          every: Duration.zero,
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(looks, 1, reason: 'at launch');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(looks, 2, reason: 'and on coming back');
  });
}
