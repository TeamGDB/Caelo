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
  String get welcome => 'Welcome';

  @override
  String get welcomeExplanation =>
      'Paste an invitation link to connect your account and receive its servers and configurations.';

  @override
  String get invitationPlaceholder => 'https://…';

  @override
  String get invitationEmpty => 'Paste an invitation link';

  @override
  String get invitationInvalid => 'Check the invitation link';

  @override
  String get invitationUnavailable =>
      'Could not check the invitation right now';

  @override
  String get continueAction => 'Continue';

  @override
  String get cancel => 'Cancel';

  @override
  String get qrLogin => 'Sign in with QR';

  @override
  String get qrUnavailableExplanation =>
      'QR sign-in is not available yet. Use an invitation link.';

  @override
  String get importOwnConfiguration => 'Import your own configuration file';

  @override
  String get configurationFileInvalid => 'Choose a valid WireGuard .conf file';

  @override
  String get forgetAccount => 'Disconnect account';

  @override
  String get selectedServer => 'Current server';

  @override
  String get chooseServer => 'Choose server';

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
  String get serviceOlderThanApp =>
      'The Caelo background service is older than this app. Reinstall Caelo to update it.';

  @override
  String get appOlderThanService =>
      'This app is older than the Caelo background service. Update Caelo.';

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
  String get currentConnection => 'Current connection';

  @override
  String latency(int ping) {
    return '$ping ms';
  }

  @override
  String get noSubscription => 'No subscription yet';

  @override
  String get addSubscription => 'Add subscription';

  @override
  String get noConfig => 'No configuration yet';

  @override
  String get configuration => 'Configuration';

  @override
  String get configurationName => 'Configuration name';

  @override
  String get configurationEmoji => 'Flag or emoji';

  @override
  String get configurationDescription => 'Server description';

  @override
  String get customServerDescription => 'User configuration';

  @override
  String get configurationEmpty => 'Paste a configuration';

  @override
  String get addConfiguration => 'Add configuration';

  @override
  String get customConfiguration => 'Custom config';

  @override
  String get configurationInstalled => 'Installed';

  @override
  String get configurationNone => 'None';

  @override
  String get configurationPlaceholder => 'Paste an AmneziaWG .conf here';

  @override
  String get configurationWarning =>
      'Stored unencrypted in the app\'s container. Use a key you are willing to rotate.';

  @override
  String get save => 'Save';

  @override
  String get remove => 'Remove';

  @override
  String get localTunnelOnly =>
      'This process only — other apps are not routed yet';

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
  String get languageRussian => 'Russian';

  @override
  String get languageEnglish => 'English';

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

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get appearance => 'Appearance';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get diagnosticLog => 'Diagnostic log';

  @override
  String get diagnosticLogOn => 'Record a diagnostic log';

  @override
  String get diagnosticLogNote =>
      'Off by default. While on, connection events are kept on this device so a problem can be reported. Keys are never recorded; server addresses are.';

  @override
  String get viewLog => 'View log';

  @override
  String get logCopy => 'Copy';

  @override
  String get logClear => 'Clear';

  @override
  String get logExport => 'Export';

  @override
  String get logCopied => 'Copied';

  @override
  String get logCleared => 'Cleared';

  @override
  String get logEmpty => 'Nothing recorded yet';

  @override
  String get logDisabled => 'Recording is off';

  @override
  String get updates => 'Updates';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get updateCheckNote =>
      'Caelo asks a static file whether a newer version exists. The request carries no identifier and is the same from every installation, and it goes through the tunnel when one is up. Turning this off stops it being sent at all.';

  @override
  String get checkNow => 'Check now';
}
