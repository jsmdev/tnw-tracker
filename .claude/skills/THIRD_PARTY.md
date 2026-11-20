# Third-party agent skills

The skill folders in this directory are vendored copies of MIT-licensed third-party agent skills. They were copied by hand from a shallow clone of each source repository at the commit listed below (no plugin installer, no `npx skills`). Each folder keeps the upstream MIT notice as `LICENSE`.

Apple's agent skills (for example `swiftui-whats-new-27`, `app-intents-specialist` and `xctrace`) are not vendored here. They stay at user level, outside this public repository.

| Skill | Source | Commit | License | Copyright | Local modifications |
|---|---|---|---|---|---|
| `swiftui-expert-skill` | https://github.com/AvdLee/SwiftUI-Agent-Skill (`skills/swiftui-expert-skill`) | `62bd760f005093d1e2e4de5db156e456a5f96400` | MIT | 2026 Antoine van der Lee | `references/soft-deprecation.md`: an explicit user request for notes now wins over the scoping rule; `references/latest-apis.md`: the upstream maintenance skill is marked as not vendored. |
| `swift-concurrency` | https://github.com/AvdLee/Swift-Concurrency-Agent-Skill (`skills/swift-concurrency`) | `3b1580d8398e0b5408b3bf0bada0e941a1cfc642` | MIT | 2026 Antoine van der Lee | None; added `LICENSE`. |
| `swift-testing-expert` | https://github.com/AvdLee/Swift-Testing-Agent-Skill (`swift-testing-expert`) | `798e9b1a2bcac164d4f0c781908199e754f0bab6` | MIT | 2026 Antoine van der Lee | None; added `LICENSE`. |
| `swiftdata-pro` | https://github.com/twostraws/SwiftData-Agent-Skill (`swiftdata-pro`) | `8051f177a0076e7fd45bdf4ee687b070ba58fdc6` | MIT | 2026 Paul Hudson | None; added `LICENSE`. |
| `ios-accessibility` | https://github.com/dadederk/iOS-Accessibility-Agent-Skill (`ios-accessibility`) | `dcc3a36ce1d0099341d545c1af4eb5a8c989bf66` | MIT | 2025 Daniel Devesa Derksen-Staats | None; added `LICENSE` (same text as the bundled `LICENSE.txt`). |
| `widgets` | https://github.com/n0an/Widgets-Agent-Skill (`widgets`) | `06567e152df00df1db50a2935bbe62fda9e27c19` | MIT | 2026 Anton Novoselov | `references/live-activities.md`: the checklist now says `Activity.request` is synchronous `throws` (only `update`/`end` are async), and a note on iOS 26 scheduled Live Activities (`start:` overload) was added, checked against the ActivityKit `.swiftinterface` in the Xcode 27.2 SDK; `references/configuration-and-intents.md` now points to the `app-intents-specialist` skill name. |
| `axiom-health` | https://github.com/charleswiltgen/Axiom (`.claude-plugin/plugins/axiom/skills/axiom-health`) | `ffafd3b3e0dbaaa60b753ca4a835ae6603b873e1` | MIT | 2025 Charles Wiltgen | Forced-usage opening line rewritten as a plain description; local note that the other Axiom suites are not installed. |
| `axiom-watchos` | https://github.com/charleswiltgen/Axiom (`.claude-plugin/plugins/axiom/skills/axiom-watchos`) | `ffafd3b3e0dbaaa60b753ca4a835ae6603b873e1` | MIT | 2025 Charles Wiltgen | Same as `axiom-health`, plus: removed the auto-generated block pointing to Axiom MCP tools that are not installed, replaced the `modernization-helper` agent / `/axiom:modernize` section in `skills/modernization.md` with a plain residue check, and toned down "ANY" in the description. |
| `codebase-design` | https://github.com/mattpocock/skills (`skills/engineering/codebase-design`) | `5863806dd4e15c63174bee4e7515a4256792ecfa` | MIT | 2026 Matt Pocock | `DEEPENING.md` testing strategy: existing tests that pin previous behavior are kept; a test is removed only when its behavior is intentionally removed (heading and the matching `SKILL.md` link text adjusted). |
| `improve-codebase-architecture` | https://github.com/mattpocock/skills (`skills/engineering/improve-codebase-architecture`) | `5863806dd4e15c63174bee4e7515a4256792ecfa` | MIT | 2026 Matt Pocock | None; added `LICENSE`. It depends on `codebase-design`, `grilling` and `domain-modeling`, all installed under those names. |
| `domain-modeling` | https://github.com/mattpocock/skills (`skills/engineering/domain-modeling`) | `5863806dd4e15c63174bee4e7515a4256792ecfa` | MIT | 2026 Matt Pocock | None; added `LICENSE`. |
| `grilling` | https://github.com/mattpocock/skills (`skills/productivity/grilling`) | `5863806dd4e15c63174bee4e7515a4256792ecfa` | MIT | 2026 Matt Pocock | Asks one question at a time and waits for the answer, instead of numbered multi-question rounds (`SKILL.md` and `agents/openai.yaml`). |

## Notes

- `swiftui-expert-skill/scripts/` contains Python helpers that only invoke the local `xctrace` CLI. They make no network calls. Review them before running.
- `swift-concurrency` links to the author's paid course with UTM-tagged URLs.
- `improve-codebase-architecture/HTML-REPORT.md` builds a report outside the repository that loads Tailwind and Mermaid from public CDNs.
- To update a skill, re-clone its source at a newer commit, diff it against the folder here, reapply the modifications above, and update this table.
