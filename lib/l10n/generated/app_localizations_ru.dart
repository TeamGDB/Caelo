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
  String get serviceOlderThanApp =>
      'Служба Caelo старее приложения. Переустановите Caelo, чтобы обновить её.';

  @override
  String get appOlderThanService =>
      'Приложение старее службы Caelo. Обновите Caelo.';

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
  String get serverPreparing => 'Готовим подключение…';

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

  @override
  String get updates => 'Обновления';

  @override
  String get checkForUpdates => 'Проверять обновления';

  @override
  String get updateCheckNote =>
      'Caelo спрашивает у статического файла, есть ли версия новее. Запрос не содержит идентификаторов и одинаков у всех установок, а когда поднят туннель — идёт через него. Выключатель прекращает отправку, а не прячет ответ.';

  @override
  String get checkNow => 'Проверить сейчас';

  @override
  String get updateChecking => 'Проверяем…';

  @override
  String get updateCurrent => 'У вас последняя версия';

  @override
  String updateFound(String version) {
    return 'Доступна версия $version';
  }

  @override
  String updateDownload(String size) {
    return 'Скачать ($size МБ)';
  }

  @override
  String get updateDownloading => 'Скачиваем…';

  @override
  String get updateInstalling => 'Передано установщику';

  @override
  String get updateNeedsPermission =>
      'Android должен разрешить Caelo устанавливать обновления.';

  @override
  String get updateOpenSettings => 'Открыть настройки';

  @override
  String get updateNotOurs => 'Скачанный файл не подписан Caelo и был удалён.';

  @override
  String get updateFailed => 'Скачивание не завершилось.';

  @override
  String get updateHandOverFailed =>
      'Не удалось запустить установщик. Файл скачан и проверен — его не открыл Android.';

  @override
  String get automaticServer => 'Автоматически';

  @override
  String get automaticServerDescription => 'Выбирается сам';

  @override
  String get automaticallyChosen => 'Выбран автоматически';

  @override
  String get noServers => 'Серверов пока нет. Добавьте подписку в настройках.';

  @override
  String get noServerReachable =>
      'Ни один сервер не ответил. Проверьте интернет и попробуйте ещё раз.';

  @override
  String get chosenServerUnreachable =>
      'Этот сервер не отвечает. Выберите другой или «Автоматически».';

  @override
  String get forgetAccountTitle => 'Отключить аккаунт?';

  @override
  String get forgetAccountMessage =>
      'Серверы и конфигурации будут удалены с этого устройства. Чтобы вернуться, понадобится ссылка приглашения.';

  @override
  String get forgetAccountConfirm => 'Отключить';

  @override
  String get updateNotInstalled => 'Обновление не установилось';

  @override
  String get updateNotInstalledExplanation =>
      'Если вы отменили установку, ничего страшного — можно попробовать ещё раз. Если Android сообщил о конфликте пакетов, удалите Caelo и установите новую версию со страницы релизов.';

  @override
  String get updateTryAgain => 'Попробовать снова';

  @override
  String get subscriptionGone =>
      'Подписка больше не действует. Получите новую ссылку приглашения и вставьте её: Настройки → Отключить аккаунт.';

  @override
  String get connectionLost =>
      'Сервер перестал отвечать, а другие тоже не ответили.';

  @override
  String get serverMaintenance => 'На обслуживании';

  @override
  String get serverNotIssued =>
      'Сейчас недоступен: сервер не выдал подключение';

  @override
  String chosenServerRemoved(String name) {
    return 'Сервер $name удалён из подписки. Выберите другой или нажмите ещё раз — подключимся автоматически.';
  }

  @override
  String get qrPointCamera => 'Наведите камеру на QR-код подписки в панели';

  @override
  String get qrNotInvitation =>
      'Это не QR-код приглашения Caelo. Откройте подписку в панели и отсканируйте её код.';

  @override
  String get qrCameraUnavailable =>
      'Камера недоступна. Разрешите Caelo пользоваться камерой в настройках телефона или вставьте ссылку приглашения.';

  @override
  String get updateInstallationNotStarted => 'Установка не началась';

  @override
  String get updateWindowsInstallerStopped =>
      'Возможно, вы отменили запрос разрешения Windows, или установщик не смог продолжить. Caelo остаётся открытым. Можно попробовать ещё раз.';

  @override
  String get updateInstall => 'Обновить';

  @override
  String get updateInstallingNow => 'Устанавливаем обновление…';

  @override
  String get updateLinuxFailed =>
      'Обновление не установилось. Можно обновить вручную: sudo apt upgrade (или sudo dnf upgrade caelo).';

  @override
  String get updateWindowsHandOverFailed =>
      'Не удалось запустить установщик. Файл скачан и проверен — попробуйте ещё раз или запустите установщик со страницы релизов.';

  @override
  String get serviceNeedsRelogin =>
      'Caelo пока не может обратиться к своей службе. Выйдите из системы и войдите снова (или перезагрузитесь), чтобы сеанс получил выданный доступ.';

  @override
  String get serviceNeedsGroup =>
      'Caelo не может обратиться к своей службе: нет доступа. Выполните в терминале: sudo usermod -aG caelo \$USER — затем выйдите из системы и войдите снова.';

  @override
  String get linkAddTitle => 'Добавить подписку?';

  @override
  String linkAddMessage(String host) {
    return 'Ссылка от $host. Caelo будет подключаться через серверы этой подписки.';
  }

  @override
  String get linkAddConfirm => 'Добавить';

  @override
  String get linkReplaceTitle => 'Заменить подписку?';

  @override
  String linkReplaceMessage(String host) {
    return 'Ссылка от $host. Подписка на этом устройстве будет отключена, а её серверы удалены: вернуть её можно только по её ссылке.';
  }

  @override
  String get linkReplaceConfirm => 'Заменить';

  @override
  String get linkKnownTitle => 'Уже добавлена';

  @override
  String get linkKnownMessage => 'Эта подписка уже есть на этом устройстве.';

  @override
  String get linkFailedTitle => 'Не удалось добавить подписку';

  @override
  String get subscriptionEmpty =>
      'В подписке пока нет серверов. Спросите того, кто дал ссылку.';

  @override
  String subscriptionSkipped(int count, String reasons) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не показано $count серверов: эта версия Caelo их не поддерживает',
      few: 'Не показаны $count сервера: эта версия Caelo их не поддерживает',
      one: 'Не показан $count сервер: эта версия Caelo его не поддерживает',
    );
    return '$_temp0 ($reasons).';
  }
}
