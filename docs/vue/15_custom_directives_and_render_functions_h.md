# Module 15: Custom Directives & Render Functions (`h()`)

**Track:** Vue — Progressive Web Framework  
**Category:** Low-Level DOM Manipulation & Virtual DOM

---

## When to Use Custom Directives vs Composables

In Vue 3, the Composition API is the preferred choice for 95% of stateful logic and browser integrations. However, **Custom Directives** remain essential when you need **direct, reusable, low-level DOM access and element lifecycle control** that cannot be cleanly modeled with templates or props alone.

Common use cases for custom directives:
- **`v-click-outside`**: Detecting clicks outside a dropdown, dialog, or popover menu.
- **`v-tooltip`**: Attaching dynamic floating tooltips without extra wrapper elements.
- **`v-focus`**: Auto-focusing inputs upon mounting or state transition.
- **`v-intersection`**: Triggering lazy loading or animations when elements enter the viewport.
- **`v-permission`**: Stripping DOM nodes dynamically based on user security roles.

---

## Anatomy of a Custom Directive & Hook Lifecycle

A directive is defined as an object containing lifecycle hooks that mirror component lifecycles:

```
Directive Hook Lifecycle:
1. `created(el, binding, vnode, prevVnode)` ── Called before element attributes or event listeners are applied.
2. `beforeMount(el, binding, vnode, prevVnode)` ── Called when element is inserted into DOM, before parent is mounted.
3. `mounted(el, binding, vnode, prevVnode)` ── Element is mounted and accessible in real DOM.
4. `beforeUpdate(el, binding, vnode, prevVnode)` ── Called before the containing component updates.
5. `updated(el, binding, vnode, prevVnode)` ── Called after the containing component and all its children have updated.
6. `beforeUnmount(el, binding, vnode, prevVnode)` ── Called before parent component is unmounted.
7. `unmounted(el, binding, vnode, prevVnode)` ── Element is removed from DOM.
```

### Directive Arguments & Modifiers Anatomy

When you write `<div v-example:arg.mod1.mod2="value">`:
- `binding.value`: The evaluated JavaScript expression (`value`).
- `binding.oldValue`: Previous value (only available in `beforeUpdate` and `updated`).
- `binding.arg`: The argument passed to the directive (e.g. `'arg'`).
- `binding.modifiers`: An object of boolean flags (e.g. `{ mod1: true, mod2: true }`).
- `binding.instance`: The component instance using the directive.

---

## Production Directives

### 1. `v-click-outside` Directive

```typescript
// src/directives/vClickOutside.ts
import type { Directive, DirectiveBinding } from "vue";

interface ClickOutsideElement extends HTMLElement {
  __clickOutsideHandler__?: (event: MouseEvent) => void;
}

export const vClickOutside: Directive<ClickOutsideElement, (event: MouseEvent) => void> = {
  mounted(el: ClickOutsideElement, binding: DirectiveBinding) {
    if (typeof binding.value !== "function") {
      console.warn("[v-click-outside] Provided value must be a callback function");
      return;
    }

    const handler = (event: MouseEvent) => {
      const target = event.target as Node;
      // Check if click occurred outside the bound element and its children
      if (!el.contains(target) && el !== target) {
        binding.value(event);
      }
    };

    el.__clickOutsideHandler__ = handler;
    // Capture phase ensures we intercept clicks before stopPropagation from children
    document.addEventListener("click", handler, true);
  },

  unmounted(el: ClickOutsideElement) {
    if (el.__clickOutsideHandler__) {
      document.removeEventListener("click", el.__clickOutsideHandler__, true);
      delete el.__clickOutsideHandler__;
    }
  },
};
```

### 2. `v-focus` Directive (with Argument and Modifier)

```typescript
// src/directives/vFocus.ts
import type { Directive } from "vue";

export const vFocus: Directive<HTMLInputElement, boolean | undefined> = {
  mounted(el, binding) {
    // If a boolean value was passed (v-focus="shouldFocus"), only focus if true
    if (binding.value === undefined || binding.value === true) {
      if (binding.modifiers.select) {
        el.select(); // v-focus.select selects text in addition to focusing
      }
      el.focus();
    }
  },
  updated(el, binding) {
    if (binding.value !== binding.oldValue && binding.value === true) {
      el.focus();
    }
  },
};
```

### Registering Directives Globally or Locally

```typescript
// Globally in main.ts
import { createApp } from "vue";
import App from "./App.vue";
import { vClickOutside } from "./directives/vClickOutside";
import { vFocus } from "./directives/vFocus";

const app = createApp(App);
app.directive("click-outside", vClickOutside);
app.directive("focus", vFocus);
app.mount("#app");
```

```vue
<!-- Locally in a Component (<script setup>) -->
<script setup lang="ts">
import { ref } from "vue";
import { vClickOutside } from "@/directives/vClickOutside";

const isDropdownOpen = ref(false);

function closeDropdown() {
  isDropdownOpen.value = false;
}
</script>

<template>
  <div class="dropdown-container">
    <button @click="isDropdownOpen = !isDropdownOpen">Toggle Menu</button>
    <div
      v-if="isDropdownOpen"
      v-click-outside="closeDropdown"
      class="dropdown-menu"
    >
      <ul>
        <li>Profile</li>
        <li>Settings</li>
        <li>Log Out</li>
      </ul>
    </div>
  </div>
</template>
```

---

## Render Functions & Virtual DOM (`h()`)

Templates are compiled into **render functions** that return Virtual DOM nodes (VNodes). While templates are declarative and readable, writing render functions directly using `h()` gives you 100% programmatic control over rendering.

Use `h()` when:
1. Creating dynamic wrappers or higher-order components.
2. Rendering recursive tree structures (like nested file trees or JSON explorers).
3. Writing headless UI libraries or polymorphic design system components.

### Syntax of `h()`

```typescript
h(type, propsOrAttributes, children)
```

- `type`: String (HTML tag like `'div'`, `'button'`) or a Vue component object.
- `propsOrAttributes` (optional): Object of attributes, props, event listeners (`onClick`), classes, and styles.
- `children` (optional): String, array of VNodes, or an object of slot functions.

---

## Building Dynamic Components with `h()`

### 1. Dynamic Heading Component (`<AppHeading level="1-6">`)

Instead of writing 6 `v-if` branches in a template (`<h1 v-if="level === 1">...`), a render function generates the exact tag dynamically:

```typescript
// src/components/AppHeading.ts
import { defineComponent, h } from "vue";

export const AppHeading = defineComponent({
  name: "AppHeading",
  props: {
    level: {
      type: Number,
      default: 1,
      validator: (val: number) => val >= 1 && val <= 6,
    },
    id: {
      type: String,
      default: undefined,
    },
  },
  setup(props, { slots }) {
    return () => {
      const tag = `h${props.level}`;
      return h(
        tag,
        {
          id: props.id,
          class: `app-heading app-heading--level-${props.level}`,
        },
        slots.default ? slots.default() : []
      );
    };
  },
});
```

### 2. Recursive Tree Renderer with `h()`

```typescript
// src/components/JsonTreeViewer.ts
import { defineComponent, h, ref } from "vue";

export interface TreeNode {
  key: string;
  value: any;
  children?: TreeNode[];
}

export const JsonTreeViewer = defineComponent({
  name: "JsonTreeViewer",
  props: {
    node: {
      type: Object as () => TreeNode,
      required: true,
    },
  },
  setup(props) {
    const isExpanded = ref(true);

    const toggle = () => {
      isExpanded.value = !isExpanded.value;
    };

    return () => {
      const hasChildren = props.node.children && props.node.children.length > 0;

      const headerVNode = h(
        "div",
        {
          class: "tree-node__header",
          onClick: hasChildren ? toggle : undefined,
          style: { cursor: hasChildren ? "pointer" : "default", fontWeight: hasChildren ? "bold" : "normal" },
        },
        [
          hasChildren ? (isExpanded.value ? "▼ " : "► ") : "• ",
          h("span", { class: "tree-node__key" }, `${props.node.key}: `),
          h("span", { class: "tree-node__value" }, String(props.node.value ?? "")),
        ]
      );

      const childrenVNode = hasChildren && isExpanded.value
        ? h(
            "div",
            { class: "tree-node__children", style: { paddingLeft: "20px" } },
            props.node.children!.map((child) =>
              h(JsonTreeViewer, { key: child.key, node: child })
            )
          )
        : null;

      return h("div", { class: "tree-node" }, [headerVNode, childrenVNode]);
    };
  },
});
```

---

## JSX / TSX in Vue 3

If your team prefers JSX syntax over `h()` function calls, configure the `@vitejs/plugin-vue-jsx` plugin:

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import vueJsx from "@vitejs/plugin-vue-jsx";

export default defineConfig({
  plugins: [vue(), vueJsx()],
});
```

```tsx
// src/components/Badge.tsx
import { defineComponent } from "vue";

export const Badge = defineComponent({
  props: {
    variant: { type: String, default: "primary" },
  },
  setup(props, { slots }) {
    return () => (
      <span class={`badge badge-${props.variant}`}>
        {slots.default?.()}
      </span>
    );
  },
});
```

---

## Troubleshooting & Best Practices

1. **Custom Directives and SSR**
   Custom directives that manipulate the DOM directly will crash during SSR because DOM APIs don't exist on the server. Nuxt/Vue provide `getSSRProps` hook for directives or use `<ClientOnly>` component wrappers.

2. **Always clean up event listeners in directive `unmounted` hook**
   Forgetting to remove document-level event listeners in `unmounted` will cause severe memory leaks and unexpected triggers as users navigate between pages.

3. **VNode Reuse Pitfall**
   Never mutate a VNode object or pass the same VNode instance into multiple places in the virtual tree. Always generate fresh VNodes using `h()`.
