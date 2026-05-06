# Plans Directory — Naming Convention

## Structure

```
.claude/plans/
├── _TEMPLATE/           Meta: templates and guidelines
├── _ARCHIVE/            Completed/superseded plans
└── pXX/                 Plan group (e.g., p03/)
    ├── _INDEX.md        Plan group overview + phase status
    ├── _RESEARCH/       Research artifacts scoped by phase
    │   └── NN/          Phase subfolder (e.g., 01/, 02.1/)
    │       ├── N.N_description.md
    │       └── N.N_description/    (asset folder)
    └── NN/              Phase folder (e.g., 01/, 02/)
        └── NN_description_YYYYMMDD.md
```

## Naming Patterns

| Element         | Pattern                        | Example                            |
| --------------- | ------------------------------ | ---------------------------------- |
| Plan group      | `pXX/`                         | `p03/`                             |
| Phase folder    | `NN/`                          | `p03/01/`                          |
| Phase plan      | `NN_description_YYYYMMDD.md`   | `01_code_review_skill_20260331.md` |
| Sub-phase plan  | `NN.N_description_YYYYMMDD.md` | `02.1_ollama_research_20260402.md` |
| Research folder | `_RESEARCH/NN/`                | `_RESEARCH/01/`                    |
| Research file   | `N.N_description.md`           | `1.1_anthropic_harness_design.md`  |
| Research assets | `N.N_description/`             | `1.1/img_01.png`                   |

## Conventions

- `_` prefix = meta/infrastructure (sorts to top): `_INDEX.md`, `_RESEARCH/`, `_TEMPLATE/`
- Research files are scoped by the phase that generated them
- Asset folders sit alongside their extraction file, named with the same prefix
- Use `git mv` for all moves to preserve history
