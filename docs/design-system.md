# Caelo design system

Caelo uses one visual language on every supported platform without changing
its Flutter architecture to Material. `CupertinoApp`, Cupertino navigation and
Cupertino controls remain the application shell. Brand-specific presentation
is built from Flutter primitives and the semantic tokens in
`lib/theme/palette.dart`.

## Decisions

- **Cupertino remains authoritative.** Do not introduce `MaterialApp` or
  platform-adaptive screen variants.
- **Typography remains system-native.** The shared size and weight scale gives
  the hierarchy a consistent shape without adding a bundled font to downloads.
- **Material icon fonts are not shipped.** Use `CupertinoIcons`; add a reviewed
  bundled SVG/PNG only when the existing set cannot express a product concept.
- **Tokens are semantic.** Components choose `control`, `card` or `dialog`
  rather than adding a radius for each mock-up measurement.
- **Product logic does not enter the design layer.** The shared widgets render
  state and forward intent; node selection and connection decisions remain in
  the Go core.

## Shared primitives

`CaeloPageSurface`
: Gives pages the same subtle palette-derived background without Material.

`CaeloContentWidth`
: Keeps forms and lists within 560 logical pixels on desktop while allowing
  them to shrink to the available mobile width.

`CaeloPanel`
: The common raised surface for settings sections, forms and diagnostic
  content.

`CaeloIconButton`
: A cross-platform icon action with a 48 × 48 logical-pixel hit target and an
  explicit semantic label.

`PowerButton`
: Remains the compact single-purpose control defined by the project. Its
  gradient, borders and glow are palette-driven; nonessential pulse motion is
  disabled when the operating system requests reduced motion.

## Adding a component

1. Reuse a semantic token before adding a value.
2. Build brand-specific visuals from `widgets`, not Material components.
3. Provide semantics and a minimum 48 × 48 interactive area.
4. Test compact and desktop constraints, light and dark palettes, and reduced
   motion when the component animates.
5. Keep network and account decisions outside the widget.

Pixel-for-pixel reproduction of the Android Compose prototype is not a goal
when it conflicts with these rules. The target is the same hierarchy, palette,
states and interaction quality across platforms while preserving Caelo's
existing architecture.
