//! Pixel art in the package (P46-01, D-151, D-152, D-153).
//!
//! A game carries one palette of up to 256 colours and any number of indexed images: sprite
//! sheets and backdrops. Every pixel is one byte, an index into the game palette, and index 0
//! is transparent whatever colour the palette stores there. Art is drawn at 320x180 and scaled
//! 4x to the 1280x720 frame (D-097), so a frame (one cell of a sheet, or a whole backdrop) is at
//! most 320x180. A sheet is a grid of equal frames read left to right, then top to bottom.
//!
//! Art is presentation data. It is never written to the World, never saved in `.sav`, and never
//! rewound, so it cannot change a replay (D-151). Names are plain text for the same reason:
//! interning them would add entities to the fact table that no rule can use.
//!
//! Every value here may come from a package file, which is untrusted input. `Art.validate` is the
//! one gate: the package loader and `Art.dupe` both pass through it, so a renderer can index a
//! sheet with `frame_pixel` and the palette with any stored index without checking again.
const std = @import("std");

/// The art resolution (D-152). A frame never exceeds it.
pub const ART_WIDTH: u16 = 320;
pub const ART_HEIGHT: u16 = 180;
/// Whole-number scale from art pixels to the 1280x720 frame (D-097, D-152).
pub const SCALE: u16 = 4;
/// One palette per game (D-152); one byte per pixel indexes all of it.
pub const MAX_COLOURS: usize = 256;
/// The palette index drawn as nothing.
pub const TRANSPARENT: u8 = 0;
/// Upper bounds a well-formed package never reaches (D-153). They keep a corrupt count or size
/// from asking for memory before the bytes behind it are read.
pub const MAX_IMAGES: usize = 1024;
pub const MAX_SHEET_SIDE: u16 = 2048;
pub const MAX_SHEET_PIXELS: usize = 1024 * 1024;
pub const MAX_NAME: usize = 64;

pub const Error = error{
    InvalidImagePalette,
    InvalidImageCount,
    InvalidImageName,
    InvalidImageSize,
    InvalidImageIndex,
};

pub const Colour = struct { r: u8, g: u8, b: u8 };

/// One indexed image. `pixels` holds `width * height` palette indices, row by row.
pub const Image = struct {
    name: []const u8,
    width: u16,
    height: u16,
    frame_width: u16,
    frame_height: u16,
    pixels: []const u8,

    pub fn columns(self: Image) u32 {
        return self.width / self.frame_width;
    }

    pub fn frame_count(self: Image) u32 {
        return self.columns() * (self.height / self.frame_height);
    }

    /// The palette index at (x, y) inside `frame`. The caller keeps x and y inside the frame
    /// and `frame` below `frame_count`; a validated image then never reads past `pixels`.
    pub fn frame_pixel(self: Image, frame: u32, x: u16, y: u16) u8 {
        std.debug.assert(frame < self.frame_count() and x < self.frame_width and y < self.frame_height);
        const left = (frame % self.columns()) * self.frame_width;
        const top = (frame / self.columns()) * self.frame_height;
        return self.pixels[(top + y) * @as(usize, self.width) + left + x];
    }

    /// Checks one image against a palette of `colour_count` colours. The order is the order a
    /// loader meets the fields in, so a package reports the first thing wrong with it.
    pub fn validate(self: Image, colour_count: usize) Error!void {
        try validate_name(self.name);
        try validate_size(self.width, self.height, self.frame_width, self.frame_height);
        if (self.pixels.len != @as(usize, self.width) * self.height) return Error.InvalidImageSize;
        try validate_indices(self.pixels, colour_count);
    }
};

/// Names are printable ASCII so a diagnostic or the inspector can show one from an untrusted
/// package without escaping it.
pub fn validate_name(name: []const u8) Error!void {
    if (name.len == 0 or name.len > MAX_NAME) return Error.InvalidImageName;
    for (name) |c| if (c < 0x20 or c > 0x7e) return Error.InvalidImageName;
}

/// A frame fits the art resolution and tiles the sheet exactly; the sheet stays inside the
/// side and pixel limits, so `width * height` bytes is a bounded read.
pub fn validate_size(width: u16, height: u16, frame_width: u16, frame_height: u16) Error!void {
    if (frame_width == 0 or frame_height == 0) return Error.InvalidImageSize;
    if (frame_width > ART_WIDTH or frame_height > ART_HEIGHT) return Error.InvalidImageSize;
    if (width == 0 or height == 0 or width > MAX_SHEET_SIDE or height > MAX_SHEET_SIDE) return Error.InvalidImageSize;
    if (@as(usize, width) * height > MAX_SHEET_PIXELS) return Error.InvalidImageSize;
    if (width % frame_width != 0 or height % frame_height != 0) return Error.InvalidImageSize;
}

/// Index 0 is transparent and needs no colour behind it to be drawn, but it is still an index
/// into the palette, so an image with any pixel at all needs a palette of at least one colour.
pub fn validate_indices(pixels: []const u8, colour_count: usize) Error!void {
    for (pixels) |index| if (index >= colour_count) return Error.InvalidImageIndex;
}

/// A game's palette and images. Empty for a game drawn by code.
pub const Art = struct {
    palette: []const Colour = &.{},
    images: []const Image = &.{},

    pub fn is_empty(self: Art) bool {
        return self.palette.len == 0 and self.images.len == 0;
    }

    pub fn find(self: *const Art, name: []const u8) ?*const Image {
        for (self.images) |*image| if (std.mem.eql(u8, image.name, name)) return image;
        return null;
    }

    pub fn validate(self: Art) Error!void {
        if (self.palette.len > MAX_COLOURS) return Error.InvalidImagePalette;
        if (self.images.len > MAX_IMAGES) return Error.InvalidImageCount;
        if (self.images.len > 0 and self.palette.len == 0) return Error.InvalidImagePalette;
        for (self.images, 0..) |image, i| {
            try image.validate(self.palette.len);
            for (self.images[0..i]) |prior| if (std.mem.eql(u8, prior.name, image.name)) return Error.InvalidImageName;
        }
    }

    /// Validates, then copies palette, names, and pixels into memory owned by `allocator`.
    pub fn dupe(allocator: std.mem.Allocator, palette: []const Colour, images: []const Image) (Error || std.mem.Allocator.Error)!Art {
        try (Art{ .palette = palette, .images = images }).validate();
        const own_palette = try allocator.dupe(Colour, palette);
        errdefer allocator.free(own_palette);
        const own_images = try allocator.alloc(Image, images.len);
        var done: usize = 0;
        errdefer {
            for (own_images[0..done]) |image| free_image(allocator, image);
            allocator.free(own_images);
        }
        for (images, own_images) |image, *copy| {
            const name = try allocator.dupe(u8, image.name);
            errdefer allocator.free(name);
            copy.* = image;
            copy.name = name;
            copy.pixels = try allocator.dupe(u8, image.pixels);
            done += 1;
        }
        return .{ .palette = own_palette, .images = own_images };
    }

    pub fn deinit_owned(self: *Art, allocator: std.mem.Allocator) void {
        for (self.images) |image| free_image(allocator, image);
        allocator.free(self.images);
        allocator.free(self.palette);
        self.* = .{};
    }
};

pub fn free_image(allocator: std.mem.Allocator, image: Image) void {
    allocator.free(image.name);
    allocator.free(image.pixels);
}

test "P46-01: a sheet's frames read left to right, then top to bottom" {
    // A 4x2 sheet of four 2x1 frames in two columns and two rows.
    const pixels = [_]u8{ 1, 1, 2, 2, 3, 3, 0, 1 };
    const sheet = Image{ .name = "Sheet", .width = 4, .height = 2, .frame_width = 2, .frame_height = 1, .pixels = &pixels };
    try sheet.validate(4);
    try std.testing.expectEqual(@as(u32, 4), sheet.frame_count());
    try std.testing.expectEqual(@as(u8, 2), sheet.frame_pixel(1, 0, 0));
    try std.testing.expectEqual(@as(u8, 3), sheet.frame_pixel(2, 1, 0));
    try std.testing.expectEqual(@as(u8, 1), sheet.frame_pixel(3, 1, 0));
}

test "P46-01: art validation names what is wrong" {
    const palette = [_]Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 } };
    const ok = [_]u8{ 0, 1, 1, 0 };
    const bad_index = [_]u8{ 0, 1, 2, 0 };
    const good = Image{ .name = "Lamp", .width = 2, .height = 2, .frame_width = 2, .frame_height = 2, .pixels = &ok };
    try (Art{ .palette = &palette, .images = &.{good} }).validate();
    try (Art{}).validate();

    var image = good;
    image.pixels = &bad_index;
    try std.testing.expectError(Error.InvalidImageIndex, (Art{ .palette = &palette, .images = &.{image} }).validate());
    try std.testing.expectError(Error.InvalidImagePalette, (Art{ .images = &.{good} }).validate());

    image = good;
    image.frame_width = 3;
    try std.testing.expectError(Error.InvalidImageSize, (Art{ .palette = &palette, .images = &.{image} }).validate());
    image = good;
    image.name = "";
    try std.testing.expectError(Error.InvalidImageName, (Art{ .palette = &palette, .images = &.{image} }).validate());
    try std.testing.expectError(Error.InvalidImageName, (Art{ .palette = &palette, .images = &.{ good, good } }).validate());

    var big: [MAX_COLOURS + 1]Colour = undefined;
    @memset(&big, .{ .r = 1, .g = 2, .b = 3 });
    try std.testing.expectError(Error.InvalidImagePalette, (Art{ .palette = &big }).validate());
}

test "P46-01: a backdrop is one 320x180 frame and a larger frame is refused" {
    try validate_size(ART_WIDTH, ART_HEIGHT, ART_WIDTH, ART_HEIGHT);
    try std.testing.expectError(Error.InvalidImageSize, validate_size(ART_WIDTH + 1, ART_HEIGHT, ART_WIDTH + 1, ART_HEIGHT));
    try std.testing.expectError(Error.InvalidImageSize, validate_size(MAX_SHEET_SIDE, MAX_SHEET_SIDE, 32, 32));
    try validate_size(1024, 1024, 32, 32);
}

test "P46-01: dupe copies art into owned memory" {
    const palette = [_]Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 9, .g = 8, .b = 7 } };
    var pixels = [_]u8{ 1, 0 };
    var art = try Art.dupe(std.testing.allocator, &palette, &.{.{ .name = "Dot", .width = 2, .height = 1, .frame_width = 1, .frame_height = 1, .pixels = &pixels }});
    defer art.deinit_owned(std.testing.allocator);
    pixels[0] = 0;
    try std.testing.expectEqual(@as(u8, 1), art.find("Dot").?.pixels[0]);
    try std.testing.expectEqual(@as(u32, 2), art.find("Dot").?.frame_count());
    try std.testing.expect(art.find("Missing") == null);
}
