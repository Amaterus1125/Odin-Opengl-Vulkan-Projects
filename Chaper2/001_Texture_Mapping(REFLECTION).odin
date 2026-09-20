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
/*  DOING 2 UNRELATED THINGS THAT WILL COME TOGETHER AT THE END 
PART 1 - Turn a flat 360 degree photo into a cubemap (a skybox) ---
so from a 360 degree camera we get a equirectangular image , one flat rectangle where the left/right edges wrap around like a globe unrolled flat (like a world map)
and we want to turn that into a cubemap instead , 6 square images , one for each face of the cube , so we can wrap it around the scene like a box.
To do this for every pixel on each of the 6 cube faces , which direction does it point? and where on the original flat photo does that SAME direction appear?" That's `faceCoordsToXYZ` (gives us the 3D direction) combined
with converting that direction into (theta, phi) , longitude and latitude, basically, exactly like coordinates on a globe , using `atan2`. Those longitude/latitude values are then just proportional
positions in the flat photo. We grab the color from there and copy it onto the cube face. Do this for all 6 faces and you've converted formats. */

/* Since the calculated position often lands BETWEEN 4 actual pixels (not exactly on one), we blend those 4 neighboring pixels together based on how close we are to each and this is called BILINEAR INTERPOLATION, 
and it's just a weighted average using how far we are from each neighbor. */

// PART 2 - MAKEING THE FIGURE LOOK REFLECTIVE AND REFRACTIVE 
/* in the fragment shader , for each pixel of the duck we calculate 2 rays, The reflection ray and The refractive ray ,by sampling the cubemap sky in both of those directions , then blend them together, how much we 
blend towards reflection vs refraction depends on viewing angle , this is a real physical effect known as FRENSEL EFFECT, We approximate the real physics using "Schlick's approximation", a well-known formula that's cheap
to compute and looks convincingly close to correct. */

