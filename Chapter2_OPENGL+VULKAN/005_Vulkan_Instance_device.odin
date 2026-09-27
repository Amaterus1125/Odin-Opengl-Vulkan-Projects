//SOME BASIC IMPORTS 
package main
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

/* Simplification worth knowing - Since we're already using GLFW (which knows what platform it's running on), GLFW can just TELL us the exact extensions needed for THIS
system, automatically, via glfw.GetRequiredInstanceExtensions(), So no manual OS detection needed at all. One less thing to hand maintain.

// crashes the program with a message if a vulkan call didn't succeed same idea as the book's VK_ASSERT/VK_CHECK macros. Odin doesn't have macros the way C++ does, so this is just a normal proc instead
vk_check :: proc(result: vk.Result, what: string) {
if result != .SUCCESS {
fmt.println("VULKAN ERROR during", what, "-", result)
panic("vulkan call failed") // panic = odin's version of crashing on purpose with a message
	}
}
