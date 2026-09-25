// IMPORTANT IMPORT FILES FOR VULKAN AND ODIN 

package main

import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"

// WHY IS THIS FILE DIFFERENT - 
/* OpenGL hides a LOT of setup from you -- glfw.MakeContextCurrent() secretly does most of the "talk to the GPU" plumbing in one call. Vulkan hides NOTHING. Before you can do anything at all 
even just load a shader you must manually create an "instance" (the app's connection to the vulkan driver) and a "device" (your actual GPU, selected and set up by hand). That's what most of this file's main() is doing before it ever gets to the shader-loading part you actually asked about. */ 

