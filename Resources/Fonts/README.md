# Canvas fonts (child screens)

Bundled so the offline kiosk matches the concept canvas (ADR 0007). `bundle.sh` copies the
fonts and their licences into `Contents/Resources/Fonts/`; `CanvasFont` registers them at
launch and falls back to the system rounded font if they are missing.

| File | Family | Covers | Source (google/fonts, `main`) | Licence |
| --- | --- | --- | --- | --- |
| `Baloo2-VariableFont_wght.ttf` | Baloo 2 (wght 400–800) | Latin, digits | `ofl/baloo2/Baloo2[wght].ttf` | `OFL-Baloo2.txt` (SIL OFL 1.1) |
| `NotoSansHK-VariableFont_wght.ttf` | Noto Sans HK (wght 100–900) | Hong Kong Traditional Chinese | `ofl/notosanshk/NotoSansHK[wght].ttf` | `OFL-NotoSansHK.txt` (SIL OFL 1.1) |

Downloaded 2026-09-29 with the parent's approval. Each file's git blob SHA matched the
GitHub API listing for google/fonts at download time. Files are unmodified; only the file
names changed (the font names inside are untouched).
