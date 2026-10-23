# Third-Party Notices

## Universal desktop client

The cross-platform client under `Desktop/` includes Electron (MIT), Electron Forge (MIT), PDF.js / `pdfjs-dist` (Apache-2.0), and their transitive packages. Binary distributions must include the complete machine-generated licence inventory from the locked dependency tree; this summary does not replace those licence texts. The macOS DMG is created with Apple's `hdiutil`; the vulnerable `appdmg`/`image-size` packaging chain is intentionally not used.

- Electron: <https://github.com/electron/electron>
- Electron Forge: <https://github.com/electron/forge>
- PDF.js: <https://github.com/mozilla/pdf.js>

The universal client uses the SQLite library embedded in Electron's Node.js runtime. Provider names and model names belong to their respective owners. No model weights are redistributed.

## Native macOS client

The standalone Research Atlas packaging script can copy an already installed Ollama runtime (`ollama` and `llama-server`) into the application bundle. Research Atlas does not redistribute model weights. Model authors may apply separate licences to weights stored in the user's local Ollama model store.

## Ollama

Source: <https://github.com/ollama/ollama>

MIT License

Copyright (c) Ollama

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## llama.cpp / ggml

The `llama-server` runtime used by Ollama incorporates the llama.cpp/ggml project.

Source: <https://github.com/ggml-org/llama.cpp>

MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The exact Ollama build may contain additional vendored components. Before distributing a binary release, archive and ship the complete version-specific vendor notices produced by that Ollama build in addition to this summary.
