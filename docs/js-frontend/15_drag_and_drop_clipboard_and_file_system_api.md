# Module 15: Native Web APIs — Drag & Drop, Clipboard & File System Access

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Native Desktop Web APIs, File System Access & Clipboard

---

## 1. Native HTML5 Drag and Drop Architecture

The HTML5 Drag and Drop API allows elements to be dragged across the screen, between browser tabs, and allows desktop OS files to be dropped directly into the browser:

```
┌─────────────────────────────────────────────────────────────┐
│                 HTML5 Drag & Drop Event Pipeline            │
├────────────────────┬────────────────────────────────────────┤
│ **1. Dragged Item**│ `dragstart` ──► `drag` ──► `dragend`   │
├────────────────────┼────────────────────────────────────────┤
│ **2. Drop Target** │ `dragenter` ──► `dragover` ──► `drop`  │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Interactive Kanban Drag-and-Drop Implementation

```html
<div class="kanban-column" id="col-todo">
  <h3>To Do</h3>
  <div class="kanban-card" draggable="true" data-id="task-1">Design UI Tokens</div>
  <div class="kanban-card" draggable="true" data-id="task-2">Setup Web Workers</div>
</div>

<div class="kanban-column" id="col-done">
  <h3>Done</h3>
</div>
```

```javascript
// src/components/kanban.js
export function initKanbanBoard() {
  let draggedCard = null;

  // 1. Configure Draggable Cards:
  document.querySelectorAll('.kanban-card').forEach((card) => {
    card.addEventListener('dragstart', (e) => {
      draggedCard = card;
      card.classList.add('is-dragging');
      // Store payload in dataTransfer:
      e.dataTransfer.setData('text/plain', card.dataset.id);
      e.dataTransfer.effectAllowed = 'move';
    });

    card.addEventListener('dragend', () => {
      draggedCard?.classList.remove('is-dragging');
      draggedCard = null;
    });
  });

  // 2. Configure Drop Target Columns:
  document.querySelectorAll('.kanban-column').forEach((column) => {
    // CRITICAL: Must call preventDefault() on 'dragover' to allow dropping!
    column.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      column.classList.add('drag-over');
    });

    column.addEventListener('dragleave', () => {
      column.classList.remove('drag-over');
    });

    column.addEventListener('drop', (e) => {
      e.preventDefault();
      column.classList.remove('drag-over');

      if (draggedCard) {
        column.appendChild(draggedCard);
        const taskId = e.dataTransfer.getData('text/plain');
        console.log(`Task ${taskId} moved to ${column.id}!`);
      }
    });
  });
}
```

---

## 3. The Asynchronous Clipboard API (`navigator.clipboard`)

Modern browsers replace deprecated `document.execCommand('copy')` with the Promise-based **Async Clipboard API**:

### 1. Copying Plain Text:

```javascript
export async function copyTextToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    console.log('Text copied to system clipboard successfully!');
  } catch (err) {
    console.error('Failed to copy to clipboard:', err);
  }
}
```

### 2. Copying Rich PNG Images & Blobs to Clipboard:

```javascript
export async function copyCanvasImageToClipboard(canvas) {
  canvas.toBlob(async (blob) => {
    try {
      const clipboardItem = new ClipboardItem({ 'image/png': blob });
      await navigator.clipboard.write([clipboardItem]);
      console.log('Image copied to clipboard! Paste directly into Slack/Figma.');
    } catch (err) {
      console.error('Image clipboard copy failed:', err);
    }
  });
}
```

---

## 4. Native File System Access API (`showOpenFilePicker`)

The **File System Access API** allows web applications to open, read, edit, and save files directly on the user's native computer hard drive (used by VS Code Web):

### 1. Open Local File:

```javascript
export async function openLocalTextFile() {
  // 1. Open Native OS File Picker Dialog:
  const [fileHandle] = await window.showOpenFilePicker({
    types: [
      {
        description: 'JSON & Text Files',
        accept: { 'text/plain': ['.txt', '.json', '.md'] },
      },
    ],
    multiple: false,
  });

  // 2. Read file contents:
  const file = await fileHandle.getFile();
  const text = await file.text();

  return { fileHandle, fileName: file.name, text };
}
```

### 2. Save / Overwrite Local File Directly on Disk:

```javascript
export async function saveLocalFile(fileHandle, updatedContent) {
  // 1. Request write stream access:
  const writable = await fileHandle.createWritable();

  // 2. Write updated text directly to disk:
  await writable.write(updatedContent);

  // 3. Close stream to finalize write:
  await writable.close();
  console.log('File saved directly to disk hardware!');
}
```

---

## Troubleshooting & Best Practices

1. **`dragover` MUST Call `event.preventDefault()`**
   By default, web browsers disable dropping elements. Failing to call `e.preventDefault()` inside the `dragover` event listener will prevent the `drop` event from ever firing.

2. **Clipboard and File Picker APIs Require User Gestures**
   Calling `window.showOpenFilePicker()` or `navigator.clipboard.writeText()` without a direct user interaction (e.g. inside a `click` or `keydown` event callback) will throw a `SecurityError: Must be handling a user gesture`.
