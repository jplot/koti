# Contributing to koti

koti is a monorepo: each SDK lives in its own folder (`hue-sdk/`, …) and is published as its
own gem. The rules below apply to every folder.

## Setup

Each gem is developed from its own folder, with Ruby 4.0 or later, except `ajax-sdk`, which runs on
Ruby 3.4 because the `grpc` and `google-protobuf` gems ship precompiled binaries only up to 3.4:

```sh
cd hue-sdk
bundle install
bundle exec rake
```

`bundle exec rake` must pass before every commit. It runs RuboCop, RSpec (95 % line coverage
overall, 70 % per file), the YARD documentation check (100 %), RBS validation and Steep.

## Code

- Follow the shared `.rubocop.yml`; disable a cop only with a comment giving the reason.
- A method whose body is a single expression is written as an endless method:
  `def name = expression`.
- Use hash and keyword shorthand: `foo(bar:)`, never `foo(bar: bar)`.
- Every public method has YARD documentation and an RBS signature in `sig/`.
- A comment explains a reason the code cannot show, with the figure or case behind it. It never
  restates what the code does.
- Never commit data from a real home (bridge ids, addresses, names, keys) or a secret. Local
  secrets go in the git-ignored `.env`.

## Tests

- Write the failing spec first and watch it fail, then make it pass.
- Prefer real local fakes (a local HTTPS bridge, a local server) to mocks.
- Code that deals with threads, connections or other shared resources gets a spec with real
  threads, seen failing before the fix.
- Live specs (`:live`) run against real devices and must never change their state.

## Commits

Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
type(scope): description
```

- **type** is one of `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore` or
  `revert`. Add `!` after the scope for a breaking change.
- **scope** is the gem folder (`hue-sdk`). Leave it out for a change to the whole repository.
- **description** is in English, lower case, in the imperative mood, without a final period.
- The whole header is at most 72 characters.
- One commit holds one coherent change of a single type: documentation and specs go in separate
  commits.
- The body, when there is one, explains why the change is needed.
- Every commit is signed (`git config commit.gpgsign true`). Unsigned commits are not accepted.

Examples:

```
feat(hue-sdk): stream bridge events with automatic reconnection
fix(hue-sdk): repeat the mdns query so a lost packet does not hide the bridge
docs: add contributing guide
```

## Branches and pull requests

- Never push to `main` directly. Work on a branch named `type/short-description`
  (`feat/hue-sdk`, `docs/contributing`).
- One topic per pull request. Its title follows the commit convention, and its description has
  three sections: Summary, Changes, How to Test.
- A pull request is merged once every CI check is green, with a merge commit (no squash, no
  rebase), so that every signed commit is kept as it is.
- Record user-facing changes in the gem's `CHANGELOG.md`, under `[Unreleased]`, following
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## License

By contributing, you agree that your contributions are licensed under the
[Mozilla Public License 2.0](LICENSE).
