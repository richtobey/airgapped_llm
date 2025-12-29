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

- **macOS or Linux** (macOS can create bundle, but APT repo needs Linux)
- **Python 3** (for downloading packages)
- **Internet connection** (for downloading components)
- **Disk space**: ~35GB+ (for all models and components)
- **Optional**: Rust/Cargo (if bundling Rust crates)

### For Installation (Airgapped System)

**Direct Installation:**

- **Pop!_OS or Ubuntu/Debian-based Linux** (amd64)
- **sudo access** (for installing packages)
- **Disk space**: ~35GB+ for bundle + installation space
- **Optional**: NVIDIA GPU with 16GB+ VRAM (for GPU acceleration)

## 🚀 Quick Start

### Method 1: Direct Installation (Traditional)

#### Step 1: Create the Bundle (On Online Machine)

```bash
# Clone or download this repository
cd airgap

# Navigate to airgap bundle scripts
cd airgap

# Option 1: Use default models (all 3 recommended models)
./get_bundle.sh

# Option 2: Bundle only specific models
export OLLAMA_MODELS="mistral:7b-instruct"
./get_bundle.sh

# Option 3: Bundle custom Python packages
# Edit airgap/requirements.txt or create your own
./get_bundle.sh
```

The bundle will be created in `./airgap_bundle/` (or `$BUNDLE_DIR` if set).

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

# Run the installation script
./install_offline.sh

# Or specify custom bundle location
BUNDLE_DIR=/path/to/airgap_bundle ./install_offline.sh
```

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

All packages from `requirements.txt` plus all transitive dependencies:

- Code quality: black, ruff, mypy, pylint
- Testing: pytest, pytest-cov, pytest-mock
- Data science: numpy, pandas
- Web: requests, httpx
- Utilities: pydantic, click, rich, sphinx
- And more (customize `requirements.txt`)

### Rust Crates

If `Cargo.toml` is provided, all Rust dependencies are vendored for offline use.

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

1. Edit `airgap/get_bundle.sh`, find `APT_PACKAGES` array (around line 410)
2. Add your packages:

```bash
APT_PACKAGES=(
  # ... existing packages ...
  your-package
  another-package
)
```

1. Re-run on Linux machine to rebuild APT repo

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

## 🔧 APT Repository on macOS

If building the bundle on macOS, the APT repository won't be created automatically. You have two options:

### Option 1: Build APT Repo on Linux

1. Copy `airgap_bundle/aptrepo/` to a Linux machine
2. Build the repo:

```bash
cd airgap_bundle/aptrepo
sudo apt-get update
sudo apt-get -y --download-only install git build-essential python3-dev ...
# Copy .deb files from /var/cache/apt/archives/ to pool/
apt-ftparchive packages pool > Packages
gzip -kf Packages
```

### Option 2: Build on Target System

If the target system has temporary internet access:

1. Run `install_offline.sh`
2. When prompted about missing APT repo, choose to build it
3. Follow the instructions

## 🐛 Troubleshooting

### Python Packages Won't Install

**Problem**: Some packages fail to install

**Solutions**:

- Check that system libraries are installed (they should be from APT repo)
- Verify build tools are installed: `gcc --version`
- Check Python version: `python3 --version`
- Some packages may need compilation - this is normal and may take time

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

### VM Bundle

| Component | Size |
|-----------|------|
| QEMU binaries/info | ~50MB |
| Pop!_OS ISO | ~3GB |
| VM disk image (empty, sparse) | ~50GB (allocated) |
| VM disk image (with Pop!_OS) | ~20GB (actual) |
| Airgap bundle (nested) | ~35GB |
| **Total VM Bundle** | **~55-60GB** |

Note: VM disk images use sparse files, so actual disk usage is less than allocated size.

## 🖥️ VM Bundle Workflow

The VM bundle provides a complete virtualized environment with Pop!_OS pre-installed. This is useful when:

- You don't have Pop!_OS installed on the airgapped host
- You want isolation between the development environment and host system
- You need to run on a different Linux distribution
- You want easy snapshot/backup capabilities

### VM Bundle Architecture

The VM bundle uses a **nested approach**:

1. `vm/get_vm_bundle.sh` creates the VM bundle
2. Inside the VM bundle, it calls `airgap/get_bundle.sh` to create the airgap bundle
3. The airgap bundle is nested inside `vm_bundle/airgap_bundle/`
4. Pop!_OS is installed in the VM disk image
5. The airgap bundle can be installed inside the VM

### QEMU/KVM Requirements

**Target Architecture:**

- **Always x86_64/amd64** - The VM bundle always creates x86_64 VMs regardless of host architecture

**Hardware Requirements:**

- **x86_64 Linux hosts**: CPU with virtualization support (Intel VT-x or AMD-V) for KVM acceleration
- **ARM64 Macs**: No special hardware needed (uses software emulation)
- `/dev/kvm` device available on x86_64 Linux (requires kernel module)
- Sufficient RAM: Host needs VM memory (4GB default) + overhead

**Software Requirements:**

- QEMU installed on host system (`qemu-system-x86_64` and `qemu-img`)
  - Linux: `sudo apt-get install qemu-system-x86 qemu-utils qemu-kvm`
  - macOS: `brew install qemu`
- User in `kvm` group (for KVM acceleration on x86_64 Linux hosts)

**Architecture-Specific Notes:**

- **x86_64 Linux**: Uses KVM acceleration (fast, near-native performance)
- **x86_64 Mac**: Uses TCG emulation (slower, but works)
- **ARM64 Mac**: Uses x86_64 emulation via QEMU TCG (slowest, but functional)
  - Consider using a Linux x86_64 machine for faster bundle creation
  - VM will work but installation and operation will be slower

**Checking KVM Support (x86_64 Linux only):**

```bash
# Check CPU virtualization flags
grep -E '(vmx|svm)' /proc/cpuinfo

# Check for /dev/kvm
ls -l /dev/kvm

# Check if user is in kvm group
groups | grep kvm
```

### VM Management

**Starting the VM:**

```bash
cd /path/to/vm_bundle
./scripts/start_vm.sh
```

**Stopping the VM:**

- Shut down Pop!_OS from within the VM (normal shutdown)
- Or use QEMU monitor: `Ctrl+Alt+2` then `quit`

**Accessing VM Files:**

- VM disk is at: `~/.local/share/vm/popos-airgap/popos-airgap.qcow2`
- You can mount the qcow2 image using `qemu-nbd` or `guestmount` (libguestfs)

**VM Configuration:**

- Default memory: 4GB (set via `VM_MEMORY` env var)
- Default CPUs: 2 (set via `VM_CPUS` env var)
- Default disk: 50GB (set via `VM_DISK_SIZE` env var)
- Network: User-mode networking (NAT, no external access)

### GPU Passthrough (Advanced)

For GPU acceleration inside the VM, you can configure GPU passthrough:

1. **Requirements:**
   - IOMMU enabled in BIOS/UEFI
   - IOMMU groups configured
   - VFIO kernel modules

2. **QEMU Arguments:**

   ```bash
   -device vfio-pci,host=XX:XX.X  # Replace with GPU PCI address
   ```

3. **Note:** GPU passthrough is complex and requires careful configuration. See QEMU/VFIO documentation for details.

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

1. **Bundle Size**: The full bundle with all models is ~35GB. VM bundle is ~55-60GB. Ensure sufficient storage.

2. **APT Repo on macOS**: If building on macOS, you'll need to build the APT repo separately on Linux or on the target system.

3. **Model Selection**: Choose models based on your GPU VRAM:
   - 16GB VRAM: Use `mistral:7b-instruct`
   - 24GB+ VRAM: Can use `mixtral:8x7b`

4. **First Run**: The first time you use Ollama, it may take a moment to load the model into GPU memory.

5. **Airgap Compliance**: This system is designed for true airgapped operation. All components are bundled and verified.

6. **VM Bundle**: The VM bundle includes Pop!_OS installation which requires manual interaction. Plan for ~30-60 minutes for Pop!_OS installation.

7. **KVM Acceleration**: For best VM performance on x86_64 Linux, ensure KVM is enabled (`/dev/kvm` exists and user is in `kvm` group). On macOS, software emulation is used (slower but functional).

8. **Architecture**: VM bundle always targets x86_64/amd64 architecture. On ARM64 Macs, QEMU will use x86_64 emulation (slower than native but works correctly).

---
