#pragma once

/* etc2comp_bridge.h
 Odin's foreign import can only call functions with a plain C ABI - it has
 no idea what a C++ class, template, or namespace is. Etc2Comp is written
 entirely in C++ (Etc::Image, Etc::File, etc.), so this header is the "seam"
 between the two languages: one flat `extern "C"` function that Odin can see,
 with all the C++ object juggling hidden away inside the .cpp file. */
#ifdef __cplusplus
extern "C" {
#endif

/* Loads `jpgPath` with stb_image, converts it to an ETC2 RGB8 compressed
 texture, and writes the result to `ktxPath` as a .ktx file.
 Returns 0 on success, non-zero on failure (e.g. the input image couldn't
 be opened or decoded). */
int etc2_convert_to_ktx(const char* jpgPath, const char* ktxPath);

#ifdef __cplusplus
}
#endif
