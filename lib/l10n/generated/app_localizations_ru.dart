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
  String get welcome => 'Добро пожаловать';

  @override
  String get welcomeExplanation =>
      'Вставьте ссылку приглашения, чтобы подключить аккаунт и получить его серверы и конфигурации.';

  @override
  String get invitationPlaceholder => 'https://…';

  @override
  String get invitationEmpty => 'Вставьте ссылку приглашения';

  @override
  String get invitationInvalid => 'Проверьте ссылку приглашения';

  @override
  String get invitationUnavailable => 'Сейчас не удалось проверить приглашение';

  @override
  String get continueAction => 'Продолжить';

  @override
  String get cancel => 'Отмена';

  @override
  String get qrLogin => 'Войти по QR';

  @override
  String get qrMockExplanation =>
      'Камера и backend аккаунтов пока не подключены. Продолжить с временной локальной демо-сессией?';

  @override
  String get mockBackendNotice =>
      'Временный режим: приглашения и QR проверяются локально до готовности backend.';

  @override
  String get importOwnConfiguration => 'Добавить свой файл конфигурации';

  @override
  String get configurationFileInvalid =>
      'Выберите корректный файл WireGuard .conf';

  @override
  String get forgetAccount => 'Отключить аккаунт';

  @override
  String get selectedServer => 'Текущий сервер';

  @override
  String get chooseServer => 'Выберите сервер';

  @override
  String get serverListMockNotice =>
      'Тестовые серверы до подключения backend аккаунта';

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
  String get currentConnection => 'Текущее подключение';

  @override
  String latency(int ping) {
    return '$ping мс';
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
  String get configurationName => 'Название конфигурации';

  @override
  String get configurationEmoji => 'Флаг или эмодзи';

  @override
  String get configurationDescription => 'Описание сервера';

  @override
  String get customServerDescription => 'Пользовательская конфигурация';

  @override
  String get configurationEmpty => 'Вставьте конфигурацию';

  @override
  String get addConfiguration => 'Добавить конфигурацию';

  @override
  String get customConfiguration => 'Свой конфиг';

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
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

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

  @override
  String get theme => 'Тема';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get appearance => 'Оформление';

  @override
  String get diagnostics => 'Диагностика';

  @override
  String get diagnosticLog => 'Журнал диагностики';

  @override
  String get diagnosticLogOn => 'Вести журнал диагностики';

  @override
  String get diagnosticLogNote =>
      'По умолчанию выключено. Пока включено, события подключения хранятся на этом устройстве, чтобы проблему можно было показать. Ключи не записываются, адреса серверов — да.';

  @override
  String get viewLog => 'Посмотреть журнал';

  @override
  String get logCopy => 'Скопировать';

  @override
  String get logClear => 'Очистить';

  @override
  String get logExport => 'Выгрузить';

  @override
  String get logCopied => 'Скопировано';

  @override
  String get logCleared => 'Очищено';

  @override
  String get logEmpty => 'Пока ничего не записано';

  @override
  String get logDisabled => 'Запись выключена';
}
