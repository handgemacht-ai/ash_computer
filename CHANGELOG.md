# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-06-24

### Fixed
- Declare the `__spark_metadata__` field on the `Computer`, `Input`, `Val` and
  `Event` DSL entity structs so Spark 2.7+ can attach source annotations without
  emitting a deprecation warning.

## [0.1.0] - 2025-10-06

### Added
- Initial release
- Reactive computation DSL powered by Spark
- Automatic dependency resolution from compute functions
- Event system for complex state mutations
- Phoenix LiveView integration via `AshComputer.LiveView`
- Compile-time safe event references in templates
- Support for chained computations
- Support for stateful computers
- Executor API for managing multiple computers
- Manual computer input updates via `update_computer_inputs/3` and `update_computers/2`

[Unreleased]: https://github.com/handgemacht-ai/ash_computer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/handgemacht-ai/ash_computer/releases/tag/v0.1.0

<!-- changelog -->

## [v0.3.0](https://github.com/handgemacht-ai/ash_computer/compare/v0.2.1...v0.3.0) (2026-10-15)

### Features:

* events: side effects for computer events. An event declared with `run` (arity 3: values, params, `AshComputer.Context`) and `handle_result` (arity 3: result, values, params) runs its effect synchronously and turns the `{:ok, _}` or `{:error, _}` result into input changes. A crash inside `run` is not rescued. Pure events (`handle`) work as before.
* add `AshComputer.Context` (`actor`, `tenant`, `extra`), `AshComputer.Reply` (input changes, flash, navigate, patch, redirect and client events, with builder functions) and `AshComputer.EventRunner`.
* add `AshComputer.dispatch_event/6,7` and `AshComputer.map_result/6,7`, with the `as:` option for computers attached under an alias.
* add a compile-time check of event definitions: exactly one of `handle` or `run`, `handle_result` required with `run` and not allowed without it, and the arity of each capture.
* live_view: add the optional `computer_context/1` callback, which builds the context for effect events from the socket on every event. The context is never stored in the assigns.
* live_view: add `run_event/4` to run an event from `mount/3`, `handle_info/2` or any other callback.
* live_view: apply the reply of an event to the socket: input changes are synced to assigns, then flash messages, client events and the navigation, patch or redirect are carried out. A reply that asks for more than one of navigate, patch and redirect raises.
* live_view: effect events work on computers attached with `attach_computer ..., as:`.

### Changed:

* live_view: an event that changes a non-input is now refused with an `ArgumentError`, as `apply_event` already did. Events may change only inputs.
* live_view: `phoenix_live_view` is now required as `~> 1.1.8 or ~> 1.2` (was `~> 1.1.8`).
* The canonical repository is `handgemacht-ai/ash_computer`; `source_url` and the `git_ops` repository URL point to it. The package is installed from GitHub with `tag: "v0.3.0"`; it is not published on Hex.

### Known limitations:

* An input set to `nil` or `false` takes its `initial` value again. Inputs that carry results or errors should start as `nil`. This is planned to be fixed in a later release.

### Chores:

* Fix the findings of the project checks: formatting, credo, dialyzer, ex_doc (no reference to the hidden `AshComputer.Builder` module) and sobelow.
* Update the dependency lock file to clear `mix hex.audit` advisories: mint 1.11.0 (with hpax 1.1.0), phoenix 1.8.15, plug 1.20.3 (with plug_crypto 2.2.0), lazy_html 0.1.13, req 0.7.5 and usage_rules 1.2.8. `usage_rules` is a dev-only dependency now required as `~> 1.2`. Other locked packages were updated along with them.
* Correct the README: the install line, the `handgemacht-ai` links and a description of effects.

## [v0.2.0](https://github.com/handgemacht-ai/ash_computer/compare/v0.1.0...v0.2.0) (2025-10-15)




### Features:

* live_view: add support for attaching external computers