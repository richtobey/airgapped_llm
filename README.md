# Airgap Development Environment Bundle

A complete offline development environment for airgapped systems, including AI-powered coding assistance, Python and Rust development tools, and all necessary dependencies.

## 🎯 What This Does

This project creates a self-contained bundle that can be transferred to an airgapped (offline) Linux system, providing:

- **AI Coding Assistant**: VSCodium editor with Continue extension + Ollama (local LLM)
- **Development Tools**: Git, build tools, Python 3, Rust toolchain
- **Language Support**: Python and Rust extensions with full IDE features
- **All Dependencies**: System libraries, Python packages, Rust crates (if provided)
- **Multiple AI Models**: Mistral 7B, Mixtral 8x7B, and quantized variants

Everything works **completely offline** - no internet connection required after initial bundle creation.

### Two Installation Methods

1. **Direct Installation**: Install directly on Pop!_OS/Ubuntu system (traditional method)
2. **VM Bundle**: Pre-configured QEMU/KVM virtual machine with Pop!_OS and airgap bundle (for testing)

## 📁 Project Structure

```bash
airgapped_llm/
├── airgap/              # Airgap bundle scripts (for System76 Pop!_OS)
│   ├── get_bundle.sh   # Create airgap bundle
│   ├── install_offline.sh  # Install bundle on airgapped system
│   ├── requirements.txt    # Python dependencies
│   ├── requirements.txt.example
│   ├── archive/        # Archive scripts for model management
│   │   ├── copy_models.sh
│   │   └── download_missing.sh
│   ├── docs/           # Documentation
│   │   ├── AIRGAP_REVIEW.md
│   │   ├── AIRGAP_PACKAGES.md
│   │   ├── MODEL_RECOMMENDATIONS.md
│   │   └── SYSTEM_LIBRARIES.md
│   ├── airgap_bundle/  # Generated bundle directory (created by get_bundle.sh)
│   └── README.md
├── mac/                 # Mac testing scripts
│   ├── setup_mac_vm.sh  # Setup QEMU/VM on macOS for testing
│   ├── cleanup_mac_vm.sh # Remove VM and cleanup
│   └── README.md
├── LICENSE              # MIT License
├── airgap.code-workspace  # VS Code workspace configuration
└── README.md           # This file
```

## 📋 Requirements

### For Bundle Creation (Online Machine)

- **Pop!_OS or Ubuntu/Debian-based Linux** (amd64) - **REQUIRED**
  - Script requires Linux to build APT repositories, compile Python packages, and vendor Rust crates
  - All components are pre-built on the online system for offline installation
- **Python 3** (for downloading and building packages)
- **Internet connection** (for downloading components)
- **Disk space**: ~35GB+ (for all models and components)
- **Rust/Cargo** (if bundling Rust crates) - will be installed if needed
- **Build tools** (gcc, g++, make, cmake) - will be installed via APT

### For Installation (Airgapped System)

**Direct Installation:**

- **Pop!_OS or Ubuntu/Debian-based Linux** (amd64)
- **sudo access** (for installing packages)
- **Disk space**: ~35GB+ for bundle + installation space
- **Optional**: NVIDIA GPU with 16GB+ VRAM (for GPU acceleration)

## 🚀 Quick Start

### Method 1: Direct Installation (Traditional)

#### Step 1: Create the Bundle (On Online Pop!_OS Machine)

**IMPORTANT**: This script must be run on a Linux system (Pop!_OS/Ubuntu/Debian) with internet access. It will:
- Download all components
- Build APT repository with system packages
- Build Python packages from source into wheels
- Vendor Rust crates (if Cargo.toml exists)
- Pull Ollama models

```bash
# Clone or download this repository
cd airgap

# Navigate to airgap bundle scripts
cd airgap

# Option 1: Use default models (all 3 recommended models)
./get_bundle.sh

# Option 2: Bundle only specific models (faster for testing)
export OLLAMA_MODELS="mistral:7b-instruct"
./get_bundle.sh

# Option 3: Bundle custom Python packages
# Edit airgap/requirements.txt or create your own
export PYTHON_REQUIREMENTS="/path/to/requirements.txt"
./get_bundle.sh

# Option 4: Move models instead of copy (saves disk space)
export MOVE_MODELS=true
./get_bundle.sh
```

The bundle will be created in `./airgap_bundle/` (or `$BUNDLE_DIR` if set).

**Note**: All packages are pre-built during bundle creation, so installation on the airgapped system will be fast and won't require compilation.

#### Step 2: Transfer Bundle to Airgapped System

Move the drive to your air gapped system.

```bash
# Copy the entire bundle directory to external drive/USB
# Ensure you have a drive with 35GB+ free space
cp -r airgap_bundle /path/to/external/drive/
```

#### Step 3: Install on Airgapped System

```bash
# On the airgapped Pop!_OS system
cd /path/to/airgap_bundle

# Run the installation script (installs pre-built packages only)
./install_offline.sh

# Or specify custom bundle location
BUNDLE_DIR=/path/to/airgap_bundle ./install_offline.sh
```

**Note**: Installation is fast because all packages are pre-built. No compilation happens on the airgapped system.

#### Step 4: Start Using

```bash
# Start Ollama server
ollama serve

# In another terminal, verify models
ollama list

# Open VSCodium
codium

# The Continue extension will automatically use Ollama for AI assistance
```

### Method 2: macOS Testing Environment (For Development)

Set up a Pop!_OS VM on macOS to test airgap scripts before deploying to production.

#### Step 1: Setup VM on macOS

```bash
# Navigate to mac scripts directory
cd mac

# Setup QEMU and create Pop!_OS VM
./setup_mac_vm.sh

# This will:
# - Install QEMU via Homebrew (if not installed)
# - Download Pop!_OS ISO (~3GB)
```

#### Step 2: Setup UTM from the Apple Store and then install POP_OS!

View the [readme](mac/README.md) to setup POP_OS! on your Mac

#### Step 3: Start VM and Test

```bash
# Start the VM
./scripts/start_vm.sh

# Inside the VM:
# 1. Copy your airgap bundle to the VM (via network, USB, or shared folder)
# 2. Navigate to bundle and test installation:
cd /path/to/airgap_bundle
sudo ./install_offline.sh

# run software installed with the bundle.
```

**Note for Apple Silicon Macs:**

- Uses x86_64 Pop!_OS (NVIDIA variant) in emulation mode for production testing
- **Why NVIDIA variant on Mac?** Macs don't have NVIDIA GPUs, but we use the NVIDIA variant ISO because:
  - It's the exact same ISO deployed to System76 machines
  - NVIDIA drivers won't cause issues - they just won't be active/used
  - Ensures we test the same installation process and scripts as production
  - We're testing airgap bundle installation, not GPU functionality
- Performance will be slower than native, but accurate for testing

See [`mac/README.md`](mac/README.md) for detailed macOS-specific documentation.

## 📦 What's Included

### Core Applications

- **Ollama**: Local LLM server and runtime
- **VSCodium**: Open-source VS Code fork (privacy-focused)
- **Continue Extension**: AI coding assistant
- **Python Extension**: Full Python IDE support
- **Rust Analyzer Extension**: Full Rust IDE support

### AI Models (Default Bundle)

- `mistral:7b-instruct` (~4GB) - Best for 16GB VRAM
- `mixtral:8x7b` (~26GB) - For 24GB+ VRAM systems
- `mistral:7b-instruct-q4_K_M` (~2GB) - Quantized, saves VRAM

### Development Tools

- Git & Git LFS
- Build tools (gcc, g++, make, cmake, pkg-config)
- Python 3 + pip + venv
- Rust toolchain (rustup-init)
- System utilities (vim, nano, htop, etc.)

### System Libraries

30+ system library packages including:

- Math libraries (BLAS, LAPACK, OpenBLAS) for numpy/scipy
- SSL/TLS libraries for network packages
- Image processing libraries for matplotlib/pillow
- XML/HTML libraries for parsing
- Compression libraries
- Database libraries
- Scientific data format libraries (HDF5, NetCDF)

### Python Packages

All packages from `requirements.txt` plus all transitive dependencies, **pre-built as wheels**:

- Code quality: black, ruff, mypy, pylint
- Testing: pytest, pytest-cov, pytest-mock
- Data science: numpy, pandas
- Web: requests, httpx
- Utilities: pydantic, click, rich, sphinx
- And more (customize `requirements.txt`)

**All packages are compiled into wheels during bundle creation**, so installation on the airgapped system is fast and requires no compilation.

### Rust Crates

If `Cargo.toml` is provided, all Rust dependencies are **vendored** during bundle creation for offline builds. The vendored crates can be used with `cargo build --offline`.

## ⚙️ Configuration

### Environment Variables

#### Bundle Creation (`airgap/get_bundle.sh`)

```bash
# Bundle directory location
export BUNDLE_DIR="/path/to/bundle"

# Models to bundle (space-separated)
export OLLAMA_MODELS="mistral:7b-instruct mixtral:8x7b mistral:7b-instruct-q4_K_M"

# Or single model (backward compatible)
export OLLAMA_MODEL="mistral:7b-instruct"

# Move models instead of copy (saves disk space, removes originals)
export MOVE_MODELS=true

# Python requirements file (default: airgap/requirements.txt)
export PYTHON_REQUIREMENTS="/path/to/requirements.txt"

# Rust Cargo.toml file
export RUST_CARGO_TOML="/path/to/Cargo.toml"
```

#### Installation (`airgap/install_offline.sh`)

```bash
# Bundle directory location
export BUNDLE_DIR="/path/to/airgap_bundle"

# Installation prefix for Ollama
export INSTALL_PREFIX="/usr/local/bin"
```

#### macOS VM Setup (`mac/setup_mac_vm.sh`)

```bash
# VM directory location (default: ~/vm-popos)
export VM_DIR="$HOME/vm-popos"

# VM disk size (default: 50G)
export VM_DISK_SIZE="60G"

# VM memory (default: 4G)
export VM_MEMORY="8G"

# VM CPU count (default: 2)
export VM_CPUS="4"

# Pop!_OS version (optional, auto-detected if not set)
export POPOS_VERSION="22.04"
```

## 📝 Customization

### Adding Python Packages

1. Edit `airgap/requirements.txt`:

```bash
numpy>=1.26.0
pandas>=2.1.0
your-package>=1.0.0
```

1. Re-run bundle creation:

```bash
cd airgap
./get_bundle.sh
```

### Adding Rust Crates

1. Create or copy `Cargo.toml` to the project root

2. Re-run bundle creation:
```bash
cd airgap
./get_bundle.sh
```

### Adding System Packages

1. Edit `airgap/get_bundle.sh`, find `APT_PACKAGES` array (around line 750)
2. Add your packages:

```bash
APT_PACKAGES=(
  # ... existing packages ...
  your-package
  another-package
)
```

3. Re-run `get_bundle.sh` on Pop!_OS to rebuild APT repo with new packages

### Selecting Models

**For 16GB VRAM:**

```bash
cd airgap
export OLLAMA_MODELS="mistral:7b-instruct mistral:7b-instruct-q4_K_M"
./get_bundle.sh
```

**For 24GB+ VRAM:**

```bash
cd airgap
export OLLAMA_MODELS="mistral:7b-instruct mixtral:8x7b"
./get_bundle.sh
```

**Single model (smallest bundle):**

```bash
cd airgap
export OLLAMA_MODEL="mistral:7b-instruct"
./get_bundle.sh
```

## 🔧 Build Requirements

**IMPORTANT**: `get_bundle.sh` **must** be run on a Linux system (Pop!_OS/Ubuntu/Debian) because it:

1. **Builds APT repository** - Requires `apt-get` and `apt-ftparchive`
2. **Builds Python packages** - Compiles source distributions into wheels
3. **Vendors Rust crates** - Requires `cargo` to vendor dependencies
4. **Pulls Ollama models** - Uses Linux Ollama binary

The script will exit with an error if run on macOS or other non-Linux systems.

**Workflow**:
1. Run `get_bundle.sh` on Pop!_OS with internet → builds everything
2. Copy bundle to airgapped machine
3. Run `install_offline.sh` on airgapped machine → installs pre-built packages (no building)

## 🐛 Troubleshooting

### Python Packages Won't Install

**Problem**: Some packages fail to install

**Solutions**:

- All packages should be pre-built as wheels - if installation fails, the bundle may be incomplete
- Re-run `get_bundle.sh` on the online Pop!_OS system to rebuild packages
- Check that system libraries are installed (they should be from APT repo)
- Verify Python version matches: `python3 --version`
- If source distributions remain, they should have been built during bundle creation

### Rust Not Found After Installation

**Problem**: `rustc` or `cargo` not in PATH

**Solutions**:

```bash
# Add to ~/.bashrc or ~/.zshrc
source ~/.cargo/env

# Or manually add to PATH
export PATH="$HOME/.cargo/bin:$PATH"
```

### Ollama Not Using GPU

**Problem**: Ollama using CPU instead of GPU

**Solutions**:

1. Verify NVIDIA drivers: `nvidia-smi`
2. Verify CUDA: `nvcc --version`
3. Check Ollama logs: `tail -f ~/.ollama/logs/server.log`
4. Force GPU usage:

```bash
export OLLAMA_NUM_GPU=1
ollama serve
```

### APT Update Fails

**Problem**: `apt-get update` shows errors about other sources

**Solutions**:

- This is normal on airgapped systems - other sources will fail
- The local `file://` source will work regardless
- Errors can be ignored if local repo works

### Bundle Too Large

**Problem**: Bundle exceeds available space

**Solutions**:

- Bundle fewer models: `export OLLAMA_MODELS="mistral:7b-instruct"`
- Remove large models from bundle after creation
- Use external drive with more space
- For VM bundle: Reduce VM disk size with `export VM_DISK_SIZE="40G"`

### VM Won't Start

**Problem**: QEMU fails to start VM

**Solutions**:

- Check QEMU installation: `qemu-system-x86_64 --version` (must be x86_64 version)
- Check VM disk exists: `ls -lh ~/.local/share/vm/popos-airgap/popos-airgap.qcow2`
- On x86_64 Linux: Check KVM support: `ls -l /dev/kvm` and `grep -E '(vmx|svm)' /proc/cpuinfo`
- On x86_64 Linux: Ensure user is in `kvm` group: `sudo usermod -aG kvm $USER` (then log out/in)
- On x86_64 Linux: Load KVM modules: `sudo modprobe kvm` and `sudo modprobe kvm_intel` (or `kvm_amd`)
- On macOS: QEMU will use software emulation (no KVM needed, but slower)

### VM Runs Very Slowly on macOS

**Problem**: VM performance is poor on macOS

**Solutions**:

- **Apple Silicon Macs**: This is expected - uses x86_64 emulation for production testing
  - Performance is slower but ensures accurate testing of production scripts
  - Consider using `mac/setup_mac_vm.sh` which is optimized for macOS testing
- **Intel Macs**: Should run reasonably well with HVF acceleration
- Ensure Hypervisor.framework is available (macOS 10.10+)
- Reduce VM memory if needed: `VM_MEMORY=2G ./scripts/start_vm.sh`
- For faster bundle creation, consider using a Linux x86_64 machine
- Once created, the VM bundle can be used on any system

### Pop!_OS Installation in VM Requires Manual Steps

**Problem**: Pop!_OS installation in VM is not fully automated

**Solutions**:

- This is expected - Pop!_OS installer requires manual interaction
- Follow the on-screen instructions in the QEMU window
- The installation script will guide you through the process
- After installation, the VM will reboot into Pop!_OS

## 📊 Bundle Size Estimates

### Direct Installation Bundle

| Component | Size |
|-----------|------|
| Ollama binary | ~50MB |
| VSCodium | ~200MB |
| Extensions | ~100MB |
| APT repo | ~500MB-1GB |
| Python packages | ~500MB-2GB (depends on requirements.txt) |
| Rust toolchain | ~100MB |
| **Models** | **~32GB** (all 3 models) |
| **Total** | **~35GB+** |

To reduce size, bundle only needed models:

- Single model (mistral:7b-instruct): ~5GB total
- Two models (mistral variants): ~7GB total

## 🔒 Security & Privacy

- **No telemetry**: VSCodium has no Microsoft telemetry
- **Local AI**: All AI processing happens locally via Ollama
- **No network calls**: Install script has zero network dependencies
- **SHA256 verification**: All downloads are verified with checksums
- **Offline operation**: Complete airgap compliance
- **VM isolation**: VM bundle provides additional isolation layer

## 📚 Additional Documentation

- `airgap/docs/AIRGAP_REVIEW.md` - Comprehensive airgap review
- `airgap/docs/AIRGAP_PACKAGES.md` - Package installation details
- `airgap/docs/MODEL_RECOMMENDATIONS.md` - AI model selection guide
- `airgap/docs/SYSTEM_LIBRARIES.md` - System library explanations
- `airgap/README.md` - Airgap bundle scripts documentation
- `vm/README.md` - VM bundle scripts documentation
- `mac/README.md` - Mac testing scripts documentation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**MIT License** - A very permissive license that allows:
- ✅ Commercial use
- ✅ Modification
- ✅ Distribution
- ✅ Private use
- ✅ Patent use
- ✅ Sublicensing

The only requirement is to include the original copyright notice and license text.

## 🙏 Acknowledgments

- **Ollama** - Local LLM runtime
- **VSCodium** - Privacy-focused code editor
- **Continue** - AI coding assistant
- **Open VSX** - Open-source extension marketplace

## ⚠️ Important Notes

1. **Bundle Creation Requires Linux**: `get_bundle.sh` **must** be run on Pop!_OS/Ubuntu/Debian. It will exit with an error on macOS or other systems because it needs to build APT repos, compile Python packages, and vendor Rust crates.

2. **Bundle Size**: The full bundle with all models is ~35GB. VM bundle is ~55-60GB. Ensure sufficient storage.

3. **Pre-built Packages**: All Python packages are compiled into wheels during bundle creation. Installation on the airgapped system is fast and requires no compilation.

4. **Model Selection**: Choose models based on your GPU VRAM:
   - 16GB VRAM: Use `mistral:7b-instruct`
   - 24GB+ VRAM: Can use `mixtral:8x7b`

5. **First Run**: The first time you use Ollama, it may take a moment to load the model into GPU memory.

6. **Airgap Compliance**: This system is designed for true airgapped operation. All components are bundled, pre-built, and verified.

7. **VM Bundle**: The VM bundle includes Pop!_OS installation which requires manual interaction. Plan for ~30-60 minutes for Pop!_OS installation.

8. **KVM Acceleration**: For best VM performance on x86_64 Linux, ensure KVM is enabled (`/dev/kvm` exists and user is in `kvm` group). On macOS, software emulation is used (slower but functional).

9. **Architecture**: VM bundle always targets x86_64/amd64 architecture. On ARM64 Macs, QEMU will use x86_64 emulation (slower than native but works correctly).

---
