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
