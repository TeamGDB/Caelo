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
- **The initial language follows the operating system.** Settings offers
  explicit Russian and English choices, applies them without restarting the
  application and stores the choice in the existing local settings file.
- **Settings stays in the upper-right safe area.** Mobile system insets are
  respected by `SafeArea`; macOS additionally reserves room for Caelo's
  transparent title bar. No platform-specific screen variant is introduced.

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
: Is the single-purpose centre of Home. It scales from 176 to 224 logical
  pixels, renders the real tunnel phase inside the control, and uses a
  palette-driven progress ring or connected glow. Nonessential motion is
  disabled when the operating system requests reduced motion.

`Home connection panel`
: Appears only after the core reports a node. It may show that node, protocol
  and measured latency, but it must not invent flags, server grades or fallback
  measurements. An interactive server selector waits for an explicit core API.

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
