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


// PART 1 - NOW CREATING THE VULKAN INSTANCE DEVICE 
/* the instance os our program's actual connection to vulkan itself, nothing gpu specific happnes yet, this is just telling vulkan that we exist */
create_instance :: proc() -> vk.Instance { 

/*validation layers are vulkan built in mistake checkers, they catch things like if we forgot to onitialize something or if we are using object in the wrong state and prints a clear error instead of our program crashing or rendering garbage 
and it is very useful while learning and normally turned odd in a shipped game for extra performance */

layers := cstring{"VK_LAYER_KHRONOS_validation"}

/*now asking glfw which extensions this system needs to be able to show vulkan output in window at all, easier way and way better than per-os extension list entirely 
glfw_extensions := glfw.GetRequiredInstanceExtensions() 

//now on top of glfw list , we add 2 extensions for the valaidation layer's debug output to actually reach us 

extensions := make([dynamic]cstring) 
defer delete(extensions) 
append(&extensions , ..glfw_extensions) 
append(&extensions , vk.EXT_DEBUG_UTILS_EXTENSION_NAME) 
append(&extensions , vk.EXT_DEBUG_REPORT_EXTENSION_NAME) 

app_info := vk.ApplicationInfo{
 sType   = .APPLICATION_INFO,
pApplicationName = "VULKAN",
applicationVersion = vk.MAKE_VERSION(1,0,0),
pEngineName = "No Engine",
engineVersion = vk.MAKE_VERSION(1,0,0) 
apiVersion = vk.API_VERSION_1_1,
}

create_info := vk.InstanceCreateInfo{
sType = .INSTANCE_CREATE_INFO ,
pApplicationInfo = &app_info , 
enabledLayerCount = u32(len(layers)),
ppEnabledLayerNames = raw_data(layers),
enabledExtensionCount = u32(len(extensions)),
ppEnabledExtensionNames = raw_data(extensions) ,
}

instance : vk.Instance 



