import 'package:flutter/cupertino.dart';

import '../../theme/palette.dart';

/// The shared page treatment.
///
/// It is intentionally built from Flutter primitives rather than Material: the
/// Cupertino application shell remains authoritative while the colour and
/// composition stay identical on every platform.
class CaeloPageSurface extends StatelessWidget {
  const CaeloPageSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.background,
            Color.lerp(palette.background, palette.surface2, 0.32)!,
            palette.background,
          ],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: child,
    );
  }
}

/// Prevents forms and lists from becoming an unreadably wide strip on desktop.
class CaeloContentWidth extends StatelessWidget {
  const CaeloContentWidth({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: CaeloSize.contentMaxWidth),
      child: child,
    ),
  );
}

/// A branded raised surface used by cards, forms and diagnostic panels.
class CaeloPanel extends StatelessWidget {
  const CaeloPanel({
    required this.child,
    this.padding,
    this.margin,
    this.radius = CaeloRadius.cardAll,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface1,
        borderRadius: radius,
        border: Border.all(
          color: palette.border.withValues(alpha: 0.72),
          width: CaeloStroke.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: palette.brightness == Brightness.dark ? 0.18 : 0.06,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// An icon-only action with the same hit target and surface on every platform.
class CaeloIconButton extends StatelessWidget {
  const CaeloIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(CaeloSize.minimumTarget),
        onPressed: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surface1.withValues(alpha: 0.9),
            border: Border.all(
              color: palette.border.withValues(alpha: 0.72),
              width: CaeloStroke.hairline,
            ),
          ),
          child: SizedBox.square(
            dimension: CaeloSize.minimumTarget,
            child: Icon(
              icon,
              size: 21,
              color: foreground ?? palette.foreground,
            ),
          ),
        ),
      ),
    );
  }
}
