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
import "base:runtime"

//EDIT THESE 3 PATHS TO POINT AT YOUR OWN FILES BEFORE RUNNING - 
HDR_PATH   :: "street.hdr"   //an equirectangle 360 degree hdr photo , common enviornmental maps we can find online easily
DUCK_GLTF_PATH :: "avocado_duck/scene.gltf"  // duck model or avocado model from earlier projects ( i will upload the duck model) 
DUCK_TEXTURE_PATH  :: "rubber_duck/DuckCM.png"  // the duck color texture 






// free moving camera to move around , use WASD to move and mouse to look 

camera_pos   := [3]f32{0, 0, 3}    // where the camera IS in the world
camera_front := [3]f32{0, 0, -1}   // which direction the camera is LOOKING
camera_up    := [3]f32{0, 1, 0}    // which way is "up" for the camera

camera_yaw:   f32 = -90.0 // left/right look angle, in degrees
camera_pitch: f32 = 0.0   // up/down look angle, in degrees

last_mouse_x, last_mouse_y: f32
first_mouse := true // avoids a big jump on the very first mouse movement

// glfw calls this automatically whenever the mouse moves. we turn that
// movement into a change in yaw/pitch, then rebuild the "front" direction
// vector from those two angles (this is standard "FPS camera" math)
mouse_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = runtime.default_context()

	if first_mouse {
		last_mouse_x = f32(xpos)
		last_mouse_y = f32(ypos)
		first_mouse = false
	}

	xoffset := (f32(xpos) - last_mouse_x) * 0.1 // 0.1 = mouse sensitivity, raise/lower to taste
	yoffset := (last_mouse_y - f32(ypos)) * 0.1 // reversed: screen y grows downward, we want up = positive
	last_mouse_x = f32(xpos)
	last_mouse_y = f32(ypos)

	camera_yaw += xoffset
	camera_pitch = clamp(camera_pitch + yoffset, -89.0, 89.0) // stops you from flipping upside down

	yaw_r := linalg.to_radians(camera_yaw)
	pitch_r := linalg.to_radians(camera_pitch)
	camera_front = linalg.normalize([3]f32{
		math.cos(yaw_r) * math.cos(pitch_r),
		math.sin(pitch_r),
		math.sin(yaw_r) * math.cos(pitch_r),
	})
}











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

/* draws the duck , this vertex shader just positions each vertex normally , and reads position/uv/normal out of a raw buffer of floats rather than the usual vertex 
attributes , same idea as microui font atlas , its a chunk og gpu memory we are interpretating ourselves by hand instead of letting opengl automatically decode it for us */


duck_vertex_src := `#version 460 core 
layout(std140 , binding = 0) out PerVertex vtx; 
     mat4 model ; 
     mat4 MVP ; 
    vec4 cameraPos; 
}; 
struct PerVertex { vec2 uv; vec3 normal; vec3 worldPos; };
layout(location = 0) out PerVertex vtx;
layout(std430, binding = 1) restrict readonly buffer Vertices { float data[]; } in_Vertices;

vec3 getPosition(int i) { return vec3(in_Vertices.data[8*i+0], in_Vertices.data[8*i+1], in_Vertices.data[8*i+2]); }
vec2 getTexCoord(int i) { return vec2(in_Vertices.data[8*i+3], in_Vertices.data[8*i+4]); }
vec3 getNormal(int i)   { return vec3(in_Vertices.data[8*i+5], in_Vertices.data[8*i+6], in_Vertices.data[8*i+7]); }

void main() {
	vec3 pos = getPosition(gl_VertexID);
	gl_Position = MVP * vec4(pos, 1.0);
	mat3 normalMatrix = mat3(transpose(inverse(model)));
	vtx.uv = getTexCoord(gl_VertexID);
	vtx.normal = normalMatrix * getNormal(gl_VertexID);
	vtx.worldPos = (model * vec4(pos, 1.0)).xyz;
}`

//writing the reflection/refraction math actually happening
duck_fragment_src := `#version 460 core 
layout(std140, binding = 0) uniform PerFrameData {
	mat4 model;
	mat4 MVP;
	vec4 cameraPos;
};
struct PerVertex { vec2 uv; vec3 normal; vec3 worldPos;};
layout(location=0) in PerVertex vtx;
layout(location=0) out vec4 out_FragColor;
layout(binding=0) uniform sampler2D texture0;    //the duck regular color texture 
layout(binding=0) uniform samplerCube texture1; //our cubemap sky , used for the shiny effect 

void main() { 
vec3 n = normalize(vtx.normal); //surface direction at this pixel 
vec3 v = normalize(cameraPos.xyz - vtx.worldPos); //our cubemap sky , used for shiny effect 
// mirror-bounce direction (reflection) and bent-through direction (refraction)
	vec3 reflection = -normalize(reflect(v, n));
    float eta = 1.00 / 1.31;                         // ratio of how much light bends roughly water/rubber-ish
	vec3 refraction = -normalize(refract(v, n, eta));
    
// SCHLICK'S APPROXIMATION (the Fresnel effect) - meaning the rate of reflection or refraction depends on which angle u looking from , happens in real life 
// R0 = how reflective the surface is when looking STRAIGHT AT it (angle = 0)
 const float R0 = ((1.0 - eta) * (1.0 - eta)) / ((1.0 + eta) * (1.0 + eta));
// as the viewing angle becomes more grazing/sideways, reflectivity rises toward 1.0 and that's what this pow(...) term is doing
const float Rtheta = R0 + (1.0 - R0) * pow((1.0 - dot(-v, n)), 5.0);

vec4 color = texture(texture0, vtx.uv);
vec4 colorRefl = texture(texture1, reflection);
vec4 colorRefr = texture(texture1, refraction);

// blend the reflection and refraction based on that angle dependent factor and then multiply by the duck;s own base color or texture 
color = color * mix(colorRefl, colorRefr, Rtheta);
out_FragColor = color;
}`

/*now writing the skybox itself , same as hardcore a cube corners directly in the shader trick from our earlier gradient cube example , just scaled way up (100x) so it 
surrounds the whole scene instead of a flat color it looks uo to the cubemap texture using its own position as direction  */

cube_vertex_src := `#version 460 core 
layout(std140, binding = 0) uniform PerFrameData {
	mat4 model;
	mat4 MVP;
	vec4 cameraPos;
};
layout(location = 0) out vec3 dir;
const vec3 pos[8] = vec3[8](
vec3(-1,-1, 1), vec3( 1,-1, 1), vec3( 1, 1, 1), vec3(-1, 1, 1),
vec3(-1,-1,-1), vec3( 1,-1,-1), vec3( 1, 1,-1), vec3(-1, 1,-1));
const int indices[36] = int[36](                                         //36 points to make the cubemap skybox itself with hardcore cube corners 
0,1,2, 2,3,0,  1,5,6, 6,2,1,  7,6,5, 5,4,7,
4,0,3, 3,7,4,  4,5,1, 1,0,4,  3,2,6, 6,7,3);
void main() {
	int idx = indices[gl_VertexID];
	gl_Position = MVP * vec4(100.0 * pos[idx], 1.0);
	dir = pos[idx];
}`

//writing the cube fragment now , with location =0 , and binding =1 and giving it the texture we want it to have 
cube_fragment_src := `#version 460 core
layout(location = 0) in vec3 dir;
layout(location = 0) out vec4 out_FragColor;
layout(binding = 1) uniform samplerCube texture1;
void main() { out_FragColor = texture(texture1, dir); }`



make_program :: proc(vs_src , fs_src:string) -> u32 { 
  compile :: proc*shader_type :u32 , src:string) -> u32 { 
  s := gl.CreateShader(shader_type)
  c_src := cstring(raw_data(src)) 
  gl.ShaderSource(s,1,&c_src , nil)
 gl.CompileShader(s) 
 ok : i32 
 if ok ==0 { 
 log : [4096]u8 
 gl.GetShaderInfoLog(s, 4096, nil, raw_data(log[:]))
fmt.println("shader error:", string(log[:]))
}
return s
}
// the final part - about linking the program and attaching both vertex and fragment shaders
p := gl.CreateProgram()
	gl.AttachShader(p, compile(gl.VERTEX_SHADER, vs_src))
	gl.AttachShader(p, compile(gl.FRAGMENT_SHADER, fs_src))
	gl.LinkProgram(p)
    ok: i32
	gl.GetProgramiv(p, gl.LINK_STATUS, &ok)
	if ok == 0 {
    log :[4096]u8 
    gl.GetProgramInfoLog(p, 4096, nil, raw_data(log[:]))
		fmt.println("link error:", string(log[:]))
	}
	return p
}


// THE ENTIRE MAIN PART FOR THE CODE EXECUTION AND ALL THE WINDOW STUFF and creating VBO , VA0 , EBO 

main ::proc() { 
 glfw.Init() 
 defer glfw.Terminate() 
 glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    window := glfw.CreateWindow(1280, 720, "reflecting duck", nil, nil)
	glfw.MakeContextCurrent(window)
	gl.load_up_to(4, 6, glfw.gl_set_proc_address)
	glfw.SwapInterval(1)

 
  




















