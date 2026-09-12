package main 
import "vendor:glfw"
import gl "vendor:OpenGL"
main :: proc(){
   glfw.Init()     //for start upsfor windows and input lib 
   defer glfw.Terminate()
//telling glfw we want an OPENGL 3.3 core profile context 
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR ,3)
  glfw.WindowHind(glfw.CONTEXT_VERSION_MINOR ,3)
  glfw.WindowHint(glfw.OPENGL_PROFILE , glfw.OPENGL_CORE_PROFILE)

win := glfw.CreateWindow(800 , 800 , "TRIANGLE LORD" ,nil,nil) //creating the window
glfw.MakeContextCurrent(win)  // make this window context active 
gl.load_up_to(3,3,glfw.gl_set_proc_address) //load opengl 3.3 functions 

// making vertices -- 
//each vertex has position (x,y,z) and color (r,g,b) packed together 
//layout per vertex : x,y,z andd r,g,b
vertices :=[18]f32{
    0.0 , 0.5, 0.0 ,    1.0 , 0.0 , 0.0 , //top vertex with some color 
  -0.5 , -0.5 , 0.0 ,   0.0 , 1.0 , 0.0 , //bottom left - any color , basically yr screen is between 1 , 0 , -1 
   -0.5 , -0.5 , 0.0 ,  0.0 , 0.0 , 1.0 ,  //bottom right with any color 
}

vao , vbo: u32 
gl.GenVertexArrays(1,&vao)   // vao (vertex array object) is for how to read vbo data , its a kind of recipe 
gl.GenBuffers(1, &vbo)   //vbo (vertex buffer object) is raw buffer of vertex numbers on the gpu 
gl.BindVertexArray(vao)  //start recording into this vao 
gl.BindBuffer(gl.ARRAY_BUFFER ,vbo) // this vbo is now the active array buffer 
gl.BufferData(gl.ARRAY_BUFFER , size_of(vertices) , &vertices , gl.STATIC_DRAW) // upload vertex data to the gpu 

