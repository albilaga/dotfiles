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

- Write and run repeatable project tests with assertions through the project's test runner (for example, Gradle or npm) without asking. This includes UI tests that use a browser, physical device, emulator, or simulator.
- Do not drive a browser or device directly or delegate ad hoc control (for example, clicking with Playwright or tapping with `adb shell input`) unless explicitly requested or called for by `/pr`.
- Test code behavior, not language, runtime, or framework guarantees.
- Do not test trivial constructors that only assign inputs, trivial accessors, or equivalent boilerplate.
- Test through observable behavior. If a test requires exposing an internal solely for testing, do not add that test.
