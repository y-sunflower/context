# Context — local Ollama chat app (Rust core + SwiftUI)

export MACOSX_DEPLOYMENT_TARGET := "26.0"

app_name := "Context"
bundle := "dist" / app_name + ".app"
rust_lib := "core/target/release/libcontext_core.a"

# List available recipes
default:
    @just --list

# Check the local toolchain and that Ollama is reachable
setup:
    @command -v cargo >/dev/null || (echo "missing: cargo (install rustup)" && exit 1)
    @command -v swift >/dev/null || (echo "missing: swift (install Xcode CLT)" && exit 1)
    @curl -sf http://localhost:11434/api/version >/dev/null \
        || (echo "Ollama is not running — start it with: ollama serve" && exit 1)
    @echo "ok: cargo, swift, ollama"

# Build the Rust core (release)
core:
    cd core && cargo build --release

# Regenerate the UniFFI Swift bindings from the static library
bindings: core
    rm -rf app/Sources/ContextCore app/Sources/ContextCoreFFI
    mkdir -p app/Sources/ContextCore app/Sources/ContextCoreFFI/include
    cd core && cargo run --release --bin uniffi-bindgen-swift -- \
        --swift-sources {{ justfile_directory() }}/{{ rust_lib }} \
        {{ justfile_directory() }}/app/Sources/ContextCore
    cd core && cargo run --release --bin uniffi-bindgen-swift -- \
        --headers --modulemap --module-name context_coreFFI \
        --modulemap-filename module.modulemap \
        {{ justfile_directory() }}/{{ rust_lib }} \
        {{ justfile_directory() }}/app/Sources/ContextCoreFFI/include
    echo '// SPM requires at least one source file in a C target.' \
        > app/Sources/ContextCoreFFI/stub.c

# Build everything: Rust core -> bindings -> Swift app
build: bindings
    cd app && swift build -c release

# Assemble and ad-hoc sign dist/Context.app
bundle: build
    rm -rf {{ bundle }}
    mkdir -p {{ bundle }}/Contents/MacOS
    cp app/.build/release/{{ app_name }} {{ bundle }}/Contents/MacOS/
    cp app/Info.plist {{ bundle }}/Contents/
    codesign --force --sign - {{ bundle }}
    @echo "built {{ bundle }}"

# Build, bundle, and launch the app
run: bundle
    open {{ bundle }}

# Build and install into /Applications
install: bundle
    rm -rf /Applications/{{ app_name }}.app
    ditto {{ bundle }} /Applications/{{ app_name }}.app
    @echo "installed /Applications/{{ app_name }}.app"

# Remove the app from /Applications (keeps your chat history)
uninstall:
    rm -rf /Applications/{{ app_name }}.app

# Build, bundle, and run in the foreground (logs on stdout)
dev: bundle
    ./{{ bundle }}/Contents/MacOS/{{ app_name }}

# Run the Rust tests
test:
    cd core && cargo test

# Format Rust (and Swift, if swift-format is available)
fmt:
    cd core && cargo fmt
    @command -v swift-format >/dev/null \
        && swift-format -i -r app/Sources/Context || true

# Lint the Rust core
lint:
    cd core && cargo clippy --all-targets -- -D warnings

# Remove build artifacts
clean:
    cd core && cargo clean
    cd app && swift package clean
    rm -rf dist

# Delete the app's local database (chat history!)
db-reset:
    rm -f ~/Library/Application\ Support/Context/context.db*
    @echo "database removed"
