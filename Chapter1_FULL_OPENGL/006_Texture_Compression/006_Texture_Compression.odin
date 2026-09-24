// TEXTURE COMPRESSION IN ODIN - 

/* Why we compress a texture at all - 
    A single 2048x2048 RGBA8 texture eats 2048*2048*4 = 16 MB of VRAM, raw.
    A real app has hundreds of textures like that - GPU memory runs out fast,
    and just streaming that many bytes off disk is slow too.
    GPU can do that all by support of a block compressed formats , they can directly use in hardware 

ETC2 (Ericsson Texture Compression 2) is one of the formats , its the mandatory compressed format in opengl 
and is also supported by vulkan, the trick is that every 4x4 tile of pixels gets squeezed into a fixed no. of bytes
    RGB8 block - 8 bytes per 4x4 tile - 4 bits per pixel 
    RGBA8 block - 16 bytes per 4x4 tile - 8 bits per pixel 

Inside each block , the encoder does not store raw colors , it stores one base color (or two, split diagonally or vertically) plus a per pixel index into 
a small fixed table of brigtness offset , The GPU reconstructs the final color per pixel in hardware at sample time.
ETC2 selects the best base color , best table and best per pixel index for every single block for us.

WHY DO WE HAVE A CPP FILE IN AN ODIN PROJECT - 
There's no Odin vendor library for ETC2 encoding. Writing a spec-conformant
encoder from scratch is real, nontrivial work (it's the whole reason, Google shipped Etc2Comp as its own project) - and a half-correct hand-rolled
version would silently produce textures that sample wrong on real hardware, So instead of reimplementing that math, we do what you'd do for any
C/C++-only library without existing bindings: write a *thin* C wrapper, around it, and call that wrapper from Odin with `foreign import`. Odin is
the orchestrator; the C++ side does the actual block-compression work.

See etc2comp_bridge.h / etc2comp_bridge.cpp - that's where the load -> float-convert -> encode -> write pipeline from the book actually lives,
with matching theory comments on each step (gamma, the error metric, etc).

ONE-TIME BUILD STEPS (before odin run will work) - 
1. Fetch the two dependencies, same as the book's Bootstrap snippet:
        git clone https://github.com/google/etc2comp
        (stb_image.h - single header, drop it in your include path)

   2. Compile Etc2Comp's core sources + the two extra .cpp files the book
      calls out (EtcFile.cpp, EtcFileHeader.cpp) + etc2comp_bridge.cpp into
      one static library, e.g. on Linux/macOS:

        g++ -std=c++17 -c etc2comp_bridge.cpp \
            -I. -Ietc2comp/EtcLib -Ietc2comp/EtcTool -o bridge.o
        ar rcs libetc2bridge.a bridge.o \
            etc2comp/EtcTool/EtcFile.o etc2comp/EtcTool/EtcFileHeader.o \
            <the rest of Etc2Comp's compiled .o files>

3. Point the foreign import line below at wherever that .a/.lib/.so
  ends up, and make sure it's on your linker's search path.
*/

import "core:fmt"
import "core:os"

//THE below decleration has to match etc2comp_bridge.h exactly  -  same argument types ,same calling convention , bc there are no type checking across an FFI boundry

foreign import bridge "libetc2bridge.a" //swap with whatever u built in step 2/3 above 
//loads the jpeg path via stb_image and converts into ETC2 RGB8 and writes a ktx file into ktxpath , returns 0 on success
foreign bridge {
   etc2_convert_to_ktx :: proc(jpgPath : cstring, ktxPath:cstring) -> i32 --- 
}

main :: proc() {
   input : cstring = "filename"
   output : cstring = 'image.ktx"
fmt.printfln("Encoding %s -> %s (ETC2 RGB8, BT.709 error metric)...", input, output)
result := etc2_convert_to_ktx(input, output)
if result == 0 {
		fmt.println("Done - image.ktx can be loaded straight into an OpenGL or Vulkan texture object.")
	} else {
		fmt.eprintln("Encoding failed - check that the input image exists and stb_image can read it.")
		os.exit(1)
	}
}

  
