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


//PART 1 - BITMAP HELPERS 
/* a simple in memory image , width ,height and depth and how many color channels per pixel (3 = RGB) , we only deal with floating point color channels here as HDR images store much brightness and darker range than a normal 0-255 range image  */

Bitmap :: struct { 
   w,h,d , comp: int ,
   pixels : []f32, 
}

make_bitmap :: proc(w,h,d,comp:int) -> Bitmap{
   return Bitmap(w,h,d,comp,make([]f32 , w*h*d*comp)}
}

get_pixel :: proc(b: ^Bitmap,x,y:int)  -> [4]f32 { 
    ofs := b.comp * (y*b.w +x)
    c: [4]f32 
    for k in 0 ..<min(b.comp ,4) {
   c[k] = b.pixels[ofs + k ]
}
return c 
}

set_pixel :: proc(b:^Bitmap , x,y:int , c :[4]f32) { 
   ofs := b.comp * (y*b.w+ x) 
   for k in 0 ..<b.comp {  
      b.pixels[ofs+k] = c[k] 
}
}

/* now given the pixel position (i,j) on one face of a cube (faceID - 0 to 5 , each face facesize x facesize) , returns a 3d direction that pixel points toward if the cube is 
centered around the origin, each 'if' below is just one face of the cube( a fixed X,Y,Z) with the other 2 coordinates sliding from -1 to 1 across that face */

face-coords_to_xyz :: proc(i,j , face_id , face_size : int) -> [3]f32 { 
 a := 2.0 *f32(i) /f32(face_size) 
 b := 2.0 *f32(j) /f32(face_size)
switch face_id { 
case 0: return {-1.0, a - 1.0, b - 1.0}
case 1: return {a - 1.0, -1.0, 1.0 - b}
case 2: return {1.0, a - 1.0, 1.0 - b}
case 3: return {1.0 - a, 1.0, 1.0 - b}
case 4: return {b - 1.0, a - 1.0, 1.0}
case 5: return {1.0 - b, a - 1.0, -1.0}
}
return {} 
} 

/* takes a flat quirectangular photo and re arranges it into a vertical cross layout , like those unfolded dice brain excersizes , cubr faces are arranged in a cross/plus shape 
, its a convinient layout before we split it into 6 seperate face images in the enxt step */

convert_eqirect_to_vertical_cross :: proc(n:^Bitmap) -> Bitmap { 
 face_size := b.w /4 
 w := face_size *3 
 h := face_size *4 
 result := make_bitmap(w,h,1,3) 

//where each of the faces sits within the cross shaped layout 
face_offsets := [6][2]int {
 {face_size , face_size *3} ,
 {0 , face_size} , 
 { face_size , face_size} ,
{face_size *2 , face_size} ,
{ face_size , face_size *2} ,
}

clamp_w := b.w -1
clamp_h := b.h -1 

for face in 0 ..< 6 { 
   for i in 0 ..< face size { 
      for j in 0 ..< face_size { 
      p := face_coords_to_xyz( i , j , face, face_size) 
// convert this 3d direction ( thetha , phi) to langitude and latitude 
 r := amth.sqrt( p.x *p.x + p.y * p.y) 
 thetha := math.atan2(p.y , p.x) 
 phi := math.atan2(p.z,r)

//turning those angles into an actual u,v pixel position inside the original flat equirectangular photo 
 uf := 2.0 * f32(face_size) * (theta + math.PI) .math.PI 
 vf := 2.0 * f32(face_size) * (math.PI / 2.0 - phi) / math.PI

/* BILINEAR INTERPOLATION - uf/vf usually land between 4 real pixels , not exactly one , so we grab all 4 pixels (u1,v1) to (u2,v2) and blend them based on how close we are to each other 
, s and t are how far ( 0.0 to 1.0) we are between them on each axis */

u1 := clamp( int(math.floor(uf)) , 0 , clamp_w) 
v1 := clamp(int(math.floor(vf)) , 0 , clamp_h) 
u2 := clamp(u1 +1 , 0 , clamp_w) 
v2 := clamp(v1 + 1 , 0 , clamp_h) 
s := uf - f32(u1) 
t := vf - f32(v1) 

ca := get_pixel(b , u1, v1) 
cb := get_pixel(b, u2, v1)
cc := get_pixel(b, u1, v2)
cd := get_pixel(b, u2, v2)

// writing the actual weighted blend , closer corners count more 
 color : [4]f32 
 for k in 0 ..<4 { 
 color[k] = 
 ca[k] * (1 - s) * (1 - t) +
cb[k] * s * (1 - t) +
cc[k] * (1 - s) * t +
cd[k] * s * t
}
set_pixel(&result , i + face_offsets[face].x , j + face_offsets[face].y , color ) 
} 
}
} 
return result 
} 

// the full pipeline - load an HDR photo from disk , convert to vertical cross , split into 6 faces and upload as an opengl cubemap texture 

load_cubemap :: proc(hdr_path : string) -> u32{ 
 w , h, comp: i32 
path_c := fmt.ctprintf("%s", hdr_path)
raw := stb1.loadf(path_c , &w , &h , &comp , 3) 
if raw == nil { 
  fmt.println("failed to load the hdr file: " , hdr_path) 
 return 0 
} 
defer stbi.image_free(raw) 
// copying the loaded pixels into on our own bitmap so we can work with them 
in_bitmap := make_bitmap( int(w) , int(h) , 1,3) 
pixel := int(w) * int(h) *3
raw_slice := raw[:pixel_count] 
copy(in_bitmap.pixels , raw_slice) 

cross := convert_equirect_to_vertical_cross(&in_bitmap)
	defer delete(cross.pixels)

//optional if you want to peek at the cross-layout image for debugging or seeing it 
os.make_directory("data/out")
	stbi.write_hdr("data/out/screen.hdr", i32(cross.w), i32(cross.h), i32(cross.comp), raw_data(cross.pixels))

	cm := convert_vertical_cross_to_cube_faces(&cross)
	defer delete(cm.pixels)

	tex: u32
	gl.CreateTextures(gl.TEXTURE_CUBE_MAP, 1, &tex)
	gl.TextureParameteri(tex, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(tex, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(tex, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(tex, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TextureParameteri(tex, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TextureStorage2D(tex, 1, gl.RGB32F, i32(cm.w), i32(cm.h))

	face_pixel_count := cm.w * cm.h * cm.comp
	for i in 0 ..< 6 {
		face_data := cm.pixels[i * face_pixel_count:(i + 1) * face_pixel_count]
		gl.TextureSubImage3D(tex, 0, 0, 0, i32(i), i32(cm.w), i32(cm.h), 1, gl.RGB, gl.FLOAT, raw_data(face_data))
	}

	return tex
}


// PART -2 SHADERS 

PerFrameData :: sturct { 
  model :  matrix[4, 4]f32,
  mvp : matrix[4 , 4] f32,
  camera_pos : [4]f32 ,
} 







 















