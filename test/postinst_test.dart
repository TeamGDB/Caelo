import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// packaging/linux/postinst.sh, run against stand-ins for the system tools, so
/// what it changes is recorded rather than done.
///
/// PATH holds only the stand-ins and a few harmless tools, so the parts that
/// would touch apt, rpm or systemd find nothing and are skipped.
void main() {
  late Directory root;
  late Directory bin;
  late File log;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('caelo-postinst-');
    bin = await Directory('${root.path}/bin').create();
    log = File('${root.path}/log');
    for (final tool in ['tr', 'grep', 'cut', 'cat']) {
      final found = Process.runSync('sh', ['-c', 'command -v $tool']);
      await Link('${bin.path}/$tool').create(found.stdout.toString().trim());
    }
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> stub(String name, String body) async {
    final file = File('${bin.path}/$name');
    await file.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', file.path]);
  }

  /// [sessions]: id → `show-session` output. [uids]: name → uid.
  /// [groups]: name → groups, the user is in.
  Future<ProcessResult> run({
    Map<String, String> env = const {},
    Map<String, String>? sessions,
    Map<String, int> uids = const {},
    Map<String, String> groups = const {},
  }) async {
    await stub('groupadd', 'echo "groupadd \$*" >> ${log.path}');
    await stub('usermod', 'echo "usermod \$*" >> ${log.path}');
    await stub('getent', r'''
case "$1 $2" in
  "group caelo") echo "caelo:x:991:" ;;
  "passwd 1000") echo "anna:x:1000:1000::/home/anna:/bin/sh" ;;
  *) exit 2 ;;
esac''');
    final idCases = StringBuffer();
    uids.forEach((n, u) => idCases.writeln('  "-u $n") echo $u ;;'));
    groups.forEach((n, g) => idCases.writeln('  "-nG $n") echo "$g" ;;'));
    await stub('id', 'case "\$1 \$2" in\n$idCases  *) exit 1 ;;\nesac');
    if (sessions != null) {
      final list = sessions.keys
          .map((s) => '   $s 1000 x seat0 tty2')
          .join('\n');
      final show = StringBuffer();
      sessions.forEach(
        (s, props) => show.writeln('  $s) printf "%s\\n" $props ;;'),
      );
      await stub('loginctl', '''
case "\$1" in
  list-sessions) cat <<'LIST'
$list
LIST
  ;;
  show-session) case "\$2" in
$show    *) exit 1 ;;
  esac ;;
esac''');
    }
    return Process.run(
      '/bin/sh',
      ['packaging/linux/postinst.sh'],
      environment: {'PATH': bin.path, ...env},
      includeParentEnvironment: false,
    );
  }

  List<String> changes() => log.existsSync() ? log.readAsLinesSync() : const [];

  test('sudo: the sudo user, and nobody else', () async {
    final result = await run(
      env: {'SUDO_USER': 'anna'},
      sessions: {'2': 'Name=boris Type=wayland Remote=no Class=user'},
      uids: {'anna': 1000, 'boris': 1001},
      groups: {'anna': 'anna sudo'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(changes(), ['usermod -aG caelo anna']);
  });

  test('pkexec: the user behind the uid', () async {
    await run(env: {'PKEXEC_UID': '1000'}, groups: {'anna': 'anna'});
    expect(changes(), ['usermod -aG caelo anna']);
  });

  test('PackageKit sets neither: the person at the screen (#116)', () async {
    final result = await run(
      sessions: {
        '2': 'Name=anna Type=wayland Remote=no Class=user',
        'c1': 'Name=gdm Type=wayland Remote=no Class=greeter',
        'c2': 'Name=gdm-greeter Type=wayland Remote=no Class=greeter',
        '5': 'Name=boris Type=x11 Remote=yes Class=user',
        '7': 'Name=anna Type=x11 Remote=no Class=user',
      },
      uids: {'anna': 1000, 'boris': 1001, 'gdm': 120, 'gdm-greeter': 60578},
      groups: {'anna': 'anna'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(changes(), ['usermod -aG caelo anna'], reason: 'once, and only her');
    expect(result.stdout, contains('log out and back in'));
  });

  test('a system account with a session is not added', () async {
    await run(
      sessions: {'2': 'Name=kiosk Type=x11 Remote=no Class=user'},
      uids: {'kiosk': 999},
    );
    expect(changes(), isEmpty);
  });

  test('two people at the machine are both added', () async {
    await run(
      sessions: {
        '2': 'Name=anna Type=wayland Remote=no Class=user',
        '3': 'Name=boris Type=x11 Remote=no Class=user',
      },
      uids: {'anna': 1000, 'boris': 1001},
      groups: {'anna': 'anna', 'boris': 'boris caelo'},
    );
    expect(changes(), ['usermod -aG caelo anna'], reason: 'boris already is');
  });

  test(
    'nobody at the machine: nothing added, and it says what to do',
    () async {
      final result = await run(sessions: const {});
      expect(result.exitCode, 0);
      expect(changes(), isEmpty);
      expect(result.stdout, contains('sudo usermod -aG caelo'));
    },
  );

  test('no loginctl at all, as in a container: as before', () async {
    final result = await run();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(changes(), isEmpty);
    expect(result.stdout, contains('could not tell who is installing'));
  });
}
