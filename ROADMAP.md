# Roadmap

_Last synced with code: 2026-07-10 (commit `c820a4b`)_

**Status legend:** ✅ Done · 🚧 Partial (shipped but narrower than the description below) · 🔜 Planned (not started) · 🧭 Exploring / Considering (not committed)

## Project Principles

To ensure `rails-preflight` remains a trusted tool for planning and estimation, we adhere to the following core principles. These rules guide development and prevent scope creep.

The OSS core is and will remain:

*   **Read-only:** It never modifies your code.
*   **Deterministic:** Results are reproducible.
*   **Static-analysis based:** No runtime side effects.
*   **Clarity over completeness:** It prefers actionable insights over exhaustive noise.
*   **Deep analysis over automation:** Professional features focus on understanding risk, not auto-fixing it.

## Roadmap Structure

The roadmap is organized into three concurrent tracks rather than sequential versions, reflecting the project's maturity and different user needs.

*   ✅ **Core (OSS)**
*   🧠 **Advanced Analysis (Professional / Power users)**
*   🧰 **Ecosystem & Integrations**

## ✅ Core (OSS)

Features that benefit every user and reinforce the tool's foundational trust.

### Near Term (v1.1)

**Report Clarity & Trust**
*   ✅ **Metric Separation:** Explicitly distinguish between production vs. test code occurrences.
*   ✅ **Ruby Analysis:** Better differentiation between version compatibility issues and lifecycle (EOL) risks.
*   ✅ **Refined Summary:** Clearer terminology (e.g., distinguishing "deprecation types" from "total occurrences").
*   🚧 **Confidence Indicators:** Section-level HIGH/MEDIUM/LOW badges are shipped, but the report footer legend still only explains Severity and Fix Effort — it doesn't explain what the confidence levels mean yet.

**Analysis Depth**
*   🚧 **Database Checks:** `utf8`/`utf8mb3` and integer-ID (bigint) rules exist, but are only wired up for a target Rails version of `6.0` — auditing any other target gets zero database checks. 191-byte index limits and integer overflow risks are not implemented yet.
*   ✅ **Config Gaps:** improved detection of missing `config.load_defaults`.
*   🚧 **Path Suggestions:** A suggested upgrade path is generated, but it does not yet recommend intermediate Rails versions (e.g., 5.2 → 6.1 → 7.1) — only start and target are named.
*   ✅ **Docker/OpenSSL ABI Mismatch:** Detects Alpine ≥3.17 paired with Ruby <3.1 (OpenSSL 3.0 incompatibility). *(Moved up from Advanced Analysis — this shipped already.)*

### Medium Term (v1.2)

**Static Analysis Improvements**
*   ✅ **Smarter Grouping:** Deprecation warnings are aggregated by message.
*   🚧 **False Positive Suppression:** Method-definition lines are skipped; symbol-only references are not yet suppressed.
*   🔜 **Scope Flags:** Introduction of `--exclude-tests` and `--only-production` flags. No CLI flag parsing exists yet.

**New Analyzers**
*   🔜 **Routes Analyzer:** Scan `config/routes.rb` for deprecated routing DSL (e.g. `match` without `via:`, unconstrained wildcard routes). Currently the only section of a Rails app never inspected. *(Idea sourced from `jm/rails_upgrade`.)*
*   🔜 **Known-Incompatible Gems List:** A curated, version-independent list of public gems known to be broken/superseded for a given Rails jump (`paperclip`, `protected_attributes`, `therubyracer`, etc.), distinct from the existing "is this gem private" heuristic. *(Idea sourced from `jm/rails_upgrade`.)*

**Output**
*   🔜 **JSON Support:** Machine-readable output for programmatic consumption.
*   🔜 **Stable Schema:** A guaranteed output format for CI integrations.

## 🧠 Advanced Analysis

Deeper, specialized analysis for complex upgrades. These features remain read-only.

### Upgrade Path Intelligence
*   🚧 *Exploring:* Suggested phased upgrade plans. (A single-step suggested path already ships — see Core > Path Suggestions — but it isn't phased/multi-hop yet.)
*   🧭 *Exploring:* Risk deltas per Rails jump.
*   🧭 *Considering:* "Minimum viable upgrade" vs. "modern Rails" comparison.

### Dependency Risk Profiling
*   🚧 **Blast Radius:** Occurrence/file/model/controller breakdowns already ship for **deprecation warnings**. The private-gem version of this ("usage counts and critical path analysis" per gem) is not implemented — private gems today are just named, not scored.
*   🧭 *Under Evaluation:* Native extension risk scoring.

### Test & CI Awareness
*   🔜 **Framework Compatibility:** Detection of incompatible test framework patterns.
*   🚧 **Environment Consistency:** Ruby version is read from `.ruby-version`, Dockerfile, or system Ruby — whichever is found first — but the sources are never cross-checked against each other for disagreement, and CI config (e.g. `.github/workflows`) isn't parsed at all yet.

### Confidence Scoring
*   ✅ **Granular Confidence:** Every analyzer section reports its own confidence level.
*   🚧 **Completeness Signal:** An ad hoc "Analysis Incomplete" message exists for gem-scan errors only; there's no general Partial-vs-Complete indicator across all sections yet.

## 🧰 Ecosystem & Integrations (Longer Term)

Optional integrations to fit into broader workflows.

*   🧭 *Considering:* SARIF output for IDE/GitHub code scanning support.
*   🧭 *Considering:* CI annotations to fail builds on "High Risk" findings.
*   🧭 *Under Evaluation:* Multi-app comparison mode.
*   🧭 *Under Evaluation:* Report diffing between runs.

## Non-Goals

To maintain trust and focus, the following are explicitly **NOT** on the roadmap:

*   ❌ **Automatic migrations**
*   ❌ **AST-based refactoring in core**
*   ❌ **"One-click upgrade" solutions**
*   ❌ **Runtime instrumentation**
