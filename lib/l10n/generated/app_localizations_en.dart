// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Caelo';

  @override
  String get statusDisconnected => 'Not connected';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusDisconnecting => 'Disconnecting';

  @override
  String get statusFailed => 'Could not connect';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String viaNode(String node) {
    return 'via $node';
  }

  @override
  String protocolAndPing(String protocol, int ping) {
    return '$protocol · $ping ms';
  }

  @override
  String get noSubscription => 'No subscription yet';

  @override
  String get addSubscription => 'Add subscription';

  @override
  String get reconnectDifferently => 'Reconnect differently';

  @override
  String get settings => 'Settings';

  @override
  String get subscriptions => 'Subscriptions';

  @override
  String get appearanceLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get core => 'Core';

  @override
  String get coreUnavailable => 'not loaded';

  @override
  String get licence => 'Licence';

  @override
  String get sourceCode => 'Source code';

  @override
  String get done => 'Done';
}
