import 'config_store.dart';
import 'settings_store.dart';
import 'subscription_store.dart';

/// Everything that came with an account, in one place to forget it.
///
/// Appearance, language and the update switch are the person's preferences
/// rather than the account's, and survive.
abstract final class AccountData {
  static Future<void> forget({
    Future<void> Function()? clearSubscriptions,
    Future<void> Function()? clearConfigurations,
    Future<void> Function(String)? writeSelected,
  }) async {
    await (clearSubscriptions ?? SubscriptionStore.clear)();
    await (clearConfigurations ?? ConfigStore.clearAll)();
    await (writeSelected ?? SettingsStore.setSelectedServerId)('');
  }
}
