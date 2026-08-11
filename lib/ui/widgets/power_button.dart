import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/tunnel.dart';
import '../../theme/palette.dart';

/// The main action and the visual centre of Home.
///
/// Its label describes the real [phase]; no timer or optimistic local state is
/// involved. The controller remains the only thing that can change the phase.
class PowerButton extends StatefulWidget {
  const PowerButton({
    required this.phase,
    required this.label,
    required this.onPressed,
    required this.semanticLabel,
    super.key,
  });

  final TunnelPhase phase;
  final String label;
  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with TickerProviderStateMixin {
  late final AnimationController _activity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Listenable _animations = Listenable.merge([_activity, _glow]);

  bool _pressed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _syncAnimations();
  }

  @override
  void didUpdateWidget(PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) _syncAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _syncAnimations();
  }

  void _syncAnimations() {
    if (widget.phase.isBusy && !_reduceMotion) {
      _activity.repeat();
    } else {
      _activity.stop();
      _activity.value = 0;
    }

    if (widget.phase == TunnelPhase.connected && !_reduceMotion) {
      _glow.repeat(reverse: true);
    } else {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _activity.dispose();
    _glow.dispose();
    super.dispose();
  }

  Gradient _gradient(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected => RadialGradient(
      colors: [
        palette.accent,
        Color.lerp(palette.accent, palette.foreground, 0.1)!,
      ],
      center: const Alignment(-0.25, -0.35),
      radius: 0.95,
    ),
    TunnelPhase.failed => RadialGradient(
      colors: [palette.surface1, palette.dangerSurface],
      center: const Alignment(-0.25, -0.35),
      radius: 0.95,
    ),
    _ => RadialGradient(
      colors: [
        palette.surface1,
        Color.lerp(palette.surface2, palette.primary, 0.16)!,
      ],
      center: const Alignment(-0.25, -0.35),
      radius: 0.95,
    ),
  };

  Color _border(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected => palette.accentBorder,
    TunnelPhase.failed => palette.dangerBorder,
    TunnelPhase.connecting || TunnelPhase.disconnecting => palette.accentBorder,
    TunnelPhase.disconnected => palette.primary,
  };

  Color _content(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected =>
      palette.brightness == Brightness.dark
          ? palette.background
          : const Color(0xFFFFFFFF),
    TunnelPhase.failed => palette.danger,
    TunnelPhase.connecting || TunnelPhase.disconnecting => palette.foreground,
    TunnelPhase.disconnected => palette.primary,
  };

  Color _labelContent(CaeloPalette palette) =>
      widget.phase == TunnelPhase.disconnected &&
          palette.brightness == Brightness.light
      ? const Color(0xFF101414)
      : _content(palette);

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final diameter = (shortestSide * 0.68).clamp(220.0, 268.0).toDouble();
    final content = _content(palette);
    final labelContent = _labelContent(palette);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: widget.label == widget.semanticLabel ? null : widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: _reduceMotion ? Duration.zero : CaeloMotion.quick,
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: _animations,
            builder: (context, child) {
              final connected = widget.phase == TunnelPhase.connected;
              return SizedBox.square(
                dimension: diameter * 1.16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (connected)
                      Transform.scale(
                        scale: 1 + 0.07 * _glow.value,
                        child: Container(
                          width: diameter * 1.11,
                          height: diameter * 1.11,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.accent.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CaeloMotion.standard,
                      curve: Curves.easeOut,
                      width: diameter,
                      height: diameter,
                      foregroundDecoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _border(palette),
                          width:
                              connected ||
                                  widget.phase == TunnelPhase.disconnected
                              ? 3
                              : CaeloStroke.emphasis,
                        ),
                      ),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _gradient(palette),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (connected ? palette.accent : palette.primary)
                                    .withValues(alpha: connected ? 0.28 : 0.22),
                            blurRadius: connected ? 52 : 32,
                            spreadRadius: connected ? 5 : 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        foregroundPainter: widget.phase.isBusy
                            ? _ProgressRingPainter(
                                rotation: _activity.value,
                                color: palette.accent,
                                staticRing: _reduceMotion,
                              )
                            : null,
                        child: child,
                      ),
                    ),
                  ],
                ),
              );
            },
            child: AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : CaeloMotion.quick,
              child: Column(
                key: ValueKey(widget.phase),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.power,
                    size: (diameter * 0.29).clamp(60.0, 72.0).toDouble(),
                    color: content,
                  ),
                  SizedBox(height: diameter * 0.07),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: diameter * 0.12),
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelContent,
                        fontSize: (diameter * 0.1).clamp(21.0, 26.0).toDouble(),
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.rotation,
    required this.color,
    required this.staticRing,
  });

  final double rotation;
  final Color color;
  final bool staticRing;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(inset);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final start = staticRing ? -math.pi / 2 : rotation * math.pi * 2;
    canvas.drawArc(arcRect, start, math.pi * 0.72, false, paint);
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      rotation != oldDelegate.rotation ||
      color != oldDelegate.color ||
      staticRing != oldDelegate.staticRing;
}
