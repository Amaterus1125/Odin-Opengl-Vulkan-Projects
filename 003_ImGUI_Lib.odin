package main 

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

import "vendor:glfw"
import gl "vendor:OpenGL"
import mu "vendor:microui"

/* micro ui (using instead of imgui bc microui comes with odin support) is a tiny immediate mode GUI lib, meaning
instead of creating button/checkboxes objects once and keeping them around , we just draw a button for every frame 
and it figures out clicks, hovering and many more on the spot. hence no leftover GUI objects to manage 
in odin objects are kind of different bc odin is not OOP 

microui itself does not know how to draw anything on the screen , it only produces a list of instructions like draw a rectangle here 
or draw this text here , we take that list and turn it into actual opengl draw calls , this is what most of this file will do */ 


