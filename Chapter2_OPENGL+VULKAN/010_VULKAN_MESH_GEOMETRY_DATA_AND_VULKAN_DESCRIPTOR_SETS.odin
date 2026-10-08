
// will be using the rubber_duck asset here 


// the normal imports above every file 
package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"
import stbi "vendor:stb/image"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}

