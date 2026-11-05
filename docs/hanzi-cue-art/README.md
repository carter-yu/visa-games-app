# Hanzi cue art source (H0)

`illustrations.svg` and `illustration-style.css` are byte-for-byte copies of
`visa-games-design/hanzi-tap/v2/assets/` (design D8: one shared SVG token style). The only addition
to the design run-2 sprite is `tree` / `tree-2` for 木 (six-target addendum, 2026-11-06), drawn with
the existing tokens only.

- `Resources/HanziTap/hanzi-pack.json` names each target's two `cuePictures`; every name is a public
  `<symbol id>` here (checked by `HanziGlyphTests`).
- Colours come from the token sheet's CSS classes. `tree` / `tree-2` use those classes only, with no
  inline colours or `style` attributes (checked by `HanziGlyphTests`). One existing symbol does
  override palette tokens inline: `left-hand-2` sets `--skin: #e9b37e` and `--skin-shade: #d69a65`
  in the `style` of its `.ill` group (the second hand skin tone), and `right-hand-2` mirrors
  `left-hand-2`, so it inherits them. A converter has to apply that override. (`car-top` also sets
  `--outline: 4` and `--detail-outline: 3` inline; those are stroke widths, not colours.)
- Nothing in the app draws the sprite yet: the native `HanziCueArt` provider and its converter are
  H2 work. The letter boards' emoji word art is not reused for Hanzi.
- Edit the design copy first, then copy both files here unchanged.
