# Roadmap

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
*   **Metric Separation:** Explicitly distinguish between production vs. test code occurrences.
*   **Ruby Analysis:** Better differentiation between version compatibility issues and lifecycle (EOL) risks.
*   **Refined Summary:** Clearer terminology (e.g., distinguishing "deprecation types" from "total occurrences").
*   **Confidence Indicators:** Adding a legend to the report to explain confidence levels.

**Analysis Depth**
*   **Database Checks:** Expanded detection for `utf8` vs `utf8mb4`, 191-byte index limits, and integer overflow risks.
*   **Config Gaps:** improved detection of missing `config.load_defaults`.
*   **Path Suggestions:** Recommended intermediate Rails versions (e.g., 5.2 → 6.1 → 7.1).

### Medium Term (v1.2)

**Static Analysis Improvements**
*   **Smarter Grouping:** Better aggregation of related deprecation warnings.
*   **False Positive Suppression:** Ignoring method definitions and symbol-only references.
*   **Scope Flags:** Introduction of `--exclude-tests` and `--only-production` flags.

**Output**
*   **JSON Support:** Machine-readable output for programmatic consumption.
*   **Stable Schema:** A guaranteed output format for CI integrations.

## 🧠 Advanced Analysis

Deeper, specialized analysis for complex upgrades. These features remain read-only.

### Upgrade Path Intelligence
*   *Exploring:* Suggested phased upgrade plans.
*   *Exploring:* Risk deltas per Rails jump.
*   *Considering:* "Minimum viable upgrade" vs. "modern Rails" comparison.

### Dependency Risk Profiling
*   **Blast Radius:** Quantifying private gem risk via usage counts and critical path analysis.
*   *Under Evaluation:* Native extension risk scoring.
*   *Considering:* Ruby ABI / OpenSSL mismatch detection.

### Test & CI Awareness
*   **Framework Compatibility:** Detection of incompatible test framework patterns.
*   **Environment Consistency:** flagging Ruby version mismatches across Docker, CI, and `.ruby-version`.

### Confidence Scoring
*   **Granular Confidence:** Per-section reliability scores.
*   **Completeness Signal:** Indicators for Partial vs. Complete audits.

## 🧰 Ecosystem & Integrations (Longer Term)

Optional integrations to fit into broader workflows.

*   *Considering:* SARIF output for IDE/GitHub code scanning support.
*   *Considering:* CI annotations to fail builds on "High Risk" findings.
*   *Under Evaluation:* Multi-app comparison mode.
*   *Under Evaluation:* Report diffing between runs.

## Non-Goals

To maintain trust and focus, the following are explicitly **NOT** on the roadmap:

*   ❌ **Automatic migrations**
*   ❌ **AST-based refactoring in core**
*   ❌ **"One-click upgrade" solutions**
*   ❌ **Runtime instrumentation**
