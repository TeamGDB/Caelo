import 'package:flutter/foundation.dart';

@immutable
class AccountSession {
  const AccountSession({required this.displayName});

  final String displayName;
}

/// Backend boundary for invitation and QR authentication.
abstract interface class AccountGateway {
  Future<AccountSession> acceptInvitation(String invitation);

  Future<AccountSession> signInWithQr();
}

class InvalidInvitation implements Exception {
  const InvalidInvitation();
}

/// Temporary development implementation while the account backend is absent.
///
/// It deliberately returns no credentials, configurations or server addresses.
/// Replacing this class with the real gateway must not change onboarding UI.
class MockAccountGateway implements AccountGateway {
  const MockAccountGateway();

  @override
  Future<AccountSession> acceptInvitation(String invitation) async {
    final uri = Uri.tryParse(invitation.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const InvalidInvitation();
    }
    return const AccountSession(displayName: 'Caelo Demo');
  }

  @override
  Future<AccountSession> signInWithQr() async =>
      const AccountSession(displayName: 'Caelo Demo');
}
