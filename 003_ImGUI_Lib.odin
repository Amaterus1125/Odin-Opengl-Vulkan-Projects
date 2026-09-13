package main 

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

import "vendor:glfw"
import gl "vendor:OpenGL"
import mu "vendor:microui"

// in odin , for constants , do use Screaming style (all things are capital and stuff)

/* micro ui (using instead of imgui bc microui comes with odin support) is a tiny immediate mode GUI lib, meaning
instead of creating button/checkboxes objects once and keeping them around , we just draw a button for every frame 
and it figures out clicks, hovering and many more on the spot. hence no leftover GUI objects to manage 
in odin objects are kind of different bc odin is not OOP 

microui itself does not know how to draw anything on the screen , it only produces a list of instructions like draw a rectangle here 
or draw this text here , we take that list and turn it into actual opengl draw calls , this is what most of this file will do */ 

//now creating one point on our GUI sheet for -- where it is (pos) , which bit of the font/icon image to sample from (tex) , what color to tint it (col)

UI_Vertex :: struct {
   pos : [2]f32,
   tex: [2]f32,
   col: [4]u8,
}

//now creating everything out GUI system needs to remember between frames 
UI :: struct {
   ctx:  mu.Context,  //microui own internal state ( focus, layout , etc)
   program: u32,  // our 32 bit shader program for drawing gui shapes 
   vao , vbo , ebo : u32, // gpu buffers for the GUI shapes 
   atlas_text: u32,   //one image containing font and a few icons if needed 

/* now creating things for -- everyframe we collect ,all the little rectangles/text into these lists first ,
then send them to the gpu all at once (much faster then sending them one by one */
verts: [dynamic]UI_Vertex,
indices: [dynamic]u32,
}


ui : UI //one global instance to keep it simple 
