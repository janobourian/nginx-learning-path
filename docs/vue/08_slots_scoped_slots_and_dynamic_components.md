# Module 08: Slots, Scoped Slots & Dynamic Components

**Track:** Vue — Progressive Web Framework
**Category:** Component Composition & Flexibility

---

## Slots: Content Projection

Slots are Vue's mechanism for passing template content from a parent into a child component. This enables building generic "shell" components that know their layout but not their content.

---

## Default Slots

```vue
<!-- components/AppCard.vue -->
<script setup lang="ts">
defineProps<{
  title: string;
  variant?: "default" | "info" | "success" | "warning" | "danger";
}>();
</script>

<template>
  <div class="card" :class="`card--${variant ?? 'default'}`">
    <header class="card__header">
      <h3>{{ title }}</h3>
    </header>
    <main class="card__body">
      <!-- Default slot: parent puts content here -->
      <slot />
    </main>
  </div>
</template>
```

```vue
<!-- Parent: using the card -->
<template>
  <AppCard title="User Profile">
    <!-- This content goes into the default slot -->
    <img :src="user.avatar" alt="Avatar" />
    <p>{{ user.bio }}</p>
  </AppCard>
</template>
```

### Fallback Content

If the parent provides no content, the slot shows its default:

```vue
<template>
  <slot>
    <!-- Fallback content: shown when parent provides nothing -->
    <p class="empty-state">No content provided.</p>
  </slot>
</template>
```

---

## Named Slots

Named slots allow multiple injection points in one component:

```vue
<!-- components/AppLayout.vue -->
<template>
  <div class="layout">
    <header class="layout__header">
      <slot name="header">
        <!-- Fallback header -->
        <h1>Default Title</h1>
      </slot>
    </header>

    <aside class="layout__sidebar">
      <slot name="sidebar" />
    </aside>

    <main class="layout__main">
      <!-- Default slot for the main content -->
      <slot />
    </main>

    <footer class="layout__footer">
      <slot name="footer">
        <p>© {{ new Date().getFullYear() }} My App</p>
      </slot>
    </footer>
  </div>
</template>
```

```vue
<!-- Using named slots with v-slot directive -->
<template>
  <AppLayout>
    <template #header>
      <nav>
        <RouterLink to="/">Home</RouterLink>
        <RouterLink to="/products">Products</RouterLink>
      </nav>
    </template>

    <template #sidebar>
      <FilterPanel />
    </template>

    <!-- Default slot (no name) — goes into <slot /> -->
    <ProductGrid :products="products" />

    <template #footer>
      <FooterLinks />
    </template>
  </AppLayout>
</template>
```

`#header` is shorthand for `v-slot:header`.

---

## Scoped Slots — Passing Data Upward

Scoped slots invert the normal pattern: the child component **passes data up to the parent's template**. This enables the parent to customize rendering while the child owns the data/logic.

```vue
<!-- components/DataTable.vue — generic table that exposes row data -->
<script setup lang="ts">
interface Props<T> {
  data: T[];
  columns: { key: string; label: string }[];
}

const props = defineProps<Props<Record<string, unknown>>>();
</script>

<template>
  <table>
    <thead>
      <tr>
        <th v-for="col in columns" :key="col.key">{{ col.label }}</th>
        <!-- Action column slot header -->
        <th v-if="$slots.actions">Actions</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="(row, index) in data" :key="index">
        <td v-for="col in columns" :key="col.key">
          <!-- Named slot for each cell, passing row and column data -->
          <slot :name="`cell-${col.key}`" :row="row" :value="row[col.key]" :index="index">
            <!-- Fallback: default rendering -->
            {{ row[col.key] }}
          </slot>
        </td>
        <td v-if="$slots.actions">
          <!-- Scoped slot for actions, exposes the row data -->
          <slot name="actions" :row="row" :index="index" />
        </td>
      </tr>
    </tbody>
  </table>
</template>
```

```vue
<!-- Parent: uses the generic DataTable with custom cell rendering -->
<template>
  <DataTable :data="users" :columns="columns">
    <!-- Custom cell for 'active' column -->
    <template #cell-active="{ value }">
      <span :class="value ? 'badge-green' : 'badge-red'">
        {{ value ? "Active" : "Inactive" }}
      </span>
    </template>

    <!-- Custom cell for 'name' column -->
    <template #cell-name="{ row, value }">
      <div class="user-name-cell">
        <img :src="row.avatar" class="avatar-sm" />
        <strong>{{ value }}</strong>
      </div>
    </template>

    <!-- Action buttons with access to each row -->
    <template #actions="{ row }">
      <button @click="editUser(row.id)">Edit</button>
      <button @click="deleteUser(row.id)" class="danger">Delete</button>
    </template>
  </DataTable>
</template>

<script setup lang="ts">
const columns = [
  { key: "name", label: "Name" },
  { key: "email", label: "Email" },
  { key: "active", label: "Status" },
];
const users = [
  { id: "1", name: "Alice", email: "alice@example.com", active: true, avatar: "/img/a.png" },
];
function editUser(id: string) { /* ... */ }
function deleteUser(id: string) { /* ... */ }
</script>
```

---

## `$slots` — Checking Slot Presence

```vue
<script setup lang="ts">
import { useSlots } from "vue";

const slots = useSlots();

// Check if a slot has been provided by the parent
const hasHeader = computed(() => !!slots.header);
const hasFooter = computed(() => !!slots.footer);
</script>

<template>
  <!-- Conditionally render wrapper elements if slot is provided -->
  <header v-if="hasHeader" class="card__header">
    <slot name="header" />
  </header>

  <main class="card__body">
    <slot />
  </main>

  <footer v-if="hasFooter" class="card__footer">
    <slot name="footer" />
  </footer>
</template>
```

---

## Dynamic Components

`<component :is="...">` renders a different component based on a runtime value:

```vue
<script setup lang="ts">
import { ref, markRaw } from "vue";
import TextWidget from "@/components/widgets/Text.vue";
import ChartWidget from "@/components/widgets/Chart.vue";
import TableWidget from "@/components/widgets/Table.vue";
import MapWidget from "@/components/widgets/Map.vue";

type WidgetType = "text" | "chart" | "table" | "map";

// Use markRaw to prevent Vue from making the component definition reactive (perf)
const widgetComponents = {
  text: markRaw(TextWidget),
  chart: markRaw(ChartWidget),
  table: markRaw(TableWidget),
  map: markRaw(MapWidget),
};

const activeWidget = ref<WidgetType>("text");
const tabs: { id: WidgetType; label: string }[] = [
  { id: "text", label: "Text" },
  { id: "chart", label: "Chart" },
  { id: "table", label: "Table" },
  { id: "map", label: "Map" },
];
</script>

<template>
  <!-- Tab navigation -->
  <nav>
    <button
      v-for="tab in tabs"
      :key="tab.id"
      @click="activeWidget = tab.id"
      :class="{ active: activeWidget === tab.id }"
    >
      {{ tab.label }}
    </button>
  </nav>

  <!-- Renders the correct widget component based on activeWidget -->
  <component :is="widgetComponents[activeWidget]" />
</template>
```

---

## `<KeepAlive>` — Preserving Component State

By default, when a dynamic component is hidden (another is shown), it is destroyed. `<KeepAlive>` keeps the component instance in memory:

```vue
<template>
  <!-- Without KeepAlive: TextWidget is destroyed when switching to ChartWidget -->
  <component :is="currentWidget" />

  <!-- With KeepAlive: all switched-out components are cached -->
  <KeepAlive>
    <component :is="currentWidget" />
  </KeepAlive>

  <!-- Cache only specific components by name -->
  <KeepAlive :include="['TextWidget', 'ChartWidget']">
    <component :is="currentWidget" />
  </KeepAlive>

  <!-- Limit cache size: destroys least recently used when full -->
  <KeepAlive :max="5">
    <component :is="currentWidget" />
  </KeepAlive>
</template>
```

Components inside `<KeepAlive>` get two additional lifecycle hooks:

```typescript
import { onActivated, onDeactivated } from "vue";

// Called when the component is re-shown from keep-alive cache
onActivated(() => {
  // Resume: restart timers, re-subscribe to events, refresh data
  startLiveDataFeed();
});

// Called when the component is hidden (but not destroyed) by keep-alive
onDeactivated(() => {
  // Pause: stop timers, unsubscribe to save resources
  stopLiveDataFeed();
});
```

---

## Troubleshooting

### Scoped slot variable is `undefined`

The slot attribute in the child must use `:attribute="value"` (bound), not `attribute="value"` (string literal). In `<slot name="row" :data="rowData" />`, the parent accesses it as `<template #row="{ data }">`.

### `<KeepAlive>` is not caching the component

`<KeepAlive>` only works with direct children of `<component :is>`, `<RouterView>`, or another single component. It does not work when wrapping multiple elements or when the component is nested deeper. Also ensure the component has a `name` property (set automatically from the filename in `<script setup>`, or set explicitly with `defineOptions({ name: 'MyComponent' })`).

### Dynamic component throws "Failed to resolve component"

The `:is` prop accepts a component options object (`markRaw(MyComponent)`), a registered name string (if globally registered), or an async component. If using a string like `"TextWidget"`, the component must be globally registered. Use `markRaw(import)` for locally imported components.
