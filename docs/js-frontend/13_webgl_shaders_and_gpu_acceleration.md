# Module 13: WebGL 2.0 Graphics, GLSL Shaders & GPU Acceleration

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** 3D Graphics, WebGL 2.0 Shaders & WebGPU Acceleration

---

## 1. What Is WebGL 2.0?

**WebGL 2.0** provides low-level JavaScript bindings to native GPU hardware via OpenGL ES 3.0.

Unlike the Canvas 2D API (which executes CPU-driven draw calls), WebGL allows you to write programs called **Shaders** that execute concurrently across **thousands of GPU cores simultaneously**.

```
WebGL 2.0 Programmable GPU Pipeline:
┌─────────────────────────────────────────────────────────────┐
│ 1. Vertex Buffer Objects (VBOs / VAOs)                      │
│    - 3D Coordinates (x, y, z), Normals, UV Texture Map      │
│                                                             │
│ 2. Vertex Shader (GLSL)                                     │
│    - Transforms 3D model vertices into Clip Space           │
│      (`gl_Position = uProjection * uView * vec4(pos, 1.0)`) │
│                                                             │
│ 3. Primitive Assembly & Hardware Rasterization              │
│    - Connects vertices into triangles & interpolates pixels │
│                                                             │
│ 4. Fragment Shader (GLSL)                                   │
│    - Computes RGB color, specular lighting, and textures    │
│      for every individual screen pixel (`outColor`)         │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Compiling GLSL Shaders in WebGL 2.0

### 1. Vertex Shader Source (GLSL 300 ES):

```glsl
#version 300 es
in vec3 aPosition;
in vec3 aColor;

uniform mat4 uModelViewMatrix;
uniform mat4 uProjectionMatrix;

out vec3 vColor;

void main() {
    vColor = aColor;
    gl_Position = uProjectionMatrix * uModelViewMatrix * vec4(aPosition, 1.0);
}
```

### 2. Fragment Shader Source (GLSL 300 ES):

```glsl
#version 300 es
precision highp float;

in vec3 vColor;
out vec4 outColor;

void main() {
    outColor = vec4(vColor, 1.0);
}
```

---

## 3. WebGL 2.0 Boilerplate Helper (Compilation & Program Linking)

```javascript
// src/graphics/webgl_utils.js

export function createShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);

  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Shader compile error: ${info}`);
  }
  return shader;
}

export function createProgram(gl, vertexShader, fragmentShader) {
  const program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const info = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(`Program link error: ${info}`);
  }
  return program;
}
```

---

## 4. Complete Raw WebGL 2.0 Spinning Colored Triangle

Here is a 100% self-contained WebGL 2.0 implementation with **zero external libraries**:

```javascript
// src/graphics/spinning_triangle.js
import { createShader, createProgram } from './webgl_utils.js';

const vsSource = `#version 300 es
in vec2 aPosition;
in vec3 aColor;
uniform float uAngle;
out vec3 vColor;

void main() {
    vColor = aColor;
    // Rotate 2D coordinates dynamically on GPU:
    float cosA = cos(uAngle);
    float sinA = sin(uAngle);
    mat2 rotation = mat2(cosA, -sinA, sinA, cosA);

    gl_Position = vec4(rotation * aPosition, 0.0, 1.0);
}
`;

const fsSource = `#version 300 es
precision mediump float;
in vec3 vColor;
out vec4 fragColor;

void main() {
    fragColor = vec4(vColor, 1.0);
}
`;

export class WebGlTriangleApp {
  constructor(canvas) {
    this.gl = canvas.getContext('webgl2');
    if (!this.gl) throw new Error('WebGL 2.0 not supported on this device.');

    this.angle = 0;
    this._initPipeline();
  }

  _initPipeline() {
    const gl = this.gl;

    // 1. Compile Shaders & Link Program:
    const vs = createShader(gl, gl.VERTEX_SHADER, vsSource);
    const fs = createShader(gl, gl.FRAGMENT_SHADER, fsSource);
    this.program = createProgram(gl, vs, fs);

    // 2. Vertex Data (Interleaved: [X, Y, R, G, B]):
    const vertexData = new Float32Array([
      // X,    Y,      R,   G,   B
       0.0,  0.6,    1.0, 0.2, 0.3, // Top (Red)
      -0.6, -0.6,    0.2, 1.0, 0.4, // Bottom Left (Green)
       0.6, -0.6,    0.3, 0.5, 1.0, // Bottom Right (Blue)
    ]);

    // 3. Create Vertex Array Object (VAO) & VBO:
    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);

    const vbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW);

    // 4. Configure Attributes:
    const aPosition = gl.getAttribLocation(this.program, 'aPosition');
    gl.enableVertexAttribArray(aPosition);
    gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 5 * 4, 0);

    const aColor = gl.getAttribLocation(this.program, 'aColor');
    gl.enableVertexAttribArray(aColor);
    gl.vertexAttribPointer(aColor, 3, gl.FLOAT, false, 5 * 4, 2 * 4);

    // 5. Look up Uniform Locations:
    this.uAngleLoc = gl.getUniformLocation(this.program, 'uAngle');
  }

  render() {
    const gl = this.gl;

    // Clear Color Buffer:
    gl.clearColor(0.06, 0.09, 0.16, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(this.program);
    gl.bindVertexArray(this.vao);

    // Update Uniform Angle:
    this.angle += 0.02;
    gl.uniform1f(this.uAngleLoc, this.angle);

    // Draw Triangle:
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    requestAnimationFrame(() => this.render());
  }
}
```

---

## 5. The Future: WebGPU Overview

While WebGL 2.0 is based on 1990s OpenGL state machines, **WebGPU** is the next-generation W3C graphics and compute standard:
- Designed around modern explicit GPU architectures (**Apple Metal, Vulkan, DirectX 12**).
- Supports **Compute Shaders** for machine learning (running LLMs and neural nets directly in the browser via WebGPU!).
- Reduces JavaScript driver overhead by over **60%**.

---

## Troubleshooting & Best Practices

1. **Always Use Vertex Array Objects (VAOs)**
   In WebGL 2, VAOs are mandatory. A VAO remembers all buffer bindings and attribute pointers, allowing you to switch complex 3D meshes with a single `gl.bindVertexArray(vao)` call.

2. **Always Handle WebGL Context Loss**
   When the mobile device enters low memory or graphics driver resets, the browser drops the WebGL context. Listen to `canvas.addEventListener('webglcontextlost', (e) => e.preventDefault())` and re-initialize shaders on `webglcontextrestored`.
