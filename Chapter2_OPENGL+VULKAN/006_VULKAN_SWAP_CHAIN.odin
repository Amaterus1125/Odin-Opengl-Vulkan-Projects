// the basic package imports and the check for if vulkan call failed or not , very imp 
package main

import "core:fmt"

import "vendor:glfw"
import vk "vendor:vulkan"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}


// PART 1 - INSTANCE  DEVICE (same as previous recipe and file , you can just copy the 005 file here
