//SOME BASIC IMPORTS 
package main
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

/* Simplification worth knowing - Since we're already using GLFW (which knows what platform it's running on), GLFW can just TELL us the exact extensions needed for THIS
system, automatically, via glfw.GetRequiredInstanceExtensions(), So no manual OS detection needed at all. One less thing to hand maintain.
