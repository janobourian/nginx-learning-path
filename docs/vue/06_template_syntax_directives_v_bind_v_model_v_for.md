# Module 06: Template Syntax — Directives, `v-bind`, `v-model`, `v-for`

**Track:** Vue — Progressive Web Framework  
**Category:** Template Language & Data Binding

---

## Vue Template Compilation

Vue templates are not interpreted at runtime — they are compiled to JavaScript render functions at build time (by Vite's Vue plugin). This compilation step enables significant optimizations: Vue marks static parts of the template as "hoisted" (created once, not on every render), and marks dynamic parts with patch flags (bitmask hints) so the virtual DOM diff can skip nodes that cannot change.

Understanding this compilation model helps you write templates that Vue can optimize aggressively.

---

## Static vs Dynamic Content

```vue
<template>
  <!-- STATIC: Vue hoists this and never re-renders it -->
  <h1>My Application</h1>

  <!-- DYNAMIC: Vue tracks that `title` can change -->
  <h2>{{ title }}</h2>

  <!-- STATIC ATTRIBUTE: `type="text"` never changes -->
  <!-- DYNAMIC ATTRIBUTE: `:placeholder="hint"` may change -->
  <input type="text" :placeholder="hint" />
</template>
```

When Vue compiles this, it creates the `<h1>` node once (hoisted out of the render function) and patches only the `<h2>` text and `input.placeholder` attribute on updates.

---

## `v-bind` Mastery

`v-bind:` (shorthand `:`) binds a JavaScript expression to an attribute. The expression is evaluated and its result becomes the attribute value.

### Dynamic Attribute Names

```vue
<script setup lang="ts">
const dynamicAttr = "disabled";
const value = true;
</script>

<template>
  <!-- Bind the attribute name dynamically — rare but valid -->
  <button :[dynamicAttr]="value">Dynamic Attribute</button>
  <!-- Renders: <button disabled="true"> -->
</template>
```

### Class Bindings (Object and Array Syntax)

```vue
<script setup lang="ts">
import { ref, computed } from "vue";

const isActive = ref(true);
const hasError = ref(false);
const size = ref<"sm" | "md" | "lg">("md");

const buttonClasses = computed(() => ({
  "btn": true,
  "btn--active": isActive.value,
  "btn--error": hasError.value,
  [`btn--${size.value}`]: true,
}));
</script>

<template>
  <!-- Object syntax: key = class name, value = boolean condition -->
  <button :class="{ active: isActive, error: hasError }">
    Object Syntax
  </button>

  <!-- Array syntax: combine multiple class bindings -->
  <button :class="['btn', isActive ? 'active' : '', { error: hasError }]">
    Array Syntax
  </button>

  <!-- Computed class object: cleaner for complex conditions -->
  <button :class="buttonClasses">Computed Classes</button>

  <!-- Merge static and dynamic classes: Vue merges them -->
  <button class="fixed-class" :class="{ dynamic: isActive }">
    Mixed
  </button>
  <!-- Renders: class="fixed-class dynamic" when isActive is true -->
</template>
```

### Style Bindings

```vue
<script setup lang="ts">
import { ref, computed } from "vue";

const primaryColor = ref("#42b883");
const fontSize = ref(16);
const spacing = ref(8);

const cardStyles = computed(() => ({
  backgroundColor: primaryColor.value,
  fontSize: `${fontSize.value}px`,
  padding: `${spacing.value}px`,
  borderRadius: "4px",
}));
</script>

<template>
  <!-- Object syntax -->
  <div :style="{ color: primaryColor, fontSize: fontSize + 'px' }">
    Inline Styles Object
  </div>

  <!-- Computed styles object -->
  <div :style="cardStyles">Computed Styles</div>

  <!-- Array: merge multiple style objects (later takes precedence) -->
  <div :style="[baseStyles, cardStyles]">Array of Styles</div>

  <!-- Vendor prefix auto-handling: Vue adds prefixes automatically -->
  <div :style="{ transform: 'rotate(45deg)' }">Auto-prefixed</div>
</template>
```

---

## `v-model` with Custom Components

`v-model` on a custom component requires the component to accept a `modelValue` prop and emit `update:modelValue`. Vue 3.4+ introduced `defineModel()` to simplify this:

```vue
<!-- components/AppInput.vue -->
<script setup lang="ts">
// Vue 3.4+: defineModel creates the prop and emit automatically
const model = defineModel<string>({ required: true });

// With validation
const validatedModel = defineModel<number>("count", {
  required: false,
  default: 0,
  set: (value: number) => Math.max(0, Math.min(100, value)), // Clamp 0-100
});
</script>

<template>
  <input
    :value="model"
    @input="model = ($event.target as HTMLInputElement).value"
    class="app-input"
  />
</template>
```

```vue
<!-- Using the component -->
<script setup lang="ts">
import { ref } from "vue";
import AppInput from "@/components/AppInput.vue";

const username = ref("");
const volume = ref(50);
</script>

<template>
  <AppInput v-model="username" />
  <!-- Equivalent to: <AppInput :modelValue="username" @update:modelValue="username = $event" /> -->

  <!-- Multiple v-model bindings on one component -->
  <UserForm v-model:firstName="firstName" v-model:lastName="lastName" />
</template>
```

Manual implementation without `defineModel()` (Vue 3.3 and earlier):

```vue
<script setup lang="ts">
// Before defineModel():
interface Props { modelValue: string }
const props = defineProps<Props>();
const emit = defineEmits<{ "update:modelValue": [value: string] }>();

function onInput(event: Event) {
  emit("update:modelValue", (event.target as HTMLInputElement).value);
}
</script>
```

### `v-model` Modifiers on Custom Components

```vue
<!-- Parent: pass modifiers to custom v-model -->
<CustomInput v-model.trim.uppercase="text" />

<!-- Child: access modifiers via defineModel -->
<script setup lang="ts">
const [model, modifiers] = defineModel<string>({
  set(value) {
    let result = value;
    if (modifiers.trim) result = result.trim();
    if (modifiers.uppercase) result = result.toUpperCase();
    return result;
  },
});
</script>
```

---

## `v-for` Advanced Patterns

```vue
<script setup lang="ts">
import { ref, computed } from "vue";

interface TreeNode {
  id: number;
  label: string;
  children?: TreeNode[];
}

const tree = ref<TreeNode[]>([
  {
    id: 1,
    label: "Root",
    children: [
      { id: 2, label: "Child 1", children: [
        { id: 4, label: "Grandchild 1" }
      ]},
      { id: 3, label: "Child 2" },
    ],
  },
]);
</script>

<template>
  <!-- Nested v-for: render a tree recursively -->
  <!-- (In practice, use a recursive component — see Module 15) -->
  <ul>
    <li v-for="node in tree" :key="node.id">
      {{ node.label }}
      <ul v-if="node.children">
        <li v-for="child in node.children" :key="child.id">
          {{ child.label }}
        </li>
      </ul>
    </li>
  </ul>

  <!-- v-for with component: each item renders a child component -->
  <ProductCard
    v-for="product in products"
    :key="product.id"
    :product="product"
    @add-to-cart="handleAddToCart(product.id)"
  />

  <!-- Range iteration -->
  <span v-for="i in 5" :key="i" class="dot" :class="{ active: i <= rating }">
    ★
  </span>
</template>
```

---

## `v-bind` with Object Shorthand (v-bind without argument)

```vue
<script setup lang="ts">
const inputProps = {
  type: "email",
  required: true,
  autocomplete: "email",
  placeholder: "Enter your email",
  "aria-label": "Email address",
};
</script>

<template>
  <!-- Spread all properties onto the element at once -->
  <input v-bind="inputProps" />
  <!-- Renders: <input type="email" required autocomplete="email" placeholder="..." aria-label="..." /> -->

  <!-- Useful for passing through props to native elements in wrapper components -->
</template>
```

---

## Template Refs with `v-for`

When `v-for` is used with `ref`, the ref is populated with an array:

```vue
<script setup lang="ts">
import { ref, onMounted } from "vue";

const items = ref(["Apple", "Banana", "Cherry"]);
const itemRefs = ref<HTMLLIElement[]>([]);

onMounted(() => {
  console.log(itemRefs.value);  // Array of 3 <li> elements
  itemRefs.value[0]?.focus();
});
</script>

<template>
  <ul>
    <li
      v-for="(item, i) in items"
      :key="item"
      ref="itemRefs"
      tabindex="0"
    >
      {{ i + 1 }}. {{ item }}
    </li>
  </ul>
</template>
```

---

## Troubleshooting

**`v-bind` class object: class not applied despite condition being `true`**

Ensure the class name doesn't contain hyphens or special characters without quotes. Object keys with hyphens must be quoted: `{ 'is-active': isActive }`, not `{ is-active: isActive }` (which is a syntax error).

**`v-model` on a custom component not working**

The most common cause: the component uses `value` prop (Vue 2 style) but the parent uses `v-model` (which binds to `modelValue`). Migrate to `defineModel()` or ensure the prop is named `modelValue` and the emit is `update:modelValue`.

**`v-for` items render in wrong order after array update**

Without a stable `:key`, Vue reuses DOM nodes by position. If you remove an item from the middle of the list, Vue may reuse the wrong DOM nodes. Always use a unique, stable identifier for `:key` (like a database ID), not the array index.
