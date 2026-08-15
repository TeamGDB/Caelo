import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// The application name. Not translated.
  ///
  /// In en, this message translates to:
  /// **'Caelo'**
  String get appTitle;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @welcomeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Paste an invitation link to connect your account and receive its servers and configurations.'**
  String get welcomeExplanation;

  /// No description provided for @invitationPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'https://…'**
  String get invitationPlaceholder;

  /// No description provided for @invitationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Paste an invitation link'**
  String get invitationEmpty;

  /// No description provided for @invitationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the invitation link'**
  String get invitationInvalid;

  /// No description provided for @invitationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not check the invitation right now'**
  String get invitationUnavailable;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// Dismisses a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @qrLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with QR'**
  String get qrLogin;

  /// No description provided for @qrUnavailableExplanation.
  ///
  /// In en, this message translates to:
  /// **'QR sign-in is not available yet. Use an invitation link.'**
  String get qrUnavailableExplanation;

  /// No description provided for @importOwnConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Import your own configuration file'**
  String get importOwnConfiguration;

  /// No description provided for @configurationFileInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid WireGuard .conf file'**
  String get configurationFileInvalid;

  /// No description provided for @forgetAccount.
  ///
  /// In en, this message translates to:
  /// **'Disconnect account'**
  String get forgetAccount;

  /// No description provided for @selectedServer.
  ///
  /// In en, this message translates to:
  /// **'Current server'**
  String get selectedServer;

  /// No description provided for @chooseServer.
  ///
  /// In en, this message translates to:
  /// **'Choose server'**
  String get chooseServer;

  /// Main screen status, tunnel is down and idle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get statusDisconnected;

  /// Main screen status, a connection attempt is in progress.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get statusConnecting;

  /// Main screen status, traffic is going through the tunnel.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// Main screen status, the tunnel is being torn down.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get statusDisconnecting;

  /// Main screen status, the attempt failed and we gave up.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get statusFailed;

  /// Shown under the main button when the privileged service speaks an older protocol than the app. Retrying will not help; the service is replaced by installing.
  ///
  /// In en, this message translates to:
  /// **'The Caelo background service is older than this app. Reinstall Caelo to update it.'**
  String get serviceOlderThanApp;

  /// Shown under the main button when the privileged service was updated and the app was not, which happens when a package manager upgraded one half.
  ///
  /// In en, this message translates to:
  /// **'This app is older than the Caelo background service. Update Caelo.'**
  String get appOlderThanService;

  /// Accessibility label for the main button when disconnected.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Accessibility label for the main button when connected.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// Small text under the status naming the node in use.
  ///
  /// In en, this message translates to:
  /// **'via {node}'**
  String viaNode(String node);

  /// Small text naming the protocol and its round-trip time.
  ///
  /// In en, this message translates to:
  /// **'{protocol} · {ping} ms'**
  String protocolAndPing(String protocol, int ping);

  /// Label above the real node reported by the core on Home.
  ///
  /// In en, this message translates to:
  /// **'Current connection'**
  String get currentConnection;

  /// Measured round-trip latency reported by the core.
  ///
  /// In en, this message translates to:
  /// **'{ping} ms'**
  String latency(int ping);

  /// Shown instead of a node name when nothing is configured.
  ///
  /// In en, this message translates to:
  /// **'No subscription yet'**
  String get noSubscription;

  /// Button that opens the subscription link entry.
  ///
  /// In en, this message translates to:
  /// **'Add subscription'**
  String get addSubscription;

  /// Shown under the status when no tunnel configuration has been added.
  ///
  /// In en, this message translates to:
  /// **'No configuration yet'**
  String get noConfig;

  /// Settings row for the AmneziaWG .conf the app connects with.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configuration;

  /// No description provided for @configurationName.
  ///
  /// In en, this message translates to:
  /// **'Configuration name'**
  String get configurationName;

  /// No description provided for @configurationEmoji.
  ///
  /// In en, this message translates to:
  /// **'Flag or emoji'**
  String get configurationEmoji;

  /// No description provided for @configurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Server description'**
  String get configurationDescription;

  /// No description provided for @customServerDescription.
  ///
  /// In en, this message translates to:
  /// **'User configuration'**
  String get customServerDescription;

  /// No description provided for @configurationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Paste a configuration'**
  String get configurationEmpty;

  /// No description provided for @addConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Add configuration'**
  String get addConfiguration;

  /// No description provided for @customConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Custom config'**
  String get customConfiguration;

  /// Value shown for the configuration row when one has been saved.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get configurationInstalled;

  /// Value shown for the configuration row when nothing has been saved.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get configurationNone;

  /// Placeholder in the configuration editor.
  ///
  /// In en, this message translates to:
  /// **'Paste an AmneziaWG .conf here'**
  String get configurationPlaceholder;

  /// Shown under the configuration editor. The private key is written to disk in the clear.
  ///
  /// In en, this message translates to:
  /// **'Stored unencrypted in the app\'s container. Use a key you are willing to rotate.'**
  String get configurationWarning;

  /// Saves the pasted configuration.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Deletes the stored configuration.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Shown while connected. The tunnel runs on a userspace stack, so it carries no traffic from other applications.
  ///
  /// In en, this message translates to:
  /// **'This process only — other apps are not routed yet'**
  String get localTunnelOnly;

  /// Action that discards the current node and picks another one.
  ///
  /// In en, this message translates to:
  /// **'Reconnect differently'**
  String get reconnectDifferently;

  /// Settings screen title and the button that opens it.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Settings section for subscription links.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// Settings row for the interface language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appearanceLanguage;

  /// Language option that follows the operating system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// Always use the Russian interface locale.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRussian;

  /// Always use the English interface locale.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Settings section with version and licence information.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Settings row showing the application version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// Settings row showing the version of the Go core the app is linked against.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get core;

  /// Shown in place of a core version when the library could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'not loaded'**
  String get coreUnavailable;

  /// Settings row showing the licence the app ships under.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get licence;

  /// Settings row linking to the public repository.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// Closes a sheet or a modal screen.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Settings row for the light/dark colour scheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Follow the operating system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Always the light scheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Always the dark scheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Settings section holding the theme and the language.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Settings section for troubleshooting.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// Title of the log screen.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log'**
  String get diagnosticLog;

  /// Switch that turns diagnostic recording on.
  ///
  /// In en, this message translates to:
  /// **'Record a diagnostic log'**
  String get diagnosticLogOn;

  /// Explains what recording does and what it keeps.
  ///
  /// In en, this message translates to:
  /// **'Off by default. While on, connection events are kept on this device so a problem can be reported. Keys are never recorded; server addresses are.'**
  String get diagnosticLogNote;

  /// Opens the log screen.
  ///
  /// In en, this message translates to:
  /// **'View log'**
  String get viewLog;

  /// Copies the log to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logCopy;

  /// Deletes everything recorded.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logClear;

  /// Shares the log as a file.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get logExport;

  /// Shown briefly after copying.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get logCopied;

  /// Shown briefly after clearing.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get logCleared;

  /// Shown when recording is on but nothing has happened.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet'**
  String get logEmpty;

  /// Shown when recording is off.
  ///
  /// In en, this message translates to:
  /// **'Recording is off'**
  String get logDisabled;

  /// Settings section header for update behaviour.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updates;

  /// Settings switch that allows Caelo to ask whether a newer build exists.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// Footer under the update switch, describing exactly what is sent.
  ///
  /// In en, this message translates to:
  /// **'Caelo asks a static file whether a newer version exists. The request carries no identifier and is the same from every installation, and it goes through the tunnel when one is up. Turning this off stops it being sent at all.'**
  String get updateCheckNote;

  /// Settings row that asks for an update check immediately.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// Settings row while an update check is in flight.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// Result of a check that found nothing newer.
  ///
  /// In en, this message translates to:
  /// **'Caelo is up to date'**
  String get updateCurrent;

  /// Title of the dialog offering an update.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateFound(String version);

  /// Button that starts fetching the update.
  ///
  /// In en, this message translates to:
  /// **'Download ({size} MB)'**
  String updateDownload(String size);

  /// Row text while the update is being fetched.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get updateDownloading;

  /// Shown once Android has been asked to install; the outcome is not ours to know.
  ///
  /// In en, this message translates to:
  /// **'Handed to the installer'**
  String get updateInstalling;

  /// Shown when REQUEST_INSTALL_PACKAGES has not been granted.
  ///
  /// In en, this message translates to:
  /// **'Android needs permission to install updates from Caelo.'**
  String get updateNeedsPermission;

  /// Button that opens the Android screen granting install permission.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get updateOpenSettings;

  /// Shown when signature verification failed. Deliberately does not speculate about why.
  ///
  /// In en, this message translates to:
  /// **'That download was not signed by Caelo, so it was discarded.'**
  String get updateNotOurs;

  /// Shown when the update could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The download did not finish.'**
  String get updateFailed;

  /// Shown when the file downloaded and verified but the system installer could not be started. Deliberately says the download is not the problem.
  ///
  /// In en, this message translates to:
  /// **'Caelo could not start the installer. The download is fine; Android would not open it.'**
  String get updateHandOverFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
