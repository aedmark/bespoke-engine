/* The SDL2 headers the desktop display uses. Zig 0.17 removed `@cImport`, so build.zig
 * translates this header into the `sdl` module (P37-01). */
#include <SDL2/SDL.h>
