# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/marot/ash_computer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/marot/ash_computer/releases/tag/v0.1.0
