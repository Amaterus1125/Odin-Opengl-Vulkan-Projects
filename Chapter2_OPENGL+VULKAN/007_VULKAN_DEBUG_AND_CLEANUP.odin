// the basic imports 
package main

import "base:runtime"
import "core:fmt"

import "vendor:glfw"
import vk "vendor:vulkan"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}

/*PART 1 - THE DEBUG CALLBACKS 
these 2 functions below won't get called by us , vulkan's validation layer calls them automatically on it's own whenever it spots 
a mistake. our job is just to tell it "when that happens , run this code" which we do in setup_debug_callbacks */

// the modern general purpose one - just prints whatever message vulkan gives us 
vulkan_debug_callback :: proc "c" { 
message_severity : vk.DebugUtilsMessageSeverityFlagsEXT,
message_type : vk.DebugUtilsMessageTypeFlagsEXT , 
callback_data : ^vk.DebugUtilsMessangerCallbackDataEXT,
user_data : rawptr , 
) -> b32 { 
 context = runtime.default_context() // required anytime a C callback needs to use normal odin code (like fmt here) 
 fmt.println("Validation Layer:" , callback_data.pMessage) 
return false 
} 

