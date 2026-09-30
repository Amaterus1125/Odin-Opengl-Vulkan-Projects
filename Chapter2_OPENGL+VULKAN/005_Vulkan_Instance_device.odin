//SOME BASIC IMPORTS for the vulkan instance

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

/*now asking glfw which extensions this system needs to be able to show vulkan output in window at all, easier way and way better than per-os extension list entirely */
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
result := vk.CreateInstance(&create_info , nil , &instance)
vk_check(result , "CREATING AN INSTANCE")

/* now that the instance exists, load every other vulkan function through it, just using odin own vendor:vulkan */
vk.load_proc_addresses(instance) 
return instance 
}

//PART -2 FINDING THE GPU TO USE 
/* walks through every gpu in the system and returns the first one that makes selector return true , selector is a function which we provide by decribing abt what we are looking for */
find_suitable_physical_device :: proc( instance : vk.instance , selector : proc(device: vk.PhysicalDevice) -> bool , } -> (vk.PhysicalDevice , bool) {
device_count : u32
vk.EnumeratePhysicalDevies(instance , &device_count , raw_data(devices)) 

for device in devices { 
if selector(device) { 
return device , true 
} } 
return {} , false 
} 

/* now look at a gpu queue families (group of things that gpu can do at once) and returns the index of the first one supporting the capability we asked for */

find_queue_families :: proc(device: vk.PhysicalDevice , desired_flags: vk.QueueFlags) -> u32 { 
family_count : u32 
vk.GetPhysicalDeviceQueueFamilyProperties(device , &family_count , nil) 
families := make([]vk.QueueFamilyProperties , family_count) 
defer delete(families) 
vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))
for family , i in families { 
 if family.queueCount > 0 && (family.queueFlags & desired_flags == desired_flags) {
 return u32(i)
} } 
return 0 
} 

// PART 3 - CREATING THE LOGICAL DEVICCE  
/* the physical device is just a description of a gpu that exists , the logical device is our actual usbale handle for talking to it , this si the object we will have to pass to almost every other vulkan func from here on */

create-device :: proc ( 
physical_device : vk.PhysicalDevice .
device_features : vk.PhysicalDeviceFeatures ,
graphics_family : u32 , ) -> (vk.Device , vk.Result) { 
//our device needs to support presenting images to a window that capability comes from this one extension 
extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	queue_priority: f32 = 1.0
	queue_info := vk.DeviceQueueCreateInfo{
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = graphics_family,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}



