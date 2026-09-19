//THE COMMON IMPORTS BEFORE RUNNING THIS HUGE FILE 
package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"

import "vendor:glfw"
import gl "vendor:OpenGL"
import cgltf "vendor:cgltf"
import stbi "vendor:stb/image"

//EDIT THESE 3 PATHS TO POINT AT YOUR OWN FILES BEFORE RUNNING - 
HDR_PATH   :: "street.hdr"   //an equirectangle 360 degree hdr photo , common enviornmental maps we can find online easily
DUCK_GLTF_PATH :: "avocado_duck/scene.gltf"  // duck model or avocado model from earlier projects ( i will upload the duck model) 
DUCK_TEXTURE_PATH  :: "rubber_duck/DuckCM.png"  // the duck color texture 

// ALL THE THINGS WE GOING TO DO - 
/*  
