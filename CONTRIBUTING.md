# Contributing to Unified Dev

Thanks for your interest in contributing.

## Bugs and feature requests

Open an issue at https://github.com/akira-foundation/unified-dev-swift/issues. Include:

- What you expected to happen.
- What actually happened.
- A minimal reproduction.
- Versions: Unified Dev, macOS, and the agent CLI involved.

## Working on a pull request

1. Fork the repository and create a branch from `develop`. `main` receives release merges only.
2. Add tests for the change. A decision that needs a test belongs in `Sources/Core`, not in a view.
3. Run `make lint`, `make swiftlint`, `make build` and `make test` before pushing, and
   `make test-browser` when the change touches the browser scripts. Zero warnings.
4. Use conventional commit messages: the changelog is generated from them via
   [git-cliff](https://git-cliff.org).
5. Open the pull request against `develop`. Keep the diff focused: refactors, feature work and
   dependency bumps belong in separate pull requests.

[CLAUDE.md](CLAUDE.md) is the full working agreement, and
[.github/workflows/branch-policy.yml](.github/workflows/branch-policy.yml) says which base each
branch prefix may target.

## Style

- Match the existing project conventions: `make lint` and `make swiftlint` are the source of truth.
- No comments in code beyond a one line `// TODO:`.
- British spelling, and no em dashes or en dashes anywhere.
- No drive-by refactors in feature pull requests.
- No emojis in code, copy, commit messages or pull request descriptions.

## Licence

By contributing, you agree that your contributions will be licensed under the GNU Affero General
Public License v3, as described in [LICENSE](LICENSE).
