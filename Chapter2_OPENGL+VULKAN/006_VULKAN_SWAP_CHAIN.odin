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
create_instance :: proc() -> vk.Instance {
	layers := []cstring{"VK_LAYER_KHRONOS_validation"}
	glfw_extensions := glfw.GetRequiredInstanceExtensions()

	extensions := make([dynamic]cstring)
	defer delete(extensions)
	append(&extensions, ..glfw_extensions)
	append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	append(&extensions, vk.EXT_DEBUG_REPORT_EXTENSION_NAME)
