#!/usr/bin/env python3
"""Check source/signed network rights; the optional UDP regression runs only in CI."""
import argparse
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT = 'com.apple.security.network.client'
SERVER = 'com.apple.security.network.server'
SANDBOX = 'com.apple.security.app-sandbox'


def require_network(rights, label, sandbox=False):
    needed = [CLIENT, SERVER] + ([SANDBOX] if sandbox else [])
    missing = [key for key in needed if rights.get(key) is not True]
    if missing:
        raise RuntimeError(f'{label}: missing true entitlement(s): {", ".join(missing)}')


def source_rights():
    files = [
        ('release app', 'macos/Runner/Release.entitlements', True),
        ('debug app', 'macos/Runner/DebugProfile.entitlements', False),
        ('system extension', 'macos/CaeloSystemExtension/CaeloSystemExtension.entitlements', True),
    ]
    result = {}
    for label, name, sandbox in files:
        rights = plistlib.loads((ROOT / name).read_bytes())
        require_network(rights, label, sandbox)
        result[label] = rights
    return result


def signed_rights(bundle):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)],
                            capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def verify_app(app):
    extension = app / 'Contents/Library/SystemExtensions/team.gdb.caelo.SystemExtension.systemextension'
    for label, bundle in [('signed app', app), ('signed system extension', extension)]:
        if not bundle.is_dir():
            raise RuntimeError(f'{label} is missing: {bundle}')
        subprocess.run(['codesign', '--verify', '--strict', str(bundle)], capture_output=True, check=True)
        require_network(signed_rights(bundle), label, sandbox=True)
        print(f'{label}: sandbox, network.client and network.server verified')


PROBE = r'''
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>
int main(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) { perror("socket"); return 3; }
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(0);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int code = errno;
        close(fd);
        fprintf(stderr, "UDP bind denied: errno=%d\n", code);
        return code == EPERM ? 42 : 4;
    }
    close(fd);
    puts("UDP bind allowed; socket closed without sending packets");
    return 0;
}
'''


def exercise_bind(release):
    # The user's workstation must not run even this local socket experiment.
    if sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_OS') != 'macOS':
        raise RuntimeError('--exercise-bind is restricted to a macOS GitHub Actions runner')
    with tempfile.TemporaryDirectory(prefix='caelo-udp-entitlement-') as directory:
        root = pathlib.Path(directory)
        source = root / 'probe.c'
        source.write_text(PROBE)
        binary = root / 'probe'
        subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)], check=True)
        for name, server, expected in [('control', False, 42), ('release', release[SERVER], 0)]:
            bundle = root / (name + '.app')
            executable = bundle / 'Contents/MacOS/probe'
            executable.parent.mkdir(parents=True)
            executable.write_bytes(binary.read_bytes())
            executable.chmod(0o755)
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'team.gdb.caelo.udp-test.' + name,
                'CFBundleName': 'Caelo UDP entitlement test',
                'CFBundleExecutable': 'probe', 'CFBundlePackageType': 'APPL',
                'CFBundleVersion': '1',
            }))
            # Only the ordinary sandbox/network rights. No provisioning-only
            # capabilities or user/group-container access belong in this probe.
            rights = {SANDBOX: release[SANDBOX], CLIENT: release[CLIENT]}
            if server:
                rights[SERVER] = True
            entitlements = root / (name + '.plist')
            entitlements.write_bytes(plistlib.dumps(rights))
            subprocess.run(['codesign', '--force', '--sign', '-', '--generate-entitlement-der',
                            '--entitlements', str(entitlements), str(bundle)], check=True, capture_output=True)
            signed = signed_rights(bundle)
            if any(signed.get(key) != value for key, value in rights.items()) or bool(signed.get(SERVER)) != server:
                raise RuntimeError(f'{name}: signing did not preserve the test entitlements')
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
            if result.returncode != expected:
                raise RuntimeError(f'{name}: expected exit {expected}, got {result.returncode}: {result.stderr.strip()}')
            print(f'{name}: {result.stdout.strip() or result.stderr.strip()}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path, help='read and verify the signed app and embedded extension')
    parser.add_argument('--exercise-bind', action='store_true', help='CI only: signed sandbox UDP bind, without packets or VPN')
    args = parser.parse_args()
    rights = source_rights()
    print('Source entitlements: network rights are present')
    if args.app:
        verify_app(args.app)
    if args.exercise_bind:
        exercise_bind(rights['release app'])


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError, plistlib.InvalidFileException) as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
