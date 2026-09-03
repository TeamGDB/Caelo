import 'package:caelo/core/node_chooser.dart';
import 'package:caelo/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

SubscriptionNode node(String tag, int position) => SubscriptionNode(
  id: 'cfg-$tag',
  tag: tag,
  endpoint: '{"type":"amneziawg","tag":"$tag"}',
  position: position,
);

void main() {
  /// Пересоздание стоит дорого: на той стороне провижионится настоящий сервер.
  /// Поэтому просить его можно только имея доказательство, что виноват узел, а
  /// не сеть, — и всё это правило держится на трёх проверках ниже.
  group('когда просить сервер выдать узел заново', () {
    test('узел не ответил, а другой ответил — виноват узел', () async {
      final asked = <String>[];

      final chosen = await NodeChooser.choose(
        among: [node('Amber', 0), node('Mett', 1)],
        probe: (endpoint, {url = '', timeout = Duration.zero}) async {
          if (endpoint.contains('Amber')) throw Exception('не отвечает');
          return {'elapsed_ms': 42};
        },
        reissue: (node) async {
          asked.add(node.tag);
          return true;
        },
      );

      expect(chosen.node.tag, 'Mett');
      // Дать серверу время на запрос, который намеренно не ожидается.
      await Future<void>.delayed(Duration.zero);
      expect(asked, ['Amber']);
    });

    test('не ответил никто — виновата сеть, и трогать нечего', () async {
      final asked = <String>[];

      await expectLater(
        NodeChooser.choose(
          among: [node('Amber', 0), node('Mett', 1)],
          probe: (endpoint, {url = '', timeout = Duration.zero}) async =>
              throw Exception('не отвечает'),
          reissue: (node) async {
            asked.add(node.tag);
            return true;
          },
        ),
        throwsA(isA<NoNodeWorked>()),
      );

      await Future<void>.delayed(Duration.zero);
      // Устройство без сети не подключится никуда, и клиент, который ответил бы
      // на это перевыдачей всего списка, сожрёт подсеть на первом же лифте.
      expect(asked, isEmpty);
    });

    test('ответил первый же — просить нечего', () async {
      final asked = <String>[];

      await NodeChooser.choose(
        among: [node('Amber', 0), node('Mett', 1)],
        probe: (endpoint, {url = '', timeout = Duration.zero}) async => {
          'elapsed_ms': 10,
        },
        reissue: (node) async {
          asked.add(node.tag);
          return true;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(asked, isEmpty);
    });
  });
}
