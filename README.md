# See

A macOS image viewer with AI-powered image descriptions.

## Features

- **Image Library**: Browse images from one or more local folders with sidebar navigation and search
- **AI Descriptions**: Generate detailed descriptions of images using LLMs (Ollama / OpenAI)
- **AI Explanations**: Get deeper contextual explanations about images
- **Markdown Rendering**: Full CommonMark/GFM support with text selection and copy
- **Zoom & Pan**: Zoom into images and pan around at high zoom levels
- **Crop**: Crop regions of interest with drag selection
- **Export**: Export cropped or full images as PNG or JPEG
- **Caching**: Local SQLite cache for descriptions and explanations

## Screenshots

![See Screenshot](docs/screenshot.png)

## Requirements

- macOS 14.0+
- Xcode 15+ (for building from source)
- Homebrew (for dependencies)

## Installation

### From DMG

Download the latest `.dmg` from the [releases page](https://github.com/pengxiaotao/see/releases) and drag `See.app` to your Applications folder.

### Build from Source

1. Install the cmark-gfm library:

   ```bash
   brew install cmark-gfm
   ```

2. Open the project in Xcode and build:

   ```bash
   open See.xcodeproj
   ```

3. Or build from the command line:

   ```bash
   xcodebuild -project See.xcodeproj -scheme See -configuration Debug build
   ```

### Create DMG

```bash
bash scripts/create-dmg.sh
```

The DMG will be created in `dist/See.dmg` with all dependencies bundled.

## Configuration

Open **Settings** from the menu bar to configure:

- **Provider**: Choose between Ollama (local) or OpenAI (compatible APIs)
- **Ollama**: Base URL (default `http://localhost:11434`) and model name (default `llava`)
- **OpenAI**: Base URL, API key, and model name
- **Prompt**: Customize the default description prompt

## Usage

1. Click **Add Folder** in the sidebar to add image directories
2. Select an image from the sidebar or navigation
3. Click **Describe** to generate an AI description
4. Click **Explain** to get a deeper explanation (requires a description first)
5. Use the description controls to:
   - Regenerate the description
   - Adjust font size
   - Show/hide the description panel

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Left/Right Arrow` (numeric pad) | Navigate previous/next image |
| `+` / `-` | Zoom in / out |
| `Cmd+0` | Reset zoom |

## Architecture

```
Sources/See/
  ContentView.swift        - Main UI, image viewer, description overlay
  ImageLibraryStore.swift  - Image library state management
  ImageCache.swift         - SQLite cache for descriptions/explanations
  ImageDescriber.swift     - LLM API integration (Ollama/OpenAI)
  LLMSettings.swift        - Settings model and API client
  ImageItem.swift          - Image metadata (URL, size, pixel dimensions)
  ImageViewApp.swift       - App entry point
  SettingsView.swift       - Settings UI
  CMarkWrapper.swift       - cmark-gfm bindings for markdown rendering
  ImageCache.swift         - NSCache for image pixel sizes
```

## Dependencies

- [cmark-gfm](https://github.com/commonmark/cmark-gfm) — CommonMark/GFM markdown library
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) — SQLite database for caching

## License

MIT.
