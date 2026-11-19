# Tests

Ostrich uses [Qt Quick Test](https://doc.qt.io/qt-6/qtquicktest-index.html) for
headless, deterministic tests.

## Layout

```
tests/
├── tst_<area>.qml        # test cases (the `tst_` prefix is required)
├── fixtures/             # shared QML fixtures and mock services
└── README.md
```

## Running

```bash
make test
# equivalent to:
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests -import .
```

CI runs the same command inside an Arch Linux container. Tests must not require a
real compositor, audio device, Bluetooth adapter, or network connection.

## Conventions

- One test case file per component or service, named `tst_<component>.qml`.
- Mock external services; never shell out to system tools in tests.
- Keep tests independent: no shared mutable state between cases.
- Cover component logic and state transitions, not pixel-perfect rendering.
- Every bug fix should add a regression test; every new component should ship
  with at least one test.
- Use `SignalSpy`, `tryCompare`, and `TestCase` helpers rather than sleeps.

## CI behavior

The `test` job passes when there are no test files yet, so the repository stays
green during scaffolding. Once the first `tst_*.qml` file lands, failures block
merges into `test` and `main` (see `AGENTS.md`).
