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
const EntityId = @import("world.zig").EntityId;

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
    InvalidImageBinding,
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

/// What a sprite is doing, which picks its animation (P46-03, D-155). A person walking takes the
/// walk for the direction of the mark it is heading to; everything else idles.
pub const Anim = enum(u8) {
    idle,
    walk_up,
    walk_down,
    walk_left,
    walk_right,

    pub fn fromInt(raw: u8) ?Anim {
        return if (raw < ANIM_COUNT) @enumFromInt(raw) else null;
    }
};
pub const ANIM_COUNT = @typeInfo(Anim).@"enum".field_names.len;
/// Upper bounds a well-formed package never reaches (D-155).
pub const MAX_STEPS: usize = 64;
pub const MAX_DURATION: u16 = 600;
pub const MAX_BINDINGS: usize = 1024;

/// One step of an animation: a frame of the sheet and how many 60 Hz display frames it shows
/// (D-152 point 3).
pub const Step = struct { frame: u16, duration: u16 };

/// A scene drawn over a backdrop image instead of the neutral stage.
pub const Backdrop = struct { scene: EntityId, image: u16 };

/// A person or prop drawn from a sprite sheet. An empty animation falls back to idle, and an
/// empty idle shows frame 0.
pub const Sprite = struct {
    entity: EntityId,
    image: u16,
    animations: [ANIM_COUNT][]const Step = @splat(@as([]const Step, &.{})),

    /// The frame to show for `anim` at display frame `clock`. The clock is the host's counter
    /// of shown frames; it never enters the world, so a replay draws the same frames when the
    /// host replays the same clock (D-152).
    pub fn frame_at(self: Sprite, anim: Anim, clock: u64) u16 {
        var steps = self.animations[@intFromEnum(anim)];
        if (steps.len == 0) steps = self.animations[@intFromEnum(Anim.idle)];
        if (steps.len == 0) return 0;
        var total: u64 = 0;
        for (steps) |step| total += step.duration;
        var t = clock % total;
        for (steps) |step| {
            if (t < step.duration) return step.frame;
            t -= step.duration;
        }
        unreachable;
    }
};

/// A game's palette, images, and what they are attached to. Empty for a game drawn by code.
pub const Art = struct {
    palette: []const Colour = &.{},
    images: []const Image = &.{},
    backdrops: []const Backdrop = &.{},
    sprites: []const Sprite = &.{},

    pub fn is_empty(self: Art) bool {
        return self.palette.len == 0 and self.images.len == 0;
    }

    pub fn find(self: *const Art, name: []const u8) ?*const Image {
        for (self.images) |*image| if (std.mem.eql(u8, image.name, name)) return image;
        return null;
    }

    pub fn backdrop_for(self: *const Art, scene: EntityId) ?*const Image {
        for (self.backdrops) |b| if (b.scene == scene) return &self.images[b.image];
        return null;
    }

    pub fn sprite_for(self: *const Art, entity: EntityId) ?*const Sprite {
        for (self.sprites) |*sprite| if (sprite.entity == entity) return sprite;
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
        if (self.backdrops.len > MAX_BINDINGS or self.sprites.len > MAX_BINDINGS) return Error.InvalidImageBinding;
        for (self.backdrops, 0..) |b, i| {
            if (b.scene == .none or b.image >= self.images.len) return Error.InvalidImageBinding;
            const image = self.images[b.image];
            // A backdrop fills the art resolution with one frame (D-152).
            if (image.width != ART_WIDTH or image.height != ART_HEIGHT or image.frame_count() != 1) return Error.InvalidImageBinding;
            for (self.backdrops[0..i]) |prior| if (prior.scene == b.scene) return Error.InvalidImageBinding;
        }
        for (self.sprites, 0..) |sprite, i| {
            if (sprite.entity == .none or sprite.image >= self.images.len) return Error.InvalidImageBinding;
            const frames = self.images[sprite.image].frame_count();
            for (sprite.animations) |steps| {
                if (steps.len > MAX_STEPS) return Error.InvalidImageBinding;
                for (steps) |step| {
                    if (step.frame >= frames or step.duration == 0 or step.duration > MAX_DURATION) return Error.InvalidImageBinding;
                }
            }
            for (self.sprites[0..i]) |prior| if (prior.entity == sprite.entity) return Error.InvalidImageBinding;
        }
    }

    /// Validates, then copies everything into memory owned by `allocator`.
    pub fn dupe(allocator: std.mem.Allocator, source: Art) (Error || std.mem.Allocator.Error)!Art {
        try source.validate();
        var art = Art{};
        errdefer art.deinit_owned(allocator);
        art.palette = try allocator.dupe(Colour, source.palette);
        const images = try allocator.alloc(Image, source.images.len);
        @memset(images, .{ .name = &.{}, .width = 0, .height = 0, .frame_width = 0, .frame_height = 0, .pixels = &.{} });
        art.images = images;
        for (source.images, images) |image, *copy| {
            copy.* = image;
            copy.name = &.{};
            copy.pixels = &.{};
            copy.name = try allocator.dupe(u8, image.name);
            copy.pixels = try allocator.dupe(u8, image.pixels);
        }
        art.backdrops = try allocator.dupe(Backdrop, source.backdrops);
        const sprites = try allocator.alloc(Sprite, source.sprites.len);
        for (sprites) |*sprite| sprite.* = .{ .entity = .none, .image = 0 };
        art.sprites = sprites;
        for (source.sprites, sprites) |sprite, *copy| {
            copy.entity = sprite.entity;
            copy.image = sprite.image;
            for (sprite.animations, &copy.animations) |steps, *own| own.* = try allocator.dupe(Step, steps);
        }
        return art;
    }

    pub fn deinit_owned(self: *Art, allocator: std.mem.Allocator) void {
        for (self.images) |image| free_image(allocator, image);
        allocator.free(self.images);
        allocator.free(self.palette);
        allocator.free(self.backdrops);
        for (self.sprites) |sprite| for (sprite.animations) |steps| allocator.free(steps);
        allocator.free(self.sprites);
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
    var art = try Art.dupe(std.testing.allocator, .{ .palette = &palette, .images = &.{.{ .name = "Dot", .width = 2, .height = 1, .frame_width = 1, .frame_height = 1, .pixels = &pixels }} });
    defer art.deinit_owned(std.testing.allocator);
    pixels[0] = 0;
    try std.testing.expectEqual(@as(u8, 1), art.find("Dot").?.pixels[0]);
    try std.testing.expectEqual(@as(u32, 2), art.find("Dot").?.frame_count());
    try std.testing.expect(art.find("Missing") == null);
}

test "P46-03: a sprite plays its steps by display frame and falls back to idle, then frame 0" {
    const walk = [_]Step{ .{ .frame = 2, .duration = 6 }, .{ .frame = 3, .duration = 4 } };
    const idle = [_]Step{.{ .frame = 1, .duration = 30 }};
    var sprite = Sprite{ .entity = EntityId.from_int(1), .image = 0 };
    try std.testing.expectEqual(@as(u16, 0), sprite.frame_at(.walk_left, 99));
    sprite.animations[@intFromEnum(Anim.idle)] = &idle;
    try std.testing.expectEqual(@as(u16, 1), sprite.frame_at(.walk_left, 99));
    sprite.animations[@intFromEnum(Anim.walk_left)] = &walk;
    try std.testing.expectEqual(@as(u16, 2), sprite.frame_at(.walk_left, 0));
    try std.testing.expectEqual(@as(u16, 2), sprite.frame_at(.walk_left, 5));
    try std.testing.expectEqual(@as(u16, 3), sprite.frame_at(.walk_left, 6));
    try std.testing.expectEqual(@as(u16, 3), sprite.frame_at(.walk_left, 9));
    try std.testing.expectEqual(@as(u16, 2), sprite.frame_at(.walk_left, 10));
    try std.testing.expectEqual(@as(u16, 2), sprite.frame_at(.walk_left, 10 * 1000));
}

test "P46-03: bindings name real images, a backdrop is one 320x180 frame, and steps stay in the sheet" {
    const palette = [_]Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 1, .g = 2, .b = 3 } };
    const sheet_px = [_]u8{ 1, 0, 0, 1 };
    const sheet = Image{ .name = "Sheet", .width = 2, .height = 2, .frame_width = 1, .frame_height = 2, .pixels = &sheet_px };
    const step_ok = [_]Step{.{ .frame = 1, .duration = 6 }};
    const step_bad = [_]Step{.{ .frame = 2, .duration = 6 }};
    var sprite = Sprite{ .entity = EntityId.from_int(3), .image = 0 };
    sprite.animations[0] = &step_ok;
    try (Art{ .palette = &palette, .images = &.{sheet}, .sprites = &.{sprite} }).validate();
    sprite.animations[0] = &step_bad;
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .palette = &palette, .images = &.{sheet}, .sprites = &.{sprite} }).validate());
    // The sheet is not a 320x180 backdrop, and image 1 does not exist.
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .palette = &palette, .images = &.{sheet}, .backdrops = &.{.{ .scene = EntityId.from_int(4), .image = 0 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .palette = &palette, .images = &.{sheet}, .backdrops = &.{.{ .scene = EntityId.from_int(4), .image = 1 }} }).validate());

    sprite.animations[0] = &step_ok;
    var art = try Art.dupe(std.testing.allocator, .{ .palette = &palette, .images = &.{sheet}, .sprites = &.{sprite} });
    defer art.deinit_owned(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 1), art.sprite_for(EntityId.from_int(3)).?.frame_at(.idle, 0));
    try std.testing.expect(art.sprite_for(EntityId.from_int(9)) == null);
}
