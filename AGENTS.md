# Repository Guidelines

## Project Structure & Module Organization

Context is a native macOS chat application with two main layers. `core/` contains the Rust library for Ollama streaming, SQLite persistence, and the UniFFI boundary; its code lives in `core/src/`, with a smoke example in `core/examples/`. `app/` is the Swift Package Manager project: SwiftUI screens and state are under `app/Sources/Context/`, while `app/Info.plist` and `app/AppIcon.icns` define bundle metadata and branding. UniFFI generates `app/Sources/ContextCore/` and `app/Sources/ContextCoreFFI/`; regenerate these rather than editing them. Source artwork is in `assets/`, automation in `scripts/`, and assembled applications in the ignored `dist/` directory.

## Build, Test, and Development Commands

Use the repository `justfile` as the main task interface:

- `just setup` checks for Rust, Swift, and a reachable local Ollama server.
- `just build` builds the Rust core, regenerates UniFFI bindings, and compiles the Swift app.
- `just dev` bundles the app and runs it in the foreground with logs visible.
- `just test` runs the Rust test suite.
- `just lint` runs Clippy with warnings treated as errors.
- `just fmt` formats Rust and, when installed, Swift via `swift-format`.
- `just bundle` creates and ad-hoc signs `dist/Context.app`.

Building requires macOS 26+, Swift 6.2+, stable Rust, `just`, and Ollama.

## Coding Style & Naming Conventions

Accept `cargo fmt` output for Rust and keep the code Clippy-clean. Use four-space indentation in Swift and run `swift-format` when available. Follow language conventions: `snake_case` for Rust functions and modules, `UpperCamelCase` for Rust types and Swift types, and `lowerCamelCase` for Swift properties and methods. Keep UI responsibilities in focused SwiftUI view files and database/chat behavior in the corresponding Rust modules.

## Testing Guidelines

Rust unit tests currently live beside implementation code, notably in `core/src/db.rs`, using `#[cfg(test)]` and descriptive `snake_case` names. Add regression tests near changed core behavior and run `just test` before submitting. There is no stated coverage threshold. For UI changes, also run `just bundle` and manually verify the relevant flow with Ollama running.

## Commit & Pull Request Guidelines

Recent commits use short, lowercase, action-oriented summaries such as `update readme` and `move release script`. Keep each commit focused and use a similarly concise subject. Pull requests should explain the user-visible effect, identify validation performed, and link relevant issues. Include screenshots or a short recording for SwiftUI changes. Ensure the CI-equivalent checks—formatting, `just lint`, `just test`, and `just bundle`—pass before requesting review.
