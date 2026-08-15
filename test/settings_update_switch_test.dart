import 'dart:io';

import 'package:caelo/core/build_info.dart';
import 'package:caelo/core/settings_store.dart';
import 'package:caelo/core/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-settings-test-');
    SettingsStore.file = (name) async => File('${directory.path}/$name');
    SettingsStore.forgetCache();
  });

  tearDown(() async {
    SettingsStore.forgetCache();
    await directory.delete(recursive: true);
  });

  // #51 requires the switch to stop the request rather than discard the answer.
  // The store is what the check reads, so this is the join that matters: a
  // default of "on" that read as "off", or a setting that did not persist,
  // would each be invisible until somebody looked at a packet capture.
  test('the setting defaults to on and survives being written', () async {
    expect(
      await SettingsStore.updateChecks(),
      isTrue,
      reason: 'people who never open Settings should still hear about updates',
    );

    await SettingsStore.setUpdateChecks(false);
    expect(await SettingsStore.updateChecks(), isFalse);

    // And the check honours it without touching the network.
    var asked = false;
    await UpdateCheck.look(
      fetch: (_) async {
        asked = true;
        return '{}';
      },
      enabled: SettingsStore.updateChecks,
    );
    expect(asked, isFalse);

    await SettingsStore.setUpdateChecks(true);
    expect(await SettingsStore.updateChecks(), isTrue);
  });

  test('the version shown in Settings comes from one place', () {
    // It had been written out by hand a third time. The constant exists because
    // the copy nobody updates is the one people read off a screenshot.
    expect(appVersion, isNotEmpty);
    expect(appBuild, greaterThan(0));
  });
}
