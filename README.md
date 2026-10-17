# ⚡ Odin-Opengl-Vulkan-Projects

Learning graphics programming from the ground up in [Odin](https://odin-lang.org), one chapter at a time. It starts with OpenGL and works toward Vulkan.

```odin
package main

import "core:fmt"

main :: proc() {
	fmt.println("Hellope")
}
```

## What this repo is

This is a learning log in code, organized into 9 chapters. Each chapter is a set of numbered, self-contained files that build on the ones before: a triangle, a spinning cube, a UI, a profiler, a loaded 3D model, and eventually a Vulkan renderer. Nothing here is a framework or a finished engine. It's the stuff I build while figuring out how a GPU actually gets pixels on the screen.

If you're learning graphics too, feel free to read, fork, or steal anything useful.

## 🌀 Why Odin

I could have done all of this in C++. I picked Odin because I wanted to spend my time learning graphics, not fighting my tools.

- **One command to build and run.** `odin run file.odin -file` and that's it. No CMake, no header files, no include-order puzzles, no linker flags to hunt down.
- **Fast compile times.** The edit, run, see-what-broke loop stays short, which matters a lot when you're experimenting with shaders and matrices.
- **Graphics libraries ship with the language.** Odin's `vendor:` collection includes bindings for GLFW, OpenGL, Vulkan, cgltf, stb and MicroUI. I didn't need to download, build and wire up a pile of dependencies before drawing my first triangle.
- **Math is built in.** Matrices and vectors are first-class types, and `core:math/linalg` covers the usual transforms. No separate GLM-style dependency.
- **Nothing hides from you.** Memory is explicit, allocators are passed around on purpose, and there are no hidden constructors, exceptions or operator overloads. When something breaks, the cause is in the code you can see. That is exactly what you want when you're trying to understand a GPU pipeline rather than just use one.
- **It's pleasant to write.** `defer` makes cleanup easy, structs are plain data, and the syntax stays out of the way. For learning, staying motivated counts for more than people admit.

### Honest trade-offs

Odin is not "better than C++" in general. It's better for what I'm doing right now.

- The ecosystem is much smaller. There are fewer tutorials, fewer Stack Overflow answers, and fewer third-party libraries.
- The language is still evolving, so things can change between compiler releases.
- Most graphics learning material is written in C++, so I translate it as I go. That is slower, but it's also a good way to make sure I understand each line instead of copy-pasting it.

## 🎯 What I'm trying to achieve

- Get comfortable with Odin's syntax and way of thinking.
- Understand how rendering actually works, not just call a library and hope. That means vertex data, shaders, matrices, depth, textures and the render loop.
- Move from OpenGL to Vulkan, and understand why Vulkan's extra layers exist (instances, devices, swapchains, pipelines, descriptor sets) instead of skipping straight to a framework.
- Ship something that runs at every step, rather than only following tutorials I'll forget in a week.
- Eventually build my own small renderer and tools on top of what I've learned.

No rush, no shortcuts. Steady reps.

## 🧱 Chapters

The repo has 9 chapters, loosely following the order of the *3D Graphics Rendering Cookbook*, ported from C++ to Odin. The book's opening chapter on setting up a build environment is skipped, because in Odin the build environment is just the compiler.

| Chapter | Focus | Status |
|---|---|---|
| 1 | Basic OpenGL and Odin: windows, shaders, first 3D | 🟢 Done |
| 2 | OpenGL and Vulkan: getting started, mesh loading, first textures | 🟡 In progress |
| 3 | User interaction and productivity tools: UI, profiling, camera | 🟡 In progress |
| 4 | Working with geometry data | ⚪ Planned |
| 5 | Physically based rendering with the glTF2 shading model | ⚪ Planned |
| 6 | Graphics rendering pipeline | ⚪ Planned |
| 7 | Image-based techniques | ⚪ Planned |
| 8 | Working with scene graphs | ⚪ Planned |
| 9 | Advanced rendering techniques and optimizations | ⚪ Planned |

The order may shift as I learn what I actually need.

## 🛠 Running a project

**From source (any platform):**

1. Install Odin from <https://odin-lang.org/docs/install/>.
2. Clone this repo.
3. From the repo root, run a file:

```bash
odin run 001_TRIANGLE.odin -file
```

Run from the repo root so paths into `Assets/` resolve. If a project is set up as its own folder, `odin run .` works too.

**What you need:**

- A GPU and drivers that support OpenGL 4.6. For the Vulkan work, Vulkan 1.1 or newer.
- For Vulkan, the [Vulkan SDK](https://vulkan.lunarg.com/) is recommended, since it provides the validation layers that catch mistakes.

## 📦 About the `.exe` files

Each file also has a pre-built `.exe` next to its source. These are Windows only. Odin compiles to a normal standalone executable, so you can just double-click one and see it working without installing the compiler. They're unsigned, so Windows may show a SmartScreen warning. If you'd rather not run a random binary (fair enough), build from source.

## How I work

Much of the learning here follows the *3D Graphics Rendering Cookbook* (C++ with OpenGL and Vulkan), ported to Odin. Where the Odin version differs from the book, because the language does things differently or because I spotted a bug in the listing, I note it in comments in the source.

Build small things. Break them. Fix them. That's the whole method.

## 💬 For fellow beginners

If you're new to Odin too, welcome. It's a friendly low-level language to learn from because you can see what it's doing. No hidden allocations, no macro maze, no ten layers of abstraction between you and the machine.

If something here is wrong or could be clearer, open an issue. I'm learning as I go, and corrections are welcome.

⭐ If you're learning Odin, OpenGL or Vulkan, feel free to fork this and build alongside it.

## License

Released under a Creative Commons license. The full legal text is in the `LICENSE` file.
