// IMPORTANT IMPORT FILES FOR VULKAN AND ODIN 



/* 
Compile the 2 shaders into .spv binaries — do this from inside that folder you have put both the fiels in and run this in the terminal (I am using Arch for this):
glslangValidator -V VK01.vert -o VK01.vert.spv
glslangValidator -V VK01.frag -o VK01.frag.spv

*/



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

main :: proc() { 
// glfw is not drawing anything here , we only use it to hand vulkan on how do i find vulkan functions on this system type of thing 
glfw.Init()
defer glfw.Terminate()
vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

//STEP 1 - create a VULKAN INSTANCE (the app connection to the driver) 

app_info := vk.ApplicationInfo{
sType = .APPLICATION_INFO,
pApplicationName = "vulkan shader test the odin way",
apiVersion = vk.API_VERSION_1_1,
}
instance_info := vk.InstanceCreateInfo { 
 sType = .INSTANCE_CREATE_INFO,
 pApplicationInfo = &app_info,
} 
instance : vk.Instance 
if vk.CreateInstance(&instance_info , nil , &instance) != .SUCCESS { 
fmt.println("failed to create vulkan instance")
return
}
defer vk.DestroyInstance(instance, nil)
vk.load_proc_addresses(instance) // now that we have an instance, load the rest

//STEP 2 - picking a physical GPU 
device_count: u32
vk.EnumeratePhysicalDevices(instance , &device_count , nil)
if device_count == 0 {
fmt.println("no vulkan-capable gpu found")
return
}

physical_devices := make([]vk.PhysicalDevice , device_count)
defer delete(physical_devices) 
vk.EnumeratePhysicalDevices(instance , &device_count , raw_data(physical_devices))
physical_device := physical_devices[0] //just grab the first gpu found , good enough for this test 

// STEP 3 - create a logical device ( our actual handle for talking to that gpu) 
queue_priority : f32 = 1.0 
queue_info := vk.DeviceQueueCreateInfo{
 sType = .DEVICE_QUEUE_CREATE_INFO, 
queuwFamilyIndex = 0 ,              // for simplification assuming that queue family 0 supports what we need , fine for this test 
queueCount = 1 ,
pQueuePriorities = &queue_info , 
}
device_info := vk.DeviceCreateInfo{
 sType = .DEVICE_CREATE_INFO,
queueCreateInfoCount = 1 , 
pQueueCreateInfos = &queue_info , 
} 

device : vk.Device 
if vk.CreateDevice(physical_device , &device_info , nil , &device) != .SUCCESS { 
fmt.println("failed to create logical device")
return
}
defer vk.DestroyDevice(device, nil)
vk.load_proc_addresses(device) // load device-specific functions now that we have a device

// STEP 4 - the actual part for loading shaders - basically create them and then destroy them isntantaneously , like we have been doing way before 
vertex_module := create_shader_module(device, "VK01.vert.spv")
defer vk.DestroyShaderModule(device, vertex_module, nil)

fragment_module := create_shader_module(device, "VK01.frag.spv")
defer vk.DestroyShaderModule(device, fragment_module, nil)

if vertex_module != 0 && fragment_module != 0 {
fmt.println("both shader modules loaded successfully!")
}
}


