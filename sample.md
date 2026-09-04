# Sample Markdown

This is a **simple** Markdown viewer with *edit* and *preview* modes.

Setext Header 1
===============

Setext Header 2
---------------

## Features

- Open existing `.md` files
- Edit with a monospace source editor
- Preview with a WebKit renderer
- Render Mermaid diagrams
- Autosave after 1 second of inactivity
- Export the rendered preview to PDF
- ~~Scratch that~~

## Tasks

- [x] Build basic editor
- [ ] Add preview mode
- [ ] Add syntax highlighting

## Code Example

Inline code looks like `print("hello")`.

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, Markdown!")
    }
}
```

## Mermaid Diagrams

Fenced code blocks tagged `mermaid` are rendered as diagrams.

```mermaid
flowchart TD
    A[Open .md file] --> B{Mode?}
    B -->|Edit| C[Monospace editor]
    B -->|Preview| D[WebKit renderer]
    C --> D
    D --> E[Export PDF]
```

```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant W as WebKit
    U->>A: Open markdown file
    A->>W: Render HTML
    W-->>U: Show preview
```

> This is a blockquote with a **bold** statement.

---

Line break test  
This should be on a new line.

[OpenAI](https://openai.com)

## Table Example

| Feature | Status | Priority |
|:--------|:------:|---------:|
| Edit    | Done   | High     |
| Preview | Done   | High     |
| Tables  | Done   | Medium   |
