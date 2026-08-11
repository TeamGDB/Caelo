import 'package:caelo/theme/palette.dart';
import 'package:caelo/ui/widgets/caelo_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget shell(Widget child, {Size size = const Size(1280, 800)}) {
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: CaeloColors(
            palette: CaeloPalette.dark,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('desktop content stays in the shared maximum width', (
    tester,
  ) async {
    const content = Key('content');
    await tester.pumpWidget(
      shell(
        const CaeloContentWidth(
          child: SizedBox(key: content, width: double.infinity, height: 20),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(content)).width,
      CaeloSize.contentMaxWidth,
    );
  });

  testWidgets('content can shrink below the desktop maximum', (tester) async {
    const content = Key('content');
    await tester.pumpWidget(
      shell(
        const CaeloContentWidth(
          child: SizedBox(key: content, width: double.infinity, height: 20),
        ),
        size: const Size(320, 640),
      ),
    );

    expect(tester.getSize(find.byKey(content)).width, 320);
  });

  testWidgets('icon actions expose a 48 pixel target and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        UnconstrainedBox(
          child: CaeloIconButton(
            icon: CupertinoIcons.gear_alt,
            semanticLabel: 'Settings',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CaeloIconButton)),
      const Size.square(CaeloSize.minimumTarget),
    );
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('branded surfaces are built without Material widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const CaeloPageSurface(
          child: Center(child: CaeloPanel(child: Text('Caelo'))),
        ),
      ),
    );

    expect(find.text('Caelo'), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
  });
}
