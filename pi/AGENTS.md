# Coding Instructions

## Workflow

- Keep each commit focused, reviewable, and independently buildable.
- Commit as you go. Stop and ask for human review only when uncommitted changes grow too large to review in one pass.

## Implementation

- Choose simplest readable solution that meets current requirements. Avoid speculative abstractions and flexibility.
- Prefer straightforward code over clever tricks while preserving required performance.
- Prefer self-explanatory names and structure. Add comments only for non-obvious reasons or constraints that code cannot express; explain why, not what.
- Before extracting code used once or spanning one line, check whether inlining is clearer. Inline by default; extract only when it materially improves readability.
- Avoid interfaces for single implementations. Add one only for a real substitution boundary, such as multiple implementations, a required test double, or implementations that genuinely change often.
- Do not abstract dependencies for hypothetical replacement. Assume infrastructure such as database technology stays unless requirements say otherwise.
- Use narrowest available visibility: `private`, then package/internal, then `public`. Never widen production visibility only for testing.
- Prefer precise types. Use `any`, `dynamic`, or equivalent loose types only when no safer alternative exists.

## Tests

- Unit tests and in-process UI tests (such as component or widget tests) are allowed without asking when they do not use a browser, physical device, emulator, or simulator.
- Do not run or delegate tests that use a browser, physical device, emulator, or simulator unless explicitly requested or called for by `/pr`. This includes Playwright (even headless) and ADB, even when invoked through a project's test suite.
- Test code behavior, not language, runtime, or framework guarantees.
- Do not test trivial constructors that only assign inputs, trivial accessors, or equivalent boilerplate.
- Test through observable behavior. If a test requires exposing an internal solely for testing, do not add that test.
