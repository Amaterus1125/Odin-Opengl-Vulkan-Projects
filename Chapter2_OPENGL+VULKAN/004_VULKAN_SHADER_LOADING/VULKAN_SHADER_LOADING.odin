// IMPORTANT IMPORT FILES FOR VULKAN AND ODIN 

package main

import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"

// WHY IS THIS FILE DIFFERENT - 
/* OpenGL hides a LOT of setup from you -- glfw.MakeContextCurrent() secretly does most of the "talk to the GPU" plumbing in one call. Vulkan hides NOTHING. Before you can do anything at all 
even just load a shader you must manually create an "instance" (the app's connection to the vulkan driver) and a "device" (your actual GPU, selected and set up by hand). That's what most of this file's main() is doing before it ever gets to the shader-loading part you actually asked about. */ 

This demo doesn't open a window or draw anything, same as the book's own version of this recipe, which is a plain console program
that loads 2 shaders and prints whether it worked. A full window + rendering setup is a separate, bigger recipe (say the word if you want that built next).

create_shader_module :: proc(device: vk.Device , spv_path: string) -> vk.ShaderModule { 
code , err := os.read_entire_file_from_path(spv_path , context.allocator) 
if err != nil { 
   fmt.println("failed to read the spir-v file:" , spv_path , err) 
   return 0 
} 
defer delete(code) 

create_info := vk.ShaderModuleCreateTnfo { 
 sType = .SHADER_MODULE_CREATE_INFO,
 codeSize len(code), 
 pCode = cast(^u32)raw_data(code) ,
} 

shader_module : vk.ShaderModule
result := vk.CreateShaderModule(device , &create_info, nil , &shader_module)
if result != .SUCCESS {
		fmt.println("failed to create shader module:", result)
		return 0
	}
return shader_module
}


