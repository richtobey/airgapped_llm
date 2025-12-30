# Mistral/Mixtral Model Recommendations for 16GB VRAM

## Your System Specifications
- **GPU VRAM:** 16GB NVIDIA
- **System RAM:** 64GB
- **Platform:** System76 (Pop!_OS)

## ✅ Recommended Models

### 1. **Mistral 7B** (BEST CHOICE)
**Ollama Model Name:** `mistral:7b` or `mistral:7b-instruct`

**VRAM Requirements:**
- Full precision (FP16): ~13.7GB VRAM ✅ **Fits perfectly in 16GB**
- 4-bit quantized (Q4): ~3.4GB VRAM (leaves plenty of headroom)
- 5-bit quantized (Q5): ~4.3GB VRAM (good balance)
- 8-bit quantized (Q8): ~6.9GB VRAM (better quality, still fits)

**Performance:**
- Excellent for coding tasks
- Fast inference on 16GB GPU
- Good quality responses
- 32k context window

**Recommended Variants:**
- `mistral:7b` - Base model
- `mistral:7b-instruct` - Fine-tuned for instructions (better for coding)
- `mistral:7b-instruct-q4_K_M` - 4-bit quantized (if you want to save VRAM)

### 2. **Mistral Small 3.1** (POSSIBLE WITH QUANTIZATION)
**Ollama Model Name:** `mistral-small:3.1` or `mistral-small:3.1-instruct`

**VRAM Requirements:**
- Full precision: ~24GB VRAM ❌ **Too large for 16GB**
- 4-bit quantized: ~12GB VRAM ✅ **Might fit with quantization**
- 5-bit quantized: ~15GB VRAM ⚠️ **Tight fit**

**Performance:**
- 24B parameters (more capable than 7B)
- 128k context window
- Better quality but slower

**Note:** Requires quantization to fit in 16GB VRAM

### 3. **Mixtral 8x7B** (NOT RECOMMENDED)
**Ollama Model Name:** `mixtral:8x7b` (current default)

**VRAM Requirements:**
- Minimum: 24GB VRAM ❌ **Won't fit in 16GB**
- Even with quantization: ~18-20GB VRAM ❌ **Still too large**

**Recommendation:** ❌ **Do not use** - Your current script defaults to this, but it won't work on 16GB VRAM.

## 🎯 Best Choice for Your System

**Use `mistral:7b-instruct`** - This is the optimal model for your hardware:

1. ✅ Fits comfortably in 16GB VRAM
2. ✅ Excellent for coding tasks
3. ✅ Fast inference
4. ✅ Good quality responses
5. ✅ Works well with Continue extension

## 📝 How to Change the Model

### Option 1: Set Environment Variable
```bash
export OLLAMA_MODEL="mistral:7b-instruct"
./get_bundle.sh
```

### Option 2: Edit get_bundle.sh
Change line 9 from:
```bash
OLLAMA_MODEL="${OLLAMA_MODEL:-mixtral:8x7b}"
```
to:
```bash
OLLAMA_MODEL="${OLLAMA_MODEL:-mistral:7b-instruct}"
```

## 🔧 GPU Setup for Ollama

### 1. Install NVIDIA Drivers (if not already)
```bash
# On Pop!_OS, NVIDIA drivers are usually pre-installed
# Verify with:
nvidia-smi
```

### 2. Install CUDA (if needed)
```bash
# Pop!_OS usually includes CUDA
# Verify with:
nvcc --version
```

### 3. Configure Ollama to Use GPU

Ollama should automatically detect and use your NVIDIA GPU if:
- NVIDIA drivers are installed
- CUDA is available
- GPU is detected

**Verify GPU usage:**
```bash
# After starting Ollama
ollama serve

# In another terminal, check GPU usage:
nvidia-smi

# You should see Ollama process using GPU memory
```

### 4. Force GPU Usage (if needed)

If Ollama doesn't use GPU automatically, you can:
```bash
# Set environment variable
export OLLAMA_NUM_GPU=1

# Or in ~/.bashrc or ~/.zshrc
echo 'export OLLAMA_NUM_GPU=1' >> ~/.bashrc
```

## 📊 Model Comparison

| Model | Parameters | VRAM (FP16) | VRAM (Q4) | Quality | Speed | Your System |
|-------|-----------|-------------|-----------|---------|-------|-------------|
| **Mistral 7B** | 7B | 13.7GB | 3.4GB | ⭐⭐⭐⭐ | ⚡⚡⚡ | ✅ Perfect |
| Mistral Small 3.1 | 24B | 24GB | 12GB | ⭐⭐⭐⭐⭐ | ⚡⚡ | ⚠️ Possible (Q4) |
| Mixtral 8x7B | 46.7B | 48GB | 24GB | ⭐⭐⭐⭐⭐ | ⚡ | ❌ Too Large |

## 🚀 Recommended Configuration

For your System76 machine with 16GB VRAM:

```bash
# Best overall choice
OLLAMA_MODEL="mistral:7b-instruct"

# If you want to save VRAM for other tasks
OLLAMA_MODEL="mistral:7b-instruct-q4_K_M"

# If you want maximum quality (still fits)
OLLAMA_MODEL="mistral:7b-instruct-q8_0"
```

## 💡 Tips

1. **Start with `mistral:7b-instruct`** - Best balance of quality and performance
2. **Monitor GPU usage** with `nvidia-smi` to see actual VRAM consumption
3. **Use quantization** (Q4/Q5) if you need to run other GPU tasks simultaneously
4. **64GB system RAM** gives you plenty of headroom for system operations

## ⚠️ Current Script Issue

Your current `get_bundle.sh` defaults to `mixtral:8x7b`, which **will not work** on 16GB VRAM. 

**Action Required:** Change the default model to `mistral:7b-instruct` before running the bundle script.

