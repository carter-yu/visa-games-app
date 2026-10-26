# Traditional-only check data (W3, design §6.3)

`simplified-only.txt` lists the CJK characters that OpenCC treats as Simplified-only: its
Simplified → Traditional (HK) mapping changes them and its Traditional → Simplified mapping keeps them.
That is the rule of `visa-games-design/weekly-report/mockups/check_traditional.py`, applied to every code
point in U+3400–4DBF, U+4E00–9FFF and U+F900–FAFF. Lines starting with `#` are comments; every other
character is one entry.

- 吓 and 晒 are left out: §6.3 allows these written-Cantonese particles, which the app already ships.
- HK glyph variants (OpenCC t2hk) are not listed, so game titles keep the app's own characters (e.g. 搵).
- The list has no compatibility ideographs and no characters with a Unicode decomposition, so Swift's
  canonical `Character` equality matches the code points.

`testReportStringsTraditionalOnly` (`WeeklyTextTests.swift`) loads the file and requires that no
template, catalogue word or rendered report sentence (verbatim titles and names aside) contains one of
these characters. It also requires the existing `isTraditionalChineseOnly` and `perfTraditionalOnly` checks
to pass.

Regenerate with the python3 `opencc` module (made with `opencc-python-reimplemented` 0.1.7):

```sh
cd Tests/VisaCoreTests/Fixtures/traditional-check
python3 make_simplified_list.py > simplified-only.txt
```

A newer OpenCC dictionary may change the list. Review the diff, then run the checks.
