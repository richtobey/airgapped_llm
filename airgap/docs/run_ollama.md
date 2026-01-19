# Running Ollama and VSCodium

This guide explains how to run Ollama (a local LLM server) and VSCodium (code editor), and how to interact with Ollama to ask questions.

## Starting Ollama

### Start Ollama Service

Ollama runs as a background service. To start it:

```bash
# Start Ollama service
ollama serve
```

This will start the Ollama server on `http://localhost:11434` by default.

**Note**: If Ollama was installed via the airgap bundle, it should be available in your PATH. If not, you may need to use the full path: `/usr/local/bin/ollama serve`

### Running in Background

To run Ollama in the background and keep it running after closing the terminal:

```bash
# Run in background
nohup ollama serve > /tmp/ollama.log 2>&1 &

# Or use systemd (if configured)
sudo systemctl start ollama
sudo systemctl enable ollama  # Enable on boot
```

### Verify Ollama is Running

Check if Ollama is running:

```bash
# Check if the service is responding
curl http://localhost:11434/api/tags

# Or check the process
ps aux | grep ollama
```

## Running VSCodium

VSCodium is a free, open-source code editor based on VS Code. It's included in the airgap bundle and can be used with the Continue extension for AI-powered coding assistance.

### Starting VSCodium

#### From Command Line

```bash
# Launch VSCodium
codium

# Or open a specific directory
codium /path/to/your/project

# Open a specific file
codium /path/to/file.py
```

**Note**: If VSCodium was installed via the airgap bundle, it should be available in your PATH. If not, you may need to use the full path or create a desktop entry.

#### Check Installation

Verify VSCodium is installed:

```bash
# Check if VSCodium is available
which codium

# Check version
codium --version

# If not found, check common installation paths
ls -la /usr/bin/codium
ls -la /usr/local/bin/codium
```

### Launching from Desktop

If VSCodium was installed via the airgap bundle, it should appear in your application menu:

1. Open the application launcher (Super key or click Applications)
2. Search for "VSCodium" or "Codium"
3. Click to launch

### Opening Workspaces

VSCodium supports workspace files for managing multiple folders:

```bash
# Open a workspace file
codium /path/to/workspace.code-workspace

# The airgap bundle includes a workspace file
codium /path/to/airgap/airgap.code-workspace
```

### Command Line Options

Useful VSCodium command-line options:

```bash
# Open in new window
codium -n /path/to/project

# Open and wait (useful for scripts)
codium -w /path/to/file

# Open with specific line number
codium -g /path/to/file:42

# Open with specific line and column
codium -g /path/to/file:42:10

# Open in read-only mode
codium -r /path/to/file

# Get help
codium --help
```

### Configuring Continue Extension

The Continue extension (included in the airgap bundle) provides AI coding assistance using your local Ollama instance:

1. **Start Ollama** (if not already running):
   ```bash
   ollama serve
   ```

2. **Open VSCodium**:
   ```bash
   codium
   ```

3. **Configure Continue Extension**:
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac) to open the command palette
   - Type "Continue: Settings" and select it
   - Or go to: File → Preferences → Settings → Extensions → Continue

4. **Set up Ollama Provider**:
   - Add Ollama to your Continue configuration
   - Set the API endpoint: `http://localhost:11434`
   - Select your preferred model (e.g., `mistral:7b-instruct`)

5. **Example Continue Configuration** (in `~/.config/Continue/config.json` or VSCodium settings):
   ```json
   {
     "models": [
       {
         "title": "Ollama Mistral",
         "provider": "ollama",
         "model": "mistral:7b-instruct",
         "apiBase": "http://localhost:11434"
       }
     ]
   }
   ```

### Using Continue Extension

Once configured, you can use Continue for AI coding assistance:

- **Chat**: Open the Continue sidebar to chat with the AI about your code
- **Inline Edit**: Select code and ask Continue to modify it
- **Code Completion**: Get AI-powered code suggestions as you type
- **Explain Code**: Ask Continue to explain any part of your codebase

### Troubleshooting VSCodium

#### VSCodium Not Found

If `codium` command is not found:

```bash
# Check installation
dpkg -l | grep vscodium

# If installed but not in PATH, create a symlink
sudo ln -s /usr/share/codium/bin/codium /usr/local/bin/codium

# Or add to PATH in ~/.bashrc or ~/.zshrc
export PATH=$PATH:/usr/share/codium/bin
```

#### Extensions Not Loading

If extensions (like Continue) aren't loading:

```bash
# Check extension directory
ls -la ~/.vscode-oss/extensions/

# Restart VSCodium
# Close all windows and reopen

# Check extension logs
# Help → Toggle Developer Tools → Console tab
```

#### Continue Extension Not Connecting to Ollama

If Continue can't connect to Ollama:

1. **Verify Ollama is running**:
   ```bash
   curl http://localhost:11434/api/tags
   ```

2. **Check Continue settings**: Ensure the API endpoint is correct (`http://localhost:11434`)

3. **Check firewall**: Ensure localhost connections are allowed

4. **View Continue logs**: Open Developer Tools in VSCodium (Help → Toggle Developer Tools) and check the Console for errors

### VSCodium Settings

Customize VSCodium for your workflow:

```bash
# Open settings file
codium ~/.config/VSCodium/User/settings.json

# Or use the GUI: File → Preferences → Settings
```

### Keyboard Shortcuts

Common VSCodium shortcuts:

- `Ctrl+Shift+P` - Command Palette
- `Ctrl+P` - Quick Open (files)
- `Ctrl+B` - Toggle Sidebar
- `Ctrl+` ` - Toggle Terminal
- `Ctrl+Shift+E` - Explorer
- `F5` - Start Debugging
- `Ctrl+/` - Toggle Line Comment

## Available Models

After installation, check which models are available:

```bash
# List installed models
ollama list
```

Common models that may be included in the airgap bundle:
- `mistral:7b-instruct` - Mistral 7B Instruct model
- `mixtral:8x7b-instruct` - Mixtral 8x7B Instruct model

## Asking Questions

### Method 1: Using Ollama CLI (Command Line)

The simplest way to ask questions is using the `ollama run` command:

```bash
# Run a model interactively
ollama run mistral:7b-instruct

# This opens an interactive session where you can type questions
# Type your question and press Enter
# Type '/bye' or press Ctrl+D to exit
```

**Example Session:**

```bash
$ ollama run mistral:7b-instruct
>>> What is Python?
Python is a high-level, interpreted programming language...

>>> Explain how to use list comprehensions
List comprehensions in Python provide a concise way...

>>> /bye
```

### Method 2: One-Line Questions

Ask a single question without entering interactive mode:

```bash
# Ask a single question
ollama run mistral:7b-instruct "What is machine learning?"

# Or using the API directly
ollama run mistral:7b-instruct <<< "Explain quantum computing"
```

### Method 3: Using the REST API

Ollama provides a REST API that you can use from any HTTP client:

#### Using curl

```bash
# Ask a question via API
curl http://localhost:11434/api/generate -d '{
  "model": "mistral:7b-instruct",
  "prompt": "What is the difference between Python and JavaScript?",
  "stream": false
}'
```

#### Using Python

```python
import requests
import json

# Ask a question
response = requests.post(
    'http://localhost:11434/api/generate',
    json={
        'model': 'mistral:7b-instruct',
        'prompt': 'What is the capital of France?',
        'stream': False
    }
)

result = response.json()
print(result['response'])
```

#### Streaming Responses

For longer responses, you can stream the output:

```bash
# Stream response
curl http://localhost:11434/api/generate -d '{
  "model": "mistral:7b-instruct",
  "prompt": "Write a short story about a robot",
  "stream": true
}'
```

### Method 4: Using Python ollama Library

If you have the `ollama` Python package installed:

```python
import ollama

# Ask a question
response = ollama.generate(
    model='mistral:7b-instruct',
    prompt='Explain how neural networks work'
)

print(response['response'])

# Chat interface
stream = ollama.chat(
    model='mistral:7b-instruct',
    messages=[
        {
            'role': 'user',
            'content': 'What is the difference between supervised and unsupervised learning?'
        }
    ],
    stream=True
)

for chunk in stream:
    print(chunk['message']['content'], end='', flush=True)
```

## Example Questions

Here are some example questions you can try:

```bash
# Technical questions
ollama run mistral:7b-instruct "How do I implement a binary search tree in Python?"

# General knowledge
ollama run mistral:7b-instruct "What are the main causes of climate change?"

# Code explanation
ollama run mistral:7b-instruct "Explain this code: def fibonacci(n): return n if n < 2 else fibonacci(n-1) + fibonacci(n-2)"

# Creative writing
ollama run mistral:7b-instruct "Write a haiku about programming"
```

## Troubleshooting

### Ollama Not Found

If you get `command not found`:

```bash
# Check if Ollama is installed
which ollama

# If not found, check the installation path
ls -la /usr/local/bin/ollama

# Add to PATH if needed
export PATH=$PATH:/usr/local/bin
```

### Port Already in Use

If port 11434 is already in use:

```bash
# Check what's using the port
sudo lsof -i :11434

# Kill the process if needed
kill <PID>

# Or specify a different port
OLLAMA_HOST=0.0.0.0:11435 ollama serve
```

### Model Not Found

If you get a "model not found" error:

```bash
# List available models
ollama list

# Pull a model (requires internet - not available in airgap)
# ollama pull mistral:7b-instruct

# In airgap environment, models should be pre-installed
# Check ~/.ollama/models/ directory
ls -lh ~/.ollama/models/
```

### Performance Issues

For better performance:

```bash
# Check system resources
free -h
nproc

# Ollama uses available CPU/GPU automatically
# For GPU acceleration, ensure proper drivers are installed
```

## Advanced Usage

### Chat with Context

```bash
# Start a chat session with context
ollama run mistral:7b-instruct

# In the session, you can have a conversation:
>>> My name is Alice and I'm learning Python
>>> What should I learn first?
>>> Can you give me a simple example?
```

### Using Different Models

```bash
# Switch between models
ollama run mistral:7b-instruct "Question about coding"
ollama run mixtral:8x7b-instruct "Complex reasoning question"
```

### Custom System Prompts

```bash
# Use a system prompt to set behavior
curl http://localhost:11434/api/generate -d '{
  "model": "mistral:7b-instruct",
  "system": "You are a helpful Python programming assistant.",
  "prompt": "How do I use decorators?",
  "stream": false
}'
```

## Integration with Continue Extension

If you're using VSCodium with the Continue extension (included in the airgap bundle), Ollama can be configured as the AI provider:

1. Open VSCodium
2. Open Continue extension settings
3. Configure Ollama endpoint: `http://localhost:11434`
4. Select your preferred model (e.g., `mistral:7b-instruct`)

The Continue extension will then use your local Ollama instance for AI coding assistance.

## Stopping Ollama

To stop the Ollama service:

```bash
# If running in foreground, press Ctrl+C

# If running in background, find and kill the process
pkill ollama

# Or if using systemd
sudo systemctl stop ollama
```

## Additional Resources

- Ollama documentation: https://ollama.ai/docs
- API reference: https://github.com/ollama/ollama/blob/main/docs/api.md
- Model library: https://ollama.ai/library
