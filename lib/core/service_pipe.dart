import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// One exchange with the privileged service over a Windows named pipe.
///
/// `dart:io` has no named pipes, and no AF_UNIX on Windows either, so this is
/// the Win32 calls by hand. The pipe's security descriptor is what decides who
/// may open it — set by the service when it creates the pipe — so there is no
/// credential to present here and nothing to authenticate with.
///
/// Every call blocks, so this runs on its own isolate.
abstract final class ServicePipe {
  static const name = r'\\.\pipe\caelo';

  /// Where the installer puts the service, beside the application.
  ///
  /// This is what "installed" means on Windows. The pipe cannot answer the
  /// question: it does not exist until the service is running, and the service
  /// does not run until somebody opens the pipe. The portable zip deliberately
  /// carries no service, so its absence here is the honest answer rather than a
  /// missed case.
  static bool get isInstalled {
    if (!Platform.isWindows) return false;
    final directory = File(Platform.resolvedExecutable).parent.path;
    return File('$directory\\caelo-service.exe').existsSync();
  }

  static Future<String> exchange(String line, Duration timeout) {
    final deadlineMs = timeout.inMilliseconds;
    return Isolate.run(() => _exchange(line, deadlineMs));
  }

  static String _exchange(String line, int deadlineMs) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    final createFile = kernel32
        .lookupFunction<
          IntPtr Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer<Void>,
            Uint32,
            Uint32,
            IntPtr,
          ),
          int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
        >('CreateFileW');
    final writeFile = kernel32
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
        >('WriteFile');
    final readFile = kernel32
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
        >('ReadFile');
    final closeHandle = kernel32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle',
        );
    final getLastError = kernel32
        .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

    const genericRead = 0x80000000;
    const genericWrite = 0x40000000;
    const openExisting = 3;
    const invalidHandle = -1;

    final path = name.toNativeUtf16();
    var handle = invalidHandle;
    try {
      // The first attempt is expected to fail. The service is registered with a
      // named-pipe start trigger, so opening a pipe nobody is listening on is
      // what tells the Service Control Manager to start it — and by then this
      // call has already returned. Retrying is not a workaround for a race; it
      // is how the mechanism is used.
      final started = DateTime.now();
      while (true) {
        handle = createFile(
          path,
          genericRead | genericWrite,
          0,
          nullptr,
          openExisting,
          0,
          0,
        );
        if (handle != invalidHandle) break;

        if (DateTime.now().difference(started).inMilliseconds > deadlineMs) {
          throw ServicePipeUnavailable(
            'the service did not answer on $name (error ${getLastError()})',
          );
        }
        sleep(const Duration(milliseconds: 150));
      }

      final request = utf8.encode('$line\n');
      final buffer = malloc<Uint8>(request.length);
      final written = malloc<Uint32>();
      try {
        buffer.asTypedList(request.length).setAll(0, request);
        if (writeFile(handle, buffer, request.length, written, nullptr) == 0) {
          throw ServicePipeUnavailable('writing failed (${getLastError()})');
        }
      } finally {
        malloc.free(buffer);
        malloc.free(written);
      }

      // One line, then the service closes its end. Reading until the pipe ends
      // is therefore the whole reply, and no framing is needed beyond it.
      final chunk = malloc<Uint8>(4096);
      final read = malloc<Uint32>();
      final reply = BytesBuilder();
      try {
        while (readFile(handle, chunk, 4096, read, nullptr) != 0 &&
            read.value > 0) {
          reply.add(chunk.asTypedList(read.value).sublist(0));
        }
      } finally {
        malloc.free(chunk);
        malloc.free(read);
      }

      return utf8.decode(reply.takeBytes()).trim();
    } finally {
      if (handle != invalidHandle) closeHandle(handle);
      malloc.free(path);
    }
  }
}

/// Raised when the pipe could not be opened, which on Windows is the same
/// question as "is the service there".
class ServicePipeUnavailable implements Exception {
  const ServicePipeUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
