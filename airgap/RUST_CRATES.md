# Rust Crates for Offline Development

This directory contains a `Cargo.toml` file with popular Rust crates that will be bundled for offline development.

## How It Works

When you run `get_bundle.sh`:

1. The script looks for `Cargo.toml` in the `airgap/` directory
2. If found, it copies it to `airgap_bundle/rust/crates/Cargo.toml`
3. It runs `cargo vendor` to download and bundle all dependencies
4. All crates are stored in `airgap_bundle/rust/crates/vendor/`

## Included Crates

The `Cargo.toml` includes popular Rust libraries organized by category:

### Async Runtime
- `tokio` - Async runtime
- `async-std` - Alternative async runtime
- `futures` - Future abstractions

### Serialization
- `serde` - Serialization framework
- `serde_json` - JSON support
- `toml` - TOML parsing
- `yaml-rust` - YAML parsing

### HTTP Clients
- `reqwest` - HTTP client
- `ureq` - Simple blocking HTTP client

### CLI Tools
- `clap` - Command-line argument parser
- `structopt` - Derive-based CLI parser

### Error Handling
- `anyhow` - Flexible error handling
- `thiserror` - Derive-based error types
- `color-eyre` - Colored error reports

### Logging
- `tracing` - Structured logging
- `tracing-subscriber` - Tracing subscribers
- `log` - Logging facade
- `env_logger` - Environment-based logger

### File I/O
- `walkdir` - Directory traversal
- `glob` - Path globbing
- `pathdiff` - Path differences

### String Processing
- `regex` - Regular expressions
- `lazy_static` - Lazy static initialization

### Data Structures
- `indexmap` - Hash map with insertion order
- `dashmap` - Concurrent hash map
- `rayon` - Data parallelism

### Date/Time
- `chrono` - Date and time library
- `time` - Time library

### Cryptography
- `sha2` - SHA-2 hashing
- `md5` - MD5 hashing
- `rand` - Random number generation
- `uuid` - UUID generation

### Database
- `rusqlite` - SQLite bindings

### Testing
- `mockall` - Mocking framework
- `proptest` - Property-based testing

### Configuration
- `config` - Configuration management
- `dotenv` - Environment variable loading

### Network
- `url` - URL parsing
- `ipnet` - IP network types

### System
- `sysinfo` - System information
- `duct` - Process execution
- `which` - Find executables
- `dirs` - Standard directories

### Utilities
- `bytes` - Byte buffer utilities
- `smallvec` - Small vector optimization
- `indicatif` - Progress bars
- `console` - Terminal utilities
- `flate2` - Compression
- `zip` - ZIP file handling
- `csv` - CSV parsing
- `pulldown-cmark` - Markdown parsing

## Customizing

To add or remove crates:

1. Edit `airgap/Cargo.toml`
2. Re-run `get_bundle.sh`
3. The new dependencies will be downloaded and bundled

## Using Bundled Crates in Your Project

After installation on the airgapped machine:

1. Copy `Cargo.toml` and `Cargo.lock` from `airgap_bundle/rust/crates/` to your project
2. Copy the vendor directory:
   ```bash
   cp -r airgap_bundle/rust/crates/vendor /path/to/your/project/
   ```
3. Add to your project's `Cargo.toml`:
   ```toml
   [source.crates-io]
   replace-with = "vendored-sources"
   
   [source.vendored-sources]
   directory = "vendor"
   ```
4. Build offline:
   ```bash
   cargo build --offline --frozen
   ```

## Notes

- The bundled crates are for **offline development only**
- You can add your own crates to `Cargo.toml` before running `get_bundle.sh`
- Some crates are commented out (like web frameworks) - uncomment if needed
- The bundle size will depend on which crates you include
