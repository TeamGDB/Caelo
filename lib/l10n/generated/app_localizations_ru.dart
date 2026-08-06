// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Caelo';

  @override
  String get statusDisconnected => 'Отключено';

  @override
  String get statusConnecting => 'Подключение';

  @override
  String get statusConnected => 'Подключено';

  @override
  String get statusDisconnecting => 'Отключение';

  @override
  String get statusFailed => 'Не удалось подключиться';

  @override
  String get connect => 'Подключить';

  @override
  String get disconnect => 'Отключить';

  @override
  String viaNode(String node) {
    return 'через $node';
  }

  @override
  String protocolAndPing(String protocol, int ping) {
    return '$protocol · $ping мс';
  }

  @override
  String get noSubscription => 'Подписки пока нет';

  @override
  String get addSubscription => 'Добавить подписку';

  @override
  String get noConfig => 'Конфиг не добавлен';

  @override
  String get configuration => 'Конфиг';

  @override
  String get configurationInstalled => 'Добавлен';

  @override
  String get configurationNone => 'Нет';

  @override
  String get configurationPlaceholder => 'Вставь сюда AmneziaWG .conf';

  @override
  String get configurationWarning =>
      'Хранится в контейнере приложения без шифрования. Используй ключ, который не жалко перевыпустить.';

  @override
  String get save => 'Сохранить';

  @override
  String get remove => 'Удалить';

  @override
  String get localTunnelOnly =>
      'Только этот процесс — трафик других приложений пока не идёт';

  @override
  String get reconnectDifferently => 'Переподключиться иначе';

  @override
  String get settings => 'Настройки';

  @override
  String get subscriptions => 'Подписки';

  @override
  String get appearanceLanguage => 'Язык';

  @override
  String get languageSystem => 'Системный';

  @override
  String get about => 'О программе';

  @override
  String get version => 'Версия';

  @override
  String get core => 'Ядро';

  @override
  String get coreUnavailable => 'не загружено';

  @override
  String get licence => 'Лицензия';

  @override
  String get sourceCode => 'Исходный код';

  @override
  String get done => 'Готово';
}
