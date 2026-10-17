# Recorded voice clips (v0.28.0, ADR 0017)

Optional. Drop `<key>.m4a` files here to replace the macOS Cantonese voice (Sinji) for
一架一架數. `scripts/bundle.sh` copies every `*.m4a` into the app. A key with no clip keeps
using the system voice; with no Cantonese voice installed it stays silent (never Mandarin).

| key | says |
|---|---|
| `number.1.yue` … `number.10.yue` | 一 … 十 (one word per tap) |
| `number.1` … `number.10` (+ `number.N.en.m4a`) | 「三、three」 bubble word, English clip optional |
| `tapCount.total.N.gaa` (+ `.en`) | 「四架！」 / "Four!" |
| `tapCount.pick.recount.N` | 「一、二、三、四。四架。」 |
| `tapCount.pick.need.N` | 「要三架喎！」 |

Keys come from `TapCountCopy` (`SpokenPrompt.key`). Record mono AAC, 44.1 kHz, short silence trimmed.
