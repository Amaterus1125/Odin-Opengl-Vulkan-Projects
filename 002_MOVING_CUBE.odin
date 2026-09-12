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
