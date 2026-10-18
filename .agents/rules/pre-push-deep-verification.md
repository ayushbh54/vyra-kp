---
description: Enforces mandatory multi-layer deep verification (static analysis, compilation, test suites, config audit) before any git push across all projects.
trigger: always_on
---

# Mandatory Deep Pre-Push Verification Protocol

Before pushing any code changes to a remote repository (`git push`) or publishing releases in ANY project (new or existing), the agent MUST execute this comprehensive 5-phase verification protocol. Never push unverified code.

## Phase 1 — Scope & Diff Audit
1. Run `git status --short` and `git diff --stat HEAD` to inspect every modified, added, and deleted file.
2. Verify that:
   - No unintended temporary files, build artifacts, or secret keys are staged.
   - All referenced new files exist on disk and are tracked by git.

## Phase 2 — Static Analysis & Lint Check
Run the project's static analysis or linting suite according to its tech stack:
- **Flutter / Dart:** `flutter analyze` — MUST report `No issues found!`.
- **Node.js / TypeScript:** `npm run lint` or `tsc --noEmit` — MUST be clean with 0 errors.
- **Python:** `ruff check` / `flake8` / `mypy` as configured in the project.
- **Kotlin / Android:** Review any compiler/lint warnings and resolve deprecations.

## Phase 3 — Clean Compilation & Build Integrity
Verify that all affected modules compile cleanly without fatal errors:
- **Android / Kotlin:** `./gradlew compileDebugKotlin` or `./gradlew assembleDebug` — MUST exit with `BUILD SUCCESSFUL`.
- **Flutter:** Verify platform builds or codegen if applicable (`build_runner`, etc.).
- **Backend / Web:** Run build step (`npm run build`, `cargo check`, `go build ./...`).

## Phase 4 — Automated Test Suite Execution
Execute the automated test suites and ensure 100% pass rate:
- **Flutter:** `flutter test --no-pub` — all unit and widget tests must pass.
- **Android / JVM:** `./gradlew testDebugUnitTest` — all unit tests must pass.
- **Node / Python:** `npm test` or `pytest` — all tests must pass.
- If any test fails, diagnose the root cause, fix the issue, and re-run until all tests pass.

## Phase 5 — Runtime, Security & Configuration Sanity Check
Inspect sensitive system contracts:
1. **Network & HTTP Policy:** Ensure cleartext HTTP rules (e.g., `network_security_config.xml`, CORS policies) allow required LAN or internal traffic without breaking HTTPS requirements.
2. **Component Registration:** Ensure any newly introduced Services, Receivers, Providers, or Routes are registered in manifest/config files (e.g., `AndroidManifest.xml`).
3. **Behavioral Invariants:** Ensure background services remain silent where expected (e.g., using silent `PackageInstaller` sessions instead of user-facing `ACTION_VIEW` prompts).
4. **Backend Health Check:** If external APIs or backends are connected, verify key endpoints respond with expected status codes (e.g. HTTP 200/302).

## Final Sign-Off
Only after Phases 1 through 5 succeed with zero failures:
1. Commit changes with a detailed semantic message describing the exact changes and verification results.
2. Execute `git push origin <branch>`.
3. Monitor CI/CD workflow status (e.g. GitHub Actions) to confirm build completion.
