# Module 01: Single File Components — SFC Structure & Template Syntax

**Track:** Vue — Progressive Web Framework
**Category:** Component Fundamentals

---

## The Single File Component Format

A `.vue` file is Vue's fundamental building block. It co-locates three concerns that belong together:

```vue
<script setup lang="ts">
// Logic: reactive state, computed values, event handlers, lifecycle hooks
</script>

<template>
  <!-- Structure: HTML augmented with Vue directives and dynamic expressions -->
</template>

<style scoped>
/* Presentation: CSS scoped to this component only */
</style>
```

This structure is compiled by Vite (via `@vitejs/plugin-vue`) into a JavaScript module. The template compiles to a render function — not interpreted at runtime but compiled to optimized virtual DOM code at build time.

---

## Template Syntax

### Text Interpolation: `{{ }}`

```vue
<script setup lang="ts">
const message = "Hello, Vue!";
const user = { name: "Alice", role: "admin" };
const now = new Date();
</script>

<template>
  <!-- Basic interpolation -->
  <p>{{ message }}</p>

  <!-- JavaScript expressions (one expression only, not statements)-->
  <p>{{ user.name.toUpperCase() }}</p>
  <p>{{ user.role === "admin" ? "Administrator" : "User" }}</p>
  <p>{{ now.toLocaleDateString("en-US", { weekday: "long" }) }}</p>

  <!-- Raw HTML (use with caution — XSS risk if content is user-provided) -->
  <p v-html="'<strong>Bold Text</strong>'"></p>
</template>
```

### Attribute Binding: `v-bind` / `:`

```vue
<script setup lang="ts">
import { ref, reactive } from "vue";

const imageUrl = ref("https://example.com/avatar.png");
const altText = ref("User avatar");
const isDisabled = ref(false);
const buttonClass = ref("btn btn-primary");
const inputStyles = reactive({ color: "#333", fontSize: "16px" });

// Object of multiple attributes to bind at once
const imgAttrs = reactive({
  src: "https://example.com/logo.png",
  alt: "Company logo",
  width: 200,
  height: 50,
});
</script>

<template>
  <!-- Bind a single attribute -->
  <img :src="imageUrl" :alt="altText" />

  <!-- Boolean attribute: presence controlled by truthy/falsy -->
  <button :disabled="isDisabled">Submit</button>

  <!-- Bind CSS class string -->
  <button :class="buttonClass">Click me</button>

  <!-- Bind CSS class object: key is class name, value is condition -->
  <button :class="{ active: isActive, error: hasError, primary: true }">
    Styled
  </button>

  <!-- Bind CSS class array -->
  <button :class="[buttonClass, { active: isActive }]">Mixed</button>

  <!-- Bind inline styles -->
  <p :style="inputStyles">Styled paragraph</p>

  <!-- Bind multiple attributes from an object using v-bind without argument -->
  <img v-bind="imgAttrs" />
</template>
```

### Event Handling: `v-on` / `@`

```vue
<script setup lang="ts">
import { ref } from "vue";

const count = ref(0);
const text = ref("");

function increment() { count.value++; }
function handleInput(event: Event) {
  text.value = (event.target as HTMLInputElement).value;
}
function handleKeydown(event: KeyboardEvent) {
  if (event.key === "Enter") console.log("Enter pressed:", text.value);
}
</script>

<template>
  <!-- Call a method -->
  <button @click="increment">Count: {{ count }}</button>

  <!-- Inline handler (for simple expressions) -->
  <button @click="count++">Increment</button>

  <!-- Pass the native event to the method -->
  <input @input="handleInput" />

  <!-- Access the event in an inline expression -->
  <button @click="(e) => console.log(e.clientX, e.clientY)">Track Click</button>

  <!-- Event modifiers: stop propagation, prevent default, etc. -->
  <form @submit.prevent="submitForm">
    <button type="submit">Submit</button>
  </form>

  <!-- Key modifiers -->
  <input @keydown.enter="submit" @keydown.esc="cancel" />
  <input @keydown="handleKeydown" />

  <!-- Mouse button modifiers -->
  <div @click.right.prevent="openContextMenu">Right-click me</div>

  <!-- Once modifier: fires the handler at most one time -->
  <button @click.once="initialize">Initialize (once only)</button>
</template>
```

Event modifier cheat sheet:

- `.stop` — calls `event.stopPropagation()`
- `.prevent` — calls `event.preventDefault()`
- `.self` — only fires if the target is the element itself (not a child)
- `.capture` — use capture mode (parent before child)
- `.passive` — sets the event as passive (improves scroll performance)
- `.once` — remove listener after it fires once
- `.enter`, `.tab`, `.delete`, `.esc`, `.space`, `.up`, `.down`, `.left`, `.right` — key modifiers

---

## Conditional Rendering: `v-if`, `v-else-if`, `v-else`, `v-show`

```vue
<script setup lang="ts">
import { ref } from "vue";

const status = ref<"loading" | "error" | "success">("loading");
const isVisible = ref(true);
</script>

<template>
  <!-- v-if: element is added/removed from DOM -->
  <div v-if="status === 'loading'">
    <span class="spinner">Loading...</span>
  </div>
  <div v-else-if="status === 'error'">
    <p class="error">Something went wrong.</p>
  </div>
  <div v-else>
    <p class="success">Data loaded successfully!</p>
  </div>

  <!-- v-show: element stays in DOM, visibility toggled with CSS display -->
  <!-- Use v-show for elements that toggle frequently -->
  <!-- Use v-if when the element is rarely shown (avoids initial render cost) -->
  <div v-show="isVisible">
    This is visible when isVisible is true.
  </div>

  <!-- Group multiple elements with <template> (renders no extra DOM element) -->
  <template v-if="status === 'success'">
    <h2>Welcome!</h2>
    <p>Here is your dashboard.</p>
    <nav>...</nav>
  </template>
</template>
```

---

## List Rendering: `v-for`

```vue
<script setup lang="ts">
import { ref } from "vue";

const items = ref([
  { id: 1, name: "Apple", category: "fruit" },
  { id: 2, name: "Banana", category: "fruit" },
  { id: 3, name: "Carrot", category: "vegetable" },
]);

const user = { name: "Alice", role: "admin", active: true };
</script>

<template>
  <!-- Always provide a :key for lists — enables efficient DOM updates -->
  <ul>
    <li v-for="item in items" :key="item.id">
      {{ item.name }} — {{ item.category }}
    </li>
  </ul>

  <!-- Access the index -->
  <ol>
    <li v-for="(item, index) in items" :key="item.id">
      {{ index + 1 }}. {{ item.name }}
    </li>
  </ol>

  <!-- Iterate over object entries -->
  <dl>
    <template v-for="(value, key) in user" :key="key">
      <dt>{{ key }}</dt>
      <dd>{{ value }}</dd>
    </template>
  </dl>

  <!-- v-for with a range -->
  <span v-for="n in 5" :key="n">{{ n }} </span>
  <!-- Renders: 1 2 3 4 5 -->

  <!-- v-for + v-if: v-if on inner template, v-for on outer (v-for takes priority) -->
  <ul>
    <template v-for="item in items" :key="item.id">
      <li v-if="item.category === 'fruit'">{{ item.name }}</li>
    </template>
  </ul>
</template>
```

**Critical**: Never use `v-for` and `v-if` on the same element. The order of evaluation is `v-if` first (in Vue 3), meaning the loop variable is not available inside the `v-if`. Wrap with `<template v-for>` and put `v-if` inside.

---

## Two-Way Binding: `v-model`

`v-model` is shorthand for `:value` + `@input` (or `@change`). It creates a bidirectional binding between form inputs and reactive data:

```vue
<script setup lang="ts">
import { ref } from "vue";

const text = ref("");
const number = ref(0);
const checked = ref(false);
const selected = ref("vue");
const multiSelect = ref<string[]>([]);
const checkedItems = ref<string[]>([]);

// v-model on a component: uses modelValue prop and update:modelValue emit
const searchQuery = ref("");
</script>

<template>
  <!-- Text input -->
  <input v-model="text" type="text" />
  <p>You typed: {{ text }}</p>

  <!-- Number input: .number modifier converts string to number automatically -->
  <input v-model.number="number" type="number" />

  <!-- Trim whitespace automatically -->
  <input v-model.trim="text" type="text" />

  <!-- Lazy: update on change (blur) rather than input (keypress) -->
  <input v-model.lazy="text" type="text" />

  <!-- Checkbox: single boolean -->
  <input v-model="checked" type="checkbox" id="agree" />
  <label for="agree">I agree</label>

  <!-- Checkbox: multiple values → array -->
  <input v-model="checkedItems" type="checkbox" value="apple" id="apple" />
  <label for="apple">Apple</label>
  <input v-model="checkedItems" type="checkbox" value="banana" id="banana" />
  <label for="banana">Banana</label>
  <p>Selected: {{ checkedItems }}</p>

  <!-- Radio buttons -->
  <input v-model="selected" type="radio" value="vue" id="vue" />
  <label for="vue">Vue</label>
  <input v-model="selected" type="radio" value="react" id="react" />
  <label for="react">React</label>

  <!-- Select dropdown -->
  <select v-model="selected">
    <option value="vue">Vue</option>
    <option value="react">React</option>
    <option value="svelte">Svelte</option>
  </select>

  <!-- Multi-select -->
  <select v-model="multiSelect" multiple>
    <option v-for="opt in ['vue', 'react', 'angular']" :key="opt" :value="opt">
      {{ opt }}
    </option>
  </select>
</template>
```

---

## The `key` Attribute

The `key` attribute is Vue's way of tracking which DOM nodes correspond to which list items. Without `key`, Vue reuses existing DOM nodes by position — which causes bugs when list order changes or items are inserted/removed:

```vue
<template>
  <!-- Wrong: Vue may reuse an old <li> for a different item -->
  <li v-for="item in list">{{ item.name }}</li>

  <!-- Correct: Vue can efficiently add, remove, and reorder items -->
  <li v-for="item in list" :key="item.id">{{ item.name }}</li>

  <!-- Also use key to force component re-creation when a prop changes -->
  <!-- Changing the key destroys and re-creates the component -->
  <UserProfile :key="userId" :user-id="userId" />
</template>
```

---

## Troubleshooting

### `v-for` doesn't update the DOM when array is mutated

Vue tracks array mutations for the following methods: `push`, `pop`, `shift`, `unshift`, `splice`, `sort`, `reverse`. Direct index assignment (`arr[0] = newValue`) is **not** tracked in Vue 3 if `arr` is a plain array. Use `arr.splice(0, 1, newValue)` or replace the array: `arr.value = [...arr.value]`.

### `v-if` and `v-for` on the same element causes unexpected behavior

In Vue 3, `v-if` has higher priority than `v-for` on the same element (opposite of Vue 2). The `v-if` condition cannot access the loop variable. Always use `<template v-for>` as the outer wrapper.

### Two-way binding on a component doesn't work

When using `v-model` on a custom component, the component must accept a `modelValue` prop and emit `update:modelValue`. Use `defineModel()` (Vue 3.4+) as the simplest way to implement this.
