import 'package:caelo/core/settings_store.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/main.dart' show LocaleModeScope;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locale modes map only explicit choices to a locale', () {
    expect(CaeloLocaleMode.system.locale, isNull);
    expect(CaeloLocaleMode.russian.locale, const Locale('ru'));
    expect(CaeloLocaleMode.english.locale, const Locale('en'));
  });

  testWidgets('an explicit Russian choice applies without restarting', (
    tester,
  ) async {
    await tester.pumpWidget(const _LocaleHarness());
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
  });
}

class _LocaleHarness extends StatefulWidget {
  const _LocaleHarness();

  @override
  State<_LocaleHarness> createState() => _LocaleHarnessState();
}

class _LocaleHarnessState extends State<_LocaleHarness> {
  CaeloLocaleMode mode = CaeloLocaleMode.english;

  Future<void> change(CaeloLocaleMode next) async {
    setState(() => mode = next);
  }

  @override
  Widget build(BuildContext context) {
    return LocaleModeScope(
      mode: mode,
      onChanged: change,
      child: CupertinoApp(
        locale: mode.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Column(
              children: [
                Text(AppLocalizations.of(context).settings),
                CupertinoButton(
                  onPressed: () => LocaleModeScope.maybeOf(
                    context,
                  )!.onChanged(CaeloLocaleMode.russian),
                  child: const Text('switch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
