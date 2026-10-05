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

/* the older more detaield one - also tells us which vulkan object caused the issue, which is useful for tracking down exactly what you misconfigured, we skip printing pure performance 
warnings so the output doesn't get too noisy to actually read */

vulkan_debug_report_callback :: proc "c" (
flags: vk.DebugReportFlagsEXT,
object_type : vk.DebugReportObjectTypeEXT , 
object : u64
location : int , 
message_code : i32 ,
layer_prefix: cstring , 
message : cstring , 
user_data: rawptr, 
) -> b32 { 
context = runtime.default_context() 
 if .PERFORMANCE_WARNING in flags { 
return false } 
fmt.println("Debug callbacks (" , layer_prefix, "):" , message) 
 return false 
} 

// registers both callbacks above with vulkan, this is the part that actually turns them on 
setup_debug_callbacks :: proc(instance:vk.Instance) -> (messenger: vk.DebugUtilsMessengerEXT , report_callback: vk.DebugReportCallbackEXT) { 
  messenger_info := vk.DebugUtilsMessengerCreateInfoEXT{ 
 sType = .DEBUG_UTILS-MESSENGER-CREATE-INFO-EXT, 
 messageSeverity = {.WARNING , .ERROR} ,
messageType = {.GENERAL , .VALIDATION , .PERFORMANCE} , 
pfnUserCallback = vulkan_debug_callback , 
} 
vk_check(vk.CreateDebugUtilsMessengerEXT(instance , &messenger_info , nil , &messenger) , "creating debug messenger") 

report_info := vk.DebugReportCallbackCreateInfoExt{ 
 
