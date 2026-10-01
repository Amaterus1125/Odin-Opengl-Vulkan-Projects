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
 app_info := vk.ApplicationInfo{
sType              = .APPLICATION_INFO,
pApplicationName   = "Vulkan",
applicationVersion = vk.MAKE_VERSION(1, 0, 0),
pEngineName        = "No Engine",
engineVersion      = vk.MAKE_VERSION(1, 0, 0),
apiVersion         = vk.API_VERSION_1_1,
	}

create_info := vk.InstanceCreateInfo{
sType                   = .INSTANCE_CREATE_INFO,
pApplicationInfo        = &app_info,
enabledLayerCount       = u32(len(layers)),
ppEnabledLayerNames     = raw_data(layers),
enabledExtensionCount   = u32(len(extensions)),
ppEnabledExtensionNames = raw_data(extensions),
}

instance: vk.Instance
vk_check(vk.CreateInstance(&create_info, nil, &instance), "creating instance")
vk.load_proc_addresses(instance)
return instance
}


find_suitable_physical_device :: proc(
	instance: vk.Instance,
	selector: proc(device: vk.PhysicalDevice) -> bool,
) -> (vk.PhysicalDevice, bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		return {}, false
	}
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	for device in devices {
		if selector(device) {
			return device, true
		}
	}
	return {}, false
}

