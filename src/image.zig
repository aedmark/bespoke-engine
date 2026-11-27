//! Pixel art in the package (P46-01, D-151, D-152, D-166, D-182).
//!
//! A game carries any number of images: sprite sheets and backdrops. Every pixel is full colour
//! with binary alpha, opaque or fully transparent, and a transparent pixel is stored as all
//! zeroes so equal art compares equal (D-166). A script's `palette:` is a style rule the
//! compiler checks; it never reaches the package. The package stores each image as a QOI
//! stream (`qoi.zig`, D-182) and loads it back to these pixels. Art is drawn at 320x180 and scaled
//! 4x to the 1280x720 frame (D-097), so a frame (one cell of a sheet, or a whole backdrop) is at
//! most 320x180. A sheet is a grid of equal frames read left to right, then top to bottom.
//!
//! Art is presentation data. It is never written to the World, never saved in `.sav`, and never
//! rewound, so it cannot change a replay (D-151). Names are plain text for the same reason:
//! interning them would add entities to the fact table that no rule can use.
//!
//! Every value here may come from a package file, which is untrusted input. `Art.validate` is the
//! one gate: the package loader and `Art.dupe` both pass through it, so a renderer can index a
//! sheet with `frame_pixel` without checking again.
const std = @import("std");
const EntityId = @import("world.zig").EntityId;

/// The art resolution (D-152). A frame never exceeds it.
pub const ART_WIDTH: u16 = 320;
pub const ART_HEIGHT: u16 = 180;
/// Whole-number scale from art pixels to the 1280x720 frame (D-097, D-152).
pub const SCALE: u16 = 4;
/// The most colours a script's `palette:` may declare (D-182). Art without a palette has no
/// colour limit.
pub const MAX_COLOURS: usize = 256;
/// Upper bounds a well-formed package never reaches (D-153, D-182). They keep a corrupt count
/// or size from asking for memory before the bytes behind it are read; the total keeps a game's
/// decoded art within 8 MiB, half the browser heap (D-071), so the rest has room.
pub const MAX_IMAGES: usize = 1024;
pub const MAX_SHEET_SIDE: u16 = 2048;
pub const MAX_SHEET_PIXELS: usize = 1024 * 1024;
pub const MAX_ART_PIXELS: usize = 2 * 1024 * 1024;
pub const MAX_NAME: usize = 64;

pub const Error = error{
    InvalidImagePalette,
    InvalidImageCount,
    InvalidImageName,
    InvalidImageSize,
    InvalidImageIndex,
    InvalidImagePixel,
    InvalidImageData,
    InvalidImageBinding,
};

/// A palette colour, as a script declares one.
pub const Colour = struct { r: u8, g: u8, b: u8 };

/// One art pixel. Alpha is 0 or 255 (D-166).
pub const Pixel = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn opaque_colour(c: Colour) Pixel {
        return .{ .r = c.r, .g = c.g, .b = c.b, .a = 255 };
    }
};

/// The pixel drawn as nothing; every transparent pixel is stored this way.
pub const TRANSPARENT = Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 };

/// Pixels from palette indices, index 0 transparent: art built in code, such as a test's or a
/// proof's, is often easiest to write this way (D-166 keeps palettes as a style).
pub fn from_indices(comptime palette: []const Colour, comptime indices: []const u8) [indices.len]Pixel {
    var out: [indices.len]Pixel = undefined;
    for (indices, &out) |index, *p| p.* = if (index == 0) TRANSPARENT else Pixel.opaque_colour(palette[index]);
    return out;
}

/// One image. `pixels` holds `width * height` pixels, row by row.
pub const Image = struct {
    name: []const u8,
    width: u16,
    height: u16,
    frame_width: u16,
    frame_height: u16,
    pixels: []const Pixel,

    pub fn columns(self: Image) u32 {
        return self.width / self.frame_width;
    }

    pub fn frame_count(self: Image) u32 {
        return self.columns() * (self.height / self.frame_height);
    }

    /// The pixel at (x, y) inside `frame`. The caller keeps x and y inside the frame
    /// and `frame` below `frame_count`; a validated image then never reads past `pixels`.
    pub fn frame_pixel(self: Image, frame: u32, x: u16, y: u16) Pixel {
        std.debug.assert(frame < self.frame_count() and x < self.frame_width and y < self.frame_height);
        const left = (frame % self.columns()) * self.frame_width;
        const top = (frame / self.columns()) * self.frame_height;
        return self.pixels[(top + y) * @as(usize, self.width) + left + x];
    }

    /// Checks one image. The order is the order a loader meets the fields in, so a package
    /// reports the first thing wrong with it.
    pub fn validate(self: Image) Error!void {
        try validate_name(self.name);
        try validate_size(self.width, self.height, self.frame_width, self.frame_height);
        if (self.pixels.len != @as(usize, self.width) * self.height) return Error.InvalidImageSize;
        try validate_pixels(self.pixels);
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

/// Indexed art from a package older than version 34: index 0 is transparent, and every index
/// is inside the palette that came with it.
pub fn validate_indices(pixels: []const u8, colour_count: usize) Error!void {
    for (pixels) |index| if (index >= colour_count) return Error.InvalidImageIndex;
}

/// Alpha is 0 or 255, and a transparent pixel is all zeroes, so a renderer can test alpha
/// alone and two equal images hold equal bytes.
pub fn validate_pixels(pixels: []const Pixel) Error!void {
    for (pixels) |p| {
        if (p.a == 255) continue;
        if (!std.meta.eql(p, TRANSPARENT)) return Error.InvalidImagePixel;
    }
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
/// Colour cycling bounds (P49-01, D-190).
pub const MAX_CYCLES: usize = 64;
pub const DEFAULT_CYCLE_INTERVAL: u16 = 6;

/// One palette colour cycle (P49-01, D-190): `colours` rotate forward by one step every
/// `every` 60 Hz display frames.
pub const ColourCycle = struct {
    colours: []const Colour,
    every: u16 = DEFAULT_CYCLE_INTERVAL,

    pub fn step_at(self: ColourCycle, clock: u64) usize {
        std.debug.assert(self.colours.len >= 2 and self.every > 0);
        return @intCast((clock / self.every) % self.colours.len);
    }

    /// The colour drawn at display frame `clock` for pixels painted with `colours[index]`.
    pub fn colour_at(self: ColourCycle, index: usize, clock: u64) Colour {
        const k = self.step_at(clock);
        return self.colours[(index + self.colours.len - k) % self.colours.len];
    }
};

/// Per-frame RGB lookup built once before drawing a frame's art (P49-01, D-190). When no
/// cycle has stepped (`count == 0`), `remap` is a fast no-op.
pub const ColourMap = struct {
    pub const CAPACITY: usize = 512;
    const Entry = struct { key: u32 = 0, value: Pixel = TRANSPARENT };

    entries: [CAPACITY]Entry = @splat(.{}),
    count: usize = 0,

    fn pack(c: Colour) u32 {
        return (@as(u32, 0xff) << 24) | (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | @as(u32, c.b);
    }

    fn slot_index(key: u32) usize {
        return @intCast((key *% 2654435761) & (CAPACITY - 1));
    }

    pub fn from_cycles(cycles: []const ColourCycle, clock: u64) ColourMap {
        var map = ColourMap{};
        for (cycles) |cycle| {
            if (cycle.colours.len < 2 or cycle.every == 0) continue;
            const k = cycle.step_at(clock);
            if (k == 0) continue;
            for (cycle.colours, 0..) |c, i| {
                const key = pack(c);
                var idx = slot_index(key);
                while (map.entries[idx].key != 0 and map.entries[idx].key != key) {
                    idx = (idx + 1) & (CAPACITY - 1);
                }
                if (map.entries[idx].key == 0) map.count += 1;
                map.entries[idx] = .{
                    .key = key,
                    .value = Pixel.opaque_colour(cycle.colours[(i + cycle.colours.len - k) % cycle.colours.len]),
                };
            }
        }
        return map;
    }

    pub fn remap(self: *const ColourMap, p: Pixel) Pixel {
        if (self.count == 0 or p.a == 0) return p;
        const key = (@as(u32, 0xff) << 24) | (@as(u32, p.r) << 16) | (@as(u32, p.g) << 8) | @as(u32, p.b);
        var idx = slot_index(key);
        while (self.entries[idx].key != 0) {
            if (self.entries[idx].key == key) return self.entries[idx].value;
            idx = (idx + 1) & (CAPACITY - 1);
        }
        return p;
    }
};

/// One step of an animation: a frame of the sheet and how many 60 Hz display frames it shows
/// (D-152 point 3).
pub const Step = struct { frame: u16, duration: u16 };

/// A scene drawn over a backdrop image instead of the neutral stage.
pub const Backdrop = struct { scene: EntityId, image: u16 };

/// A prop's clickable region on the art, in art pixels (P46-05, D-158): the window or door
/// painted on a backdrop, or the whole of a lamp. A click anywhere inside acts on the prop, the
/// hover outline is this rectangle, and a prop with an area and no sprite draws nothing of its
/// own, because the art already shows it.
pub const Area = struct {
    entity: EntityId,
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    pub fn valid(self: Area) bool {
        return self.entity != .none and self.w > 0 and self.h > 0 and
            @as(u32, self.x) + self.w <= ART_WIDTH and @as(u32, self.y) + self.h <= ART_HEIGHT;
    }
};

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
        return frame_in(self.animations, anim, clock);
    }
};

/// The frame `animations` show for `anim` at display frame `clock`: the walk falls back to the
/// idle, and no idle shows frame 0. Shared by sprites and looks.
pub fn frame_in(animations: [ANIM_COUNT][]const Step, anim: Anim, clock: u64) u16 {
    var steps = animations[@intFromEnum(anim)];
    if (steps.len == 0) steps = animations[@intFromEnum(Anim.idle)];
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

/// A named way of showing an image with its own animations (P48-11, D-181), so several looks
/// can share one sheet. A `Looks(Thing, Look)` fact picks one for a thing.
pub const Look = struct {
    name: []const u8,
    image: u16,
    animations: [ANIM_COUNT][]const Step = @splat(@as([]const Step, &.{})),

    pub fn frame_at(self: Look, anim: Anim, clock: u64) u16 {
        return frame_in(self.animations, anim, clock);
    }
};

/// A part drawn with its host at an offset in art pixels from the host's anchor (P48-11,
/// D-181); it follows the host's walking and heading and is clicked as the host.
pub const Part = struct {
    entity: EntityId,
    host: EntityId,
    dx: i16,
    dy: i16,
};

/// The furthest a part may sit from its host's anchor, in art pixels.
pub const MAX_PART_OFFSET: i16 = ART_WIDTH;

/// A game's images and what they are attached to. Empty for a game drawn by code.
pub const Art = struct {
    images: []const Image = &.{},
    backdrops: []const Backdrop = &.{},
    sprites: []const Sprite = &.{},
    areas: []const Area = &.{},
    looks: []const Look = &.{},
    parts: []const Part = &.{},
    cycles: []const ColourCycle = &.{},

    pub fn is_empty(self: Art) bool {
        return self.images.len == 0 and self.areas.len == 0 and self.looks.len == 0 and self.parts.len == 0 and self.cycles.len == 0;
    }

    pub fn look_named(self: *const Art, name: []const u8) ?*const Look {
        for (self.looks) |*look| if (std.mem.eql(u8, look.name, name)) return look;
        return null;
    }

    pub fn part_for(self: *const Art, entity: EntityId) ?Part {
        for (self.parts) |part| if (part.entity == entity) return part;
        return null;
    }

    pub fn area_for(self: *const Art, entity: EntityId) ?Area {
        for (self.areas) |a| if (a.entity == entity) return a;
        return null;
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
        if (self.images.len > MAX_IMAGES) return Error.InvalidImageCount;
        var total: usize = 0;
        for (self.images, 0..) |image, i| {
            try image.validate();
            total += image.pixels.len;
            if (total > MAX_ART_PIXELS) return Error.InvalidImageSize;
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
        if (self.looks.len > MAX_BINDINGS or self.parts.len > MAX_BINDINGS) return Error.InvalidImageBinding;
        for (self.looks, 0..) |look, i| {
            validate_name(look.name) catch return Error.InvalidImageBinding;
            if (look.image >= self.images.len) return Error.InvalidImageBinding;
            const frames = self.images[look.image].frame_count();
            for (look.animations) |steps| {
                if (steps.len > MAX_STEPS) return Error.InvalidImageBinding;
                for (steps) |step| {
                    if (step.frame >= frames or step.duration == 0 or step.duration > MAX_DURATION) return Error.InvalidImageBinding;
                }
            }
            for (self.looks[0..i]) |prior| if (std.mem.eql(u8, prior.name, look.name)) return Error.InvalidImageBinding;
        }
        for (self.parts, 0..) |part, i| {
            if (part.entity == .none or part.host == .none or part.entity == part.host) return Error.InvalidImageBinding;
            if (@abs(part.dx) > MAX_PART_OFFSET or @abs(part.dy) > MAX_PART_OFFSET) return Error.InvalidImageBinding;
            for (self.parts[0..i]) |prior| if (prior.entity == part.entity) return Error.InvalidImageBinding;
            var cur = part.host;
            var hops: usize = 0;
            while (hops < self.parts.len) : (hops += 1) {
                const parent = self.part_for(cur) orelse break;
                if (parent.host == part.entity) return Error.InvalidImageBinding;
                cur = parent.host;
            }
        }
        if (self.areas.len > MAX_BINDINGS) return Error.InvalidImageBinding;
        for (self.areas, 0..) |a, i| {
            if (!a.valid()) return Error.InvalidImageBinding;
            for (self.areas[0..i]) |prior| if (prior.entity == a.entity) return Error.InvalidImageBinding;
        }
        if (self.cycles.len > MAX_CYCLES) return Error.InvalidImageBinding;
        var total_cycled: usize = 0;
        for (self.cycles, 0..) |cycle, ci| {
            if (cycle.colours.len < 2 or cycle.colours.len >= MAX_COLOURS) return Error.InvalidImageBinding;
            if (cycle.every == 0 or cycle.every > MAX_DURATION) return Error.InvalidImageBinding;
            total_cycled += cycle.colours.len;
            if (total_cycled >= MAX_COLOURS) return Error.InvalidImageBinding;
            for (cycle.colours, 0..) |c, j| {
                for (cycle.colours[0..j]) |prior| if (std.meta.eql(prior, c)) return Error.InvalidImageBinding;
                for (self.cycles[0..ci]) |other| {
                    for (other.colours) |prior| if (std.meta.eql(prior, c)) return Error.InvalidImageBinding;
                }
            }
        }
    }

    /// Validates, then copies everything into memory owned by `allocator`.
    pub fn dupe(allocator: std.mem.Allocator, source: Art) (Error || std.mem.Allocator.Error)!Art {
        try source.validate();
        var art = Art{};
        errdefer art.deinit_owned(allocator);
        const images = try allocator.alloc(Image, source.images.len);
        @memset(images, .{ .name = &.{}, .width = 0, .height = 0, .frame_width = 0, .frame_height = 0, .pixels = &.{} });
        art.images = images;
        for (source.images, images) |image, *copy| {
            copy.* = image;
            copy.name = &.{};
            copy.pixels = &.{};
            copy.name = try allocator.dupe(u8, image.name);
            copy.pixels = try allocator.dupe(Pixel, image.pixels);
        }
        art.backdrops = try allocator.dupe(Backdrop, source.backdrops);
        art.areas = try allocator.dupe(Area, source.areas);
        art.parts = try allocator.dupe(Part, source.parts);
        const looks = try allocator.alloc(Look, source.looks.len);
        for (looks) |*look| look.* = .{ .name = &.{}, .image = 0 };
        art.looks = looks;
        for (source.looks, looks) |look, *copy| {
            copy.image = look.image;
            copy.name = try allocator.dupe(u8, look.name);
            for (look.animations, &copy.animations) |steps, *own| own.* = try allocator.dupe(Step, steps);
        }
        const sprites = try allocator.alloc(Sprite, source.sprites.len);
        for (sprites) |*sprite| sprite.* = .{ .entity = .none, .image = 0 };
        art.sprites = sprites;
        for (source.sprites, sprites) |sprite, *copy| {
            copy.entity = sprite.entity;
            copy.image = sprite.image;
            for (sprite.animations, &copy.animations) |steps, *own| own.* = try allocator.dupe(Step, steps);
        }
        const cycles = try allocator.alloc(ColourCycle, source.cycles.len);
        for (cycles) |*cycle| cycle.* = .{ .colours = &.{} };
        art.cycles = cycles;
        for (source.cycles, cycles) |cycle, *copy| {
            copy.every = cycle.every;
            copy.colours = try allocator.dupe(Colour, cycle.colours);
        }
        return art;
    }

    pub fn deinit_owned(self: *Art, allocator: std.mem.Allocator) void {
        for (self.images) |image| free_image(allocator, image);
        allocator.free(self.images);
        allocator.free(self.backdrops);
        allocator.free(self.areas);
        allocator.free(self.parts);
        for (self.looks) |look| {
            allocator.free(look.name);
            for (look.animations) |steps| allocator.free(steps);
        }
        allocator.free(self.looks);
        for (self.sprites) |sprite| for (sprite.animations) |steps| allocator.free(steps);
        allocator.free(self.sprites);
        for (self.cycles) |cycle| allocator.free(cycle.colours);
        allocator.free(self.cycles);
        self.* = .{};
    }
};

pub fn free_image(allocator: std.mem.Allocator, image: Image) void {
    allocator.free(image.name);
    allocator.free(image.pixels);
}

/// A test pixel: 0 is transparent, and any other value an opaque grey of that level.
fn grey(n: u8) Pixel {
    return if (n == 0) TRANSPARENT else .{ .r = n, .g = n, .b = n, .a = 255 };
}

fn greys(comptime levels: []const u8) [levels.len]Pixel {
    var out: [levels.len]Pixel = undefined;
    for (levels, &out) |n, *p| p.* = grey(n);
    return out;
}

test "P46-01: a sheet's frames read left to right, then top to bottom" {
    // A 4x2 sheet of four 2x1 frames in two columns and two rows.
    const pixels = greys(&.{ 1, 1, 2, 2, 3, 3, 0, 1 });
    const sheet = Image{ .name = "Sheet", .width = 4, .height = 2, .frame_width = 2, .frame_height = 1, .pixels = &pixels };
    try sheet.validate();
    try std.testing.expectEqual(@as(u32, 4), sheet.frame_count());
    try std.testing.expectEqual(grey(2), sheet.frame_pixel(1, 0, 0));
    try std.testing.expectEqual(grey(3), sheet.frame_pixel(2, 1, 0));
    try std.testing.expectEqual(grey(1), sheet.frame_pixel(3, 1, 0));
}

test "P48-12: art validation names what is wrong" {
    const ok = greys(&.{ 0, 1, 1, 0 });
    const good = Image{ .name = "Lamp", .width = 2, .height = 2, .frame_width = 2, .frame_height = 2, .pixels = &ok };
    try (Art{ .images = &.{good} }).validate();
    try (Art{}).validate();

    // Alpha is 0 or 255, and a transparent pixel holds no colour.
    var image = good;
    const half = [_]Pixel{ grey(1), .{ .r = 1, .g = 1, .b = 1, .a = 128 }, grey(1), grey(1) };
    image.pixels = &half;
    try std.testing.expectError(Error.InvalidImagePixel, (Art{ .images = &.{image} }).validate());
    const ghost = [_]Pixel{ grey(1), .{ .r = 9, .g = 0, .b = 0, .a = 0 }, grey(1), grey(1) };
    image.pixels = &ghost;
    try std.testing.expectError(Error.InvalidImagePixel, (Art{ .images = &.{image} }).validate());

    image = good;
    image.frame_width = 3;
    try std.testing.expectError(Error.InvalidImageSize, (Art{ .images = &.{image} }).validate());
    image = good;
    image.name = "";
    try std.testing.expectError(Error.InvalidImageName, (Art{ .images = &.{image} }).validate());
    try std.testing.expectError(Error.InvalidImageName, (Art{ .images = &.{ good, good } }).validate());
    try std.testing.expectError(Error.InvalidImageIndex, validate_indices(&.{ 0, 1, 2 }, 2));
}

test "P48-12: a game's images together stay under the total pixel cap" {
    const many = try std.testing.allocator.alloc(Pixel, MAX_SHEET_PIXELS);
    defer std.testing.allocator.free(many);
    @memset(many, TRANSPARENT);
    var sheets: [3]Image = undefined;
    const names = [_][]const u8{ "A", "B", "C" };
    for (&sheets, names) |*sheet, name| sheet.* = .{ .name = name, .width = 1024, .height = 1024, .frame_width = 32, .frame_height = 32, .pixels = many };
    try (Art{ .images = sheets[0..2] }).validate();
    try std.testing.expectError(Error.InvalidImageSize, (Art{ .images = &sheets }).validate());
}

test "P46-01: a backdrop is one 320x180 frame and a larger frame is refused" {
    try validate_size(ART_WIDTH, ART_HEIGHT, ART_WIDTH, ART_HEIGHT);
    try std.testing.expectError(Error.InvalidImageSize, validate_size(ART_WIDTH + 1, ART_HEIGHT, ART_WIDTH + 1, ART_HEIGHT));
    try std.testing.expectError(Error.InvalidImageSize, validate_size(MAX_SHEET_SIDE, MAX_SHEET_SIDE, 32, 32));
    try validate_size(1024, 1024, 32, 32);
}

test "P46-01: dupe copies art into owned memory" {
    var pixels = greys(&.{ 1, 0 });
    var art = try Art.dupe(std.testing.allocator, .{ .images = &.{.{ .name = "Dot", .width = 2, .height = 1, .frame_width = 1, .frame_height = 1, .pixels = &pixels }} });
    defer art.deinit_owned(std.testing.allocator);
    pixels[0] = TRANSPARENT;
    try std.testing.expectEqual(grey(1), art.find("Dot").?.pixels[0]);
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
    const sheet_px = greys(&.{ 1, 0, 0, 1 });
    const sheet = Image{ .name = "Sheet", .width = 2, .height = 2, .frame_width = 1, .frame_height = 2, .pixels = &sheet_px };
    const step_ok = [_]Step{.{ .frame = 1, .duration = 6 }};
    const step_bad = [_]Step{.{ .frame = 2, .duration = 6 }};
    var sprite = Sprite{ .entity = EntityId.from_int(3), .image = 0 };
    sprite.animations[0] = &step_ok;
    try (Art{ .images = &.{sheet}, .sprites = &.{sprite} }).validate();
    sprite.animations[0] = &step_bad;
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .images = &.{sheet}, .sprites = &.{sprite} }).validate());
    // The sheet is not a 320x180 backdrop, and image 1 does not exist.
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .images = &.{sheet}, .backdrops = &.{.{ .scene = EntityId.from_int(4), .image = 0 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .images = &.{sheet}, .backdrops = &.{.{ .scene = EntityId.from_int(4), .image = 1 }} }).validate());

    sprite.animations[0] = &step_ok;
    var art = try Art.dupe(std.testing.allocator, .{ .images = &.{sheet}, .sprites = &.{sprite} });
    defer art.deinit_owned(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 1), art.sprite_for(EntityId.from_int(3)).?.frame_at(.idle, 0));
    try std.testing.expect(art.sprite_for(EntityId.from_int(9)) == null);
}

test "P46-05: an area stays on the art and names one prop once" {
    const room = Area{ .entity = EntityId.from_int(5), .x = 300, .y = 170, .w = 20, .h = 10 };
    try std.testing.expect(room.valid());
    var past = room;
    past.w = 21;
    try std.testing.expect(!past.valid());
    try (Art{ .areas = &.{room} }).validate();
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .areas = &.{ room, room } }).validate());
    try std.testing.expect(!(Art{ .areas = &.{room} }).is_empty());
    try std.testing.expectEqual(@as(u16, 300), (Art{ .areas = &.{room} }).area_for(EntityId.from_int(5)).?.x);
}

test "P48-25: part attachment cycles (2-node and 3-node) are rejected by Art.validate" {
    const a = EntityId.from_int(1);
    const b = EntityId.from_int(2);
    const c = EntityId.from_int(3);
    const two = Art{ .parts = &.{
        .{ .entity = a, .host = b, .dx = 0, .dy = 0 },
        .{ .entity = b, .host = a, .dx = 0, .dy = 0 },
    } };
    try std.testing.expectError(Error.InvalidImageBinding, two.validate());

    const three = Art{ .parts = &.{
        .{ .entity = a, .host = b, .dx = 0, .dy = 0 },
        .{ .entity = b, .host = c, .dx = 0, .dy = 0 },
        .{ .entity = c, .host = a, .dx = 0, .dy = 0 },
    } };
    try std.testing.expectError(Error.InvalidImageBinding, three.validate());
}

test "P49-01: colour cycles rotate forward and validate bounds and disjoint RGBs" {
    const a = Colour{ .r = 10, .g = 20, .b = 30 };
    const b = Colour{ .r = 40, .g = 50, .b = 60 };
    const c = Colour{ .r = 70, .g = 80, .b = 90 };
    const d = Colour{ .r = 100, .g = 110, .b = 120 };
    const cycle = ColourCycle{ .colours = &.{ a, b, c }, .every = 8 };

    try std.testing.expectEqual(a, cycle.colour_at(0, 0));
    try std.testing.expectEqual(c, cycle.colour_at(0, 8));
    try std.testing.expectEqual(a, cycle.colour_at(1, 8));
    try std.testing.expectEqual(b, cycle.colour_at(2, 8));
    try std.testing.expectEqual(b, cycle.colour_at(0, 16));
    try std.testing.expectEqual(a, cycle.colour_at(0, 24));

    const map0 = ColourMap.from_cycles(&.{cycle}, 0);
    try std.testing.expectEqual(@as(usize, 0), map0.count);
    try std.testing.expectEqual(Pixel.opaque_colour(a), map0.remap(Pixel.opaque_colour(a)));

    const map8 = ColourMap.from_cycles(&.{cycle}, 8);
    try std.testing.expectEqual(@as(usize, 3), map8.count);
    try std.testing.expectEqual(Pixel.opaque_colour(c), map8.remap(Pixel.opaque_colour(a)));
    try std.testing.expectEqual(Pixel.opaque_colour(a), map8.remap(Pixel.opaque_colour(b)));
    try std.testing.expectEqual(Pixel.opaque_colour(b), map8.remap(Pixel.opaque_colour(c)));
    try std.testing.expectEqual(Pixel.opaque_colour(d), map8.remap(Pixel.opaque_colour(d)));
    try std.testing.expectEqual(TRANSPARENT, map8.remap(TRANSPARENT));

    try (Art{ .cycles = &.{cycle} }).validate();
    try std.testing.expect(!(Art{ .cycles = &.{cycle} }).is_empty());

    var owned = try Art.dupe(std.testing.allocator, .{ .cycles = &.{cycle} });
    defer owned.deinit_owned(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), owned.cycles.len);
    try std.testing.expectEqual(@as(u16, 8), owned.cycles[0].every);
    try std.testing.expectEqualSlices(Colour, &.{ a, b, c }, owned.cycles[0].colours);

    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &.{.{ .colours = &.{a}, .every = 6 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &.{.{ .colours = &.{ a, b }, .every = 0 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &.{.{ .colours = &.{ a, b }, .every = MAX_DURATION + 1 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &.{.{ .colours = &.{ a, b, a }, .every = 6 }} }).validate());
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &.{
        .{ .colours = &.{ a, b }, .every = 6 },
        .{ .colours = &.{ b, c }, .every = 6 },
    } }).validate());

    var too_many: [MAX_CYCLES + 1]ColourCycle = undefined;
    for (&too_many) |*slot| slot.* = .{ .colours = &.{ a, b }, .every = 6 };
    try std.testing.expectError(Error.InvalidImageBinding, (Art{ .cycles = &too_many }).validate());
}
