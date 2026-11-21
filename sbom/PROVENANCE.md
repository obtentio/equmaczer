# equmaczer — Provenance Ledger

Generated from the repository's own git evidence on 2026-11-13.
Machine-readable companion: `equmaczer.spdx.json` (SPDX 2.3) in
this directory. Method: full-history author census, merge-base
reconciliation against both upstreams, and content diffs at the
fork points. A ScanCode/REUSE pass has not been run; this ledger
is the git-evidence layer of Gate C, with that scan still open.

## Chain of title

| Component | Upstream origin | Fork evidence |
| :--- | :--- | :--- |
| Swift application | `cvknage/equaliser` | merge-base `8472be63f6c08333c21338da0c2be36ea2694234` (2026-06-16, the merge of upstream PR #5) |
| C HAL driver | `ExistentialAudio/BlackHole` | base commit `11efc147fef0ac537be1c24ea7e29e4b2a2d63c7` (2025-12-18); imported whole at commit `0695bc2` with the modifier's own 373-line patch preserved in history; the imported file differs from the base by 224 lines |
| Everything since | obtentio | 37 commits on this side of the merge-base |

## Authorship census (264 commits)

| Author | Commits | Standing |
| :--- | ---: | :--- |
| Christophe Knage | 227 | upstream author; credited |
| obtentio owner | 23 | obtentio |
| obtentio engineer | 13 | obtentio |
| crimist | 1 | upstream contributor; credited |

## Rulings recorded

- **crimist's commit** (window registration via
  `WindowActivationController`, merged as upstream PR #5) is real,
  load-bearing feature work that the current tree still builds on.
  Ruling: **keep and credit** — it appears in the About pane's
  legal acknowledgements.
- **The driver's modifier alias is "logic"**: the original patch
  header reads "Modified for Equaliser by logic", which is why the
  driver's CoreAudio manufacturer string is the literal word
  `logic` today. It is renamed in the identity slice (Slice 4).
- **Licence variant**: the tree carries the unmodified GPL-3.0
  text at the root and no per-file grant language, so whether the
  grant is GPL-3.0-only or GPL-3.0-or-later cannot be settled from
  the tree alone. The SBOM records `GPL-3.0-only` as the concluded
  licence (the conservative reading); distribution complies with
  v3 under either reading.
- **File classes in this SBOM**: {'upstream': 133, 'mixed': 45, 'driver': 2, 'ours': 43} — "driver" files carry
  the three-party copyright (Existential Audio, Knage, obtentio);
  "mixed" files carry upstream + obtentio; "ours" files are
  obtentio alone; "upstream" files are unmodified upstream work.
