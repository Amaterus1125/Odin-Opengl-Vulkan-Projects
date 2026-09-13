# ⚡ Odin-Opengl-Vulkan-Projects

> just some OpenGL and Vulkan projects in Odin — learning graphics programming
> from the ground up, one project at a time.

```
package main

import "core:fmt"

main :: proc() {
	fmt.println("hello, joy of programming")
}
```

---

## 🌀 why Odin?

Odin is a language built for people who actually want to **understand** what their
code is doing — no hidden magic, no fighting a build system, no 40-minute compile
times. It's fast, simple, gives you manual control when you want it, and the syntax
gets out of your way instead of showing off.

It's also just... fun. It feels like the language *wants* you to keep building things,
not fight it. That's the whole point of this repo — chasing that feeling, with
graphics as the excuse.

> "Programming should feel like play, not paperwork."

---

## 🎯 my aim

I'm learning Odin, OpenGL, and eventually Vulkan, with a simple goal:

- go from **zero → comfortable** with Odin's syntax and mental model
- understand **how computers actually render things** (not just call a library and hope)
- build real, runnable projects at every step — not just tutorials I forget in a week
- work my way from basic OpenGL up to lower-level Vulkan, understanding *why*
  each layer exists instead of skipping straight to a framework
- eventually get comfortable enough to build my own tools/renderers from scratch

No rush, no shortcuts — just steady reps and shipping small working things.

---

## 🧱 roadmap: base → advanced

| Stage | Focus | Status |
|---|---|---|
| 001 — Triangle | window + first triangle, shaders, VAO/VBO | 🟢 done |
| 002 — Moving Cube | 3D cube, MVP matrices, depth test, wireframe overlay | 🟢 done |
| 003 — Lighting | normals, basic Phong/Blinn shading | ⚪ planned |
| 004 — Textures & Models | texture loading, loading real meshes | ⚪ planned |
| 005 — Camera & Input | free-look camera, keyboard/mouse control | ⚪ planned |
| 006 — Mini Engine | scene graph, entities, basic ECS-ish structure | ⚪ planned |
| 007 — Vulkan Basics | instance/device setup, first Vulkan triangle | ⚪ planned |
| 008 — Vulkan Pipeline | descriptor sets, pipelines, real rendering | ⚪ planned |

---

## 📁 projects so far

| File | What it does |
|---|---|
| `001_TRIANGLE.odin` | first window + a triangle with interpolated RGB colors |
| `002_MOVING_CUBE.odin` | rotating 3D cube using an MVP matrix + wireframe overlay |
| `003_MicroUI.odin` | the GUI for the game engines to control different things |
| *(more added as I build them)* | |

Each `.odin` file is runnable directly:

```bash
odin run 001_TRIANGLE.odin -file
```

or, if it's set up as its own project folder:

```bash
odin run .
```

---

## 📦 about the `.exe` files

Each project also has a pre-built `.exe` sitting next to its `.odin` source file.
Odin compiles down to a normal standalone executable, so you (or anyone else) can
just run the `.exe` directly and see the project working — **no need to install the
Odin compiler at all** if you just want to try it out. If you want to read/edit the
actual code, open the `.odin` file.

---

## 🛠 setup

1. Install Odin: https://odin-lang.org/docs/install/
2. Clone this repo
3. Pick a project file
4. `odin run <filename>.odin -file`

---

## 💬 a note to fellow beginners

If you're new to Odin too — welcome. It's one of the friendliest low-level languages
to actually *learn from*, because you can see everything it's doing. No hidden
allocations, no obscure macros, no 10-layer abstractions between you and the machine.

Build small things. Break them. Fix them. That's basically the whole method.

---

⭐ if you're also learning Odin, OpenGL, or Vulkan, feel free to fork this and build
alongside it.
