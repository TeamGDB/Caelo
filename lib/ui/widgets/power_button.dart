import 'package:flutter/cupertino.dart';

import '../../core/tunnel.dart';
import '../../theme/palette.dart';

/// The button. There is only one, and it is the reason the app exists.
///
/// It reports state through colour and motion rather than words — the words
/// live underneath it, in the status line. Connected is the only time anything
/// on screen glows.
class PowerButton extends StatefulWidget {
  const PowerButton({
    required this.phase,
    required this.onPressed,
    required this.semanticLabel,
    super.key,
  });

  final TunnelPhase phase;
  final VoidCallback onPressed;
  final String semanticLabel;

  static const _diameter = 132.0;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool _pressed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _syncPulse();
  }

  /// The ring breathes only while the outcome is unknown. Once the tunnel
  /// settles either way, motion stops — a screen that keeps animating reads as
  /// "still working on it".
  void _syncPulse() {
    if (widget.phase.isBusy && !_reduceMotion) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _fill(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected => palette.accentSurface,
    TunnelPhase.failed => palette.dangerSurface,
    _ => palette.surface2,
  };

  Gradient _gradient(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected => RadialGradient(
      colors: [
        palette.accent,
        Color.lerp(palette.accent, palette.foreground, 0.1)!,
      ],
      center: const Alignment(-0.25, -0.35),
      radius: 0.95,
    ),
    _ => RadialGradient(
      colors: [palette.surface1, _fill(palette)],
      center: const Alignment(-0.25, -0.35),
      radius: 0.95,
    ),
  };

  Color _border(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected => palette.accentBorder,
    TunnelPhase.failed => palette.dangerBorder,
    _ => palette.surface3,
  };

  Color _glyph(CaeloPalette palette) => switch (widget.phase) {
    TunnelPhase.connected =>
      palette.brightness == Brightness.dark
          ? palette.background
          : const Color(0xFFFFFFFF),
    TunnelPhase.failed => palette.danger,
    TunnelPhase.connecting || TunnelPhase.disconnecting => palette.muted,
    TunnelPhase.disconnected => palette.dim,
  };

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: _reduceMotion ? Duration.zero : CaeloMotion.quick,
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final glowAlpha = switch (widget.phase) {
                TunnelPhase.connected => 0.22,
                _ when widget.phase.isBusy => 0.05 + 0.10 * _pulse.value,
                _ => 0.0,
              };

              return AnimatedContainer(
                duration: _reduceMotion ? Duration.zero : CaeloMotion.standard,
                curve: Curves.easeOut,
                width: PowerButton._diameter,
                height: PowerButton._diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _gradient(palette),
                  border: Border.all(
                    color: _border(palette),
                    width: widget.phase == TunnelPhase.connected
                        ? CaeloStroke.emphasis
                        : CaeloStroke.hairline,
                  ),
                  boxShadow: glowAlpha == 0
                      ? null
                      : [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: glowAlpha),
                            blurRadius: widget.phase == TunnelPhase.connected
                                ? 48
                                : 36,
                            spreadRadius: widget.phase == TunnelPhase.connected
                                ? 4
                                : 1,
                          ),
                        ],
                ),
                child: child,
              );
            },
            child: Center(
              child: AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : CaeloMotion.quick,
                child: Icon(
                  CupertinoIcons.power,
                  key: ValueKey(_glyph(palette)),
                  size: 46,
                  color: _glyph(palette),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
