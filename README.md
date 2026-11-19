# Ostrich

A QML / [Quickshell](https://quickshell.org/) based rice for Arch Linux.

> Status: **pre-alpha**. The repository is scaffolded (branch model, CI, release
> automation, product requirements). The shell itself has not been implemented yet.

## Documentation

| Document | Purpose |
| --- | --- |
| [PRD.md](PRD.md) | Product requirements: every component the shell must provide. |
| [AGENTS.md](AGENTS.md) | Branch model, release workflow, and rules for agents and humans. |
| [CHANGELOG.md](CHANGELOG.md) | Release history. |

## Branch model

| Branch | Role |
| --- | --- |
| `dev` | Working branch. All commits land here first. Rolling prereleases are published from it. |
| `test` | Release candidates. CI is authoritative here. Only `dev` -> `test` pull requests. |
| `main` | Released versions only. Only `test` -> `main` pull requests. Tagged `vX.Y.Z`. |

Versions are bumped on `dev` (for example `1.1.0` -> `1.2.0`), promoted to `test`
where the full suite runs, and merged to `main` only when every required check
passes. See [AGENTS.md](AGENTS.md) for the exact commands.

## Local checks

```bash
make check     # validate + lint + compile + test + review
make format    # format QML sources in place
```

Build dependencies on Arch Linux:

```bash
sudo pacman -S --needed git qt6-declarative shellcheck base-devel
# Quickshell (AUR):
yay -S quickshell
```

## License

[MIT](LICENSE)
