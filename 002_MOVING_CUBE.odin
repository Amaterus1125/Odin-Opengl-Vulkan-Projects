package main //as always keep the package name as this only 
import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:math/linalg"

/* the next will be just a box , to hold 2 things we send to the gpu every frame 
that is -- the matrix that moves/rotates/zooms our cube 
        -- a on/off switch (0 or 1) that says draw lines only or draw fileld 
*/
PerFrameData :: struct {
    mvp:     matrix[4.4]f32 , //where is the cube right now math is done by this 
    is_wireframe : i32 , }      // 0 = normal cube , 1 = outline only 

main :: proc() {

glfw.Init() 
defer glfw.Terminate() 

glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,4) //this example needs newer opengl version than the traingle_001 did 
glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR ,6)
glfw.WindowHint(glfw.OPENGL_PROFILE , glfw.OPENGL_CORE_PROFILE)

win := glfw.CreateWindow( 800, 800, "PRISON REALM" , nil,nil)
glfw.MakeContextCurrent(win)
gl.load_up_to(4,5,glfw.gl_set_proc_address)
gl.Enable(gl.DEPTH_TEST) // this will make sure that front of the cube covers the back (without this faces can be drawn in wrong rder and may look bad 

/* Now we create the shader that decides where each corner of the cube goes to , unlike the traingle we don't need to send corner positions from our code this time
  instead all 8 corners and colors are just typed directly inside theshader text */

vertex_src := `#version 460 core 
//this is the small setting box which gpu can read from , we fill it in from our code every frame 

layout(std140 , binding =0) uniform PerFrameData {
    uniform mat4 MVP;
    uniform int isWireFrame;
};
layout (location =0) out vec3 color;

//the 8 corner points of the cube 
const vec3 pos[8] = vec3[8](
    vec3(-1.0,-1.0,1.0) , vec3(1.0,-1.0,1.0) , vec3(1.0 , 1.0,1.0) , vec3(-1.0,1.0,1.0),
    vec3(-1.0,-1.0 , -1.0) , vec3(1.0,-1.0,1.0) , vec3(1.0 , 1.0 , -1.0) , vec3(-1.0 , 1.0 , -1.0)
);

//one color for each 8 corners -- gold color hehe
const vec3 col[8] = vec3[8](
	vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0),
	vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0), vec3(1.0, 0.84, 0.0)
);

//a cube has 6 flat faces , each face is made of 2 triangle , so 12 triangles total.
//this list just says "which 3 corners make each triangle" 
const int indices[36] = int[36](
   0,1,2, 2,3,0, //front face 
   1,5,6 , 6,2,1, //right face
  7,6,5,  5,4,7, //back face 
   4,0,3 , 3,7,4,  //bottom face
  3,2,6 , 6,7,3  //top face 
);

void main() {
  //the gpu calls this function once per corner it needs to draw 
 // gl_VertexID just tells us "which corner no. am i on right now from 0 to 35
int idx = indices[gl_VertexID];
//move this corner using our matrix ( this is what makesthe cube rotate and move on the screen) 
gl_Position = MVP * vec4(pos[idx],1.0);
// if we are in outline mode , just make everything black ,other wise use the normal color
color = isWireFrame > 0 ? vec3(0.0) : col[idx];

//this shader just colors in each pixel using whatever color came from above 
frag_src := `#version 460 core 
layout (location =0) in vec3 color;
layout (location=0) out vec4 out_FragColor;

void main() {
  out_FragColor = vec4(color , 1.0);
}`

vs := gl.CreateShader(gl.VERTEX_SHADER)
src1 := cstring(raw_data(vertex_src))
gl.ShaderSource(vs, 1, &src1 , nil)
gl.CompileShader(vs)

fs := gl.CreateShader(gl.FRAGMENT_SHADER)
src2 := cstring(raw_data(frag_src))
gl.ShaderSource(fs,1,&src2 , nil)
gl.CompileShader(fs)

program := gl.CreateProgram()
gl.AttachShader(program , vs)
gl.AttachShader(program , fs)
gl.LinkProgram(program)
gl.DeleteShader(vs)
gl.DeleteShader(fs)

//opengl still wants some vao active before drawing , even though we are not sending any vertex data from our code this time 

vao: u32 
gl.GenVertexArrays(1,&vao)
gl.BindVertexArray(vao)

// making the setting box buffer , holds our matrix , on/off switch
buf_size := size_of(PerFrameData)
per_frame_buf: u32
gl.CreateBuffers(1 , &per_frame_buf)    // create it 
hl.NamedBufferStorage(per_frame_buf , buf_size , nil , gl.DYNAMIC_STORAGE_BIT)   // set aside space for it on the gpu (empty for now)
gl.BindBufferRange(gl.UNIFORM_BUFFER, 0,per_frame_buf , 0 , buf_size) //connect it to shader setting box ( binding =0 )

for !glfw.WindowShouldClose(win) {
     width , height := glfw.GetFramebufferSize(win)
     gl.Viewport(0,0,width , height)
     gl.ClearColoe(0.1,0.1,0.1,1.0)
     gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT) // wipe both the pictures and the depth info from last frame

   // next lines will be work out where the cube should be of this frame 
   // p = makes far away things look smaller , like a real camera 
   // m = moves the cube back a bit and spins it based on how much time has passed 

aspect := f32(width) / f32(height)
p := linalg.matrix4_perspective_f32(linalg.to_radians(f32(60.0)), aspect, 0.1, 100.0)
translate := linalg.matrix4_translate_f32({0.0,0.0,-3.5)}  // push the cube back so we can see it 
rotate := linalg.matrix4_rotate_f32(f32(glfw.GetTime()), {1.0,1.0,1.0}) //spin it over timeee
m := translate * rotate

mvp := p*m //combine camera view and cube position into one final matrix
gl.UseProgram(program)

// draw 1 = the solid , filled in cube 
frame_data := PerFrameData{mvp = mvp , is_wireframe =0}
gl.NamedBufferSubData(per_frame_buf,0,buf_size , &frame_data) // send this frame info to the gpu 
gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL) //draw normal solid triangles 
gl.DrawArrays(gl.TRIANGLES , 0,36) //36 corners = 12 triangle = the full cube 

//draw 2 = draw the same cube normal , but back as a outline on top 
frame_data.is_wireframe = 1 
gl.NamedBufferSubData(per_frame_buf, 0, buf_size, &frame_data) // update the switch to "outline mode"
gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE) // this time only draw the edges, not the fill
gl.DrawArrays(gl.TRIANGLES, 0, 36)         // same cube, drawn as lines this time

glfw.SwapBuffers(win) //show what we just drew 
glfw.PollEvents() // check if user closed the window etc 

}
gl.DeleteBuffers(1 , &per_frame_buf)  // the cleanup
gl.DeleteVertexArrays(1, &vao)
gl.Deleterogram(program)
}


