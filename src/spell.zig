//! Combinable spell vocabularies (P44-04).
//!
//! A `spellbook` declaration names words in three kinds (power, element, form) and the
//! combinations that spell something. A combination resolves to the cue named after the spell,
//! so the script owns the effect while the engine owns lookup and discovery.
//!
//! The declaration is program data owned by `CompiledProgram`, never world state: a save, a
//! rewind, and a replay see the same book. What a caster has learned is an ordinary relational
//! fact, `Knows` or `Believes` with `Rejects` overriding both (P21-02, D-015), so discovery
//! needs no new save field.
//!
//! Tiers are the word's position in its kind, counted from one. They order the author's
//! vocabulary and give a readout something stable to print; they do not gate a cast. A cast is
//! refused only when one of its words is not known, and a triple that names no spell is
//! refused before any cue fires.
const std = @import("std");
const world_mod = @import("world.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;

/// One book per script. A second book would make `host.cast` ambiguous.
pub const MAX_BOOKS: usize = 1;
pub const MAX_WORDS_PER_KIND: usize = 12;
pub const MAX_WORDS: usize = MAX_WORDS_PER_KIND * 3;
pub const MAX_SPELLS: usize = 16;
pub const MAX_WORD_TEXT: usize = 32;

/// Relations a caster's knowledge is read from, in priority order. `Rejects` beats both.
pub const KNOWS_RELATION = "Knows";
pub const BELIEVES_RELATION = "Believes";
pub const REJECTS_RELATION = "Rejects";

pub const Error = error{InvalidSpellbook};

/// The three positions of a combination. The values are serialized in `.bspk` packages.
pub const Kind = enum(u2) {
    power = 1,
    element = 2,
    form = 3,

    pub fn fromInt(value: u32) ?Kind {
        return switch (value) {
            1 => .power,
            2 => .element,
            3 => .form,
            else => null,
        };
    }

    /// Zero-based slot in `Spell.words`.
    pub fn index(self: Kind) usize {
        return @backingInt(self) - 1;
    }

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .power => "power",
            .element => "element",
            .form => "form",
        };
    }

    pub fn plural(self: Kind) []const u8 {
        return switch (self) {
            .power => "powers",
            .element => "elements",
            .form => "forms",
        };
    }
};

/// One word of a book. `tier` is its position among the words of its kind, from one.
pub const Word = struct {
    entity: EntityId,
    kind: Kind,
    tier: u16,
};

/// One combination that resolves. `words` is in kind order: power, element, form.
pub const Spell = struct {
    entity: EntityId,
    words: [3]EntityId,

    pub fn word(self: Spell, kind: Kind) EntityId {
        return self.words[kind.index()];
    }
};

pub const Book = struct {
    entity: EntityId,
    words: []const Word,
    spells: []const Spell,
};

/// Compiler-owned declaration. The slices are freed by `deinit_owned`; entity names are
/// borrowed from the World's tables, which outlives the program.
pub const Declaration = struct {
    book: Book,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.book.words);
        allocator.free(self.book.spells);
        self.* = undefined;
    }
};

/// Why a combination did not resolve. Ordered the way a cast checks its words.
pub const Refusal = enum {
    no_such_spell,
    unlearned_power,
    unlearned_element,
    unlearned_form,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .no_such_spell => "no such spell",
            .unlearned_power => "the power is unknown",
            .unlearned_element => "the element is unknown",
            .unlearned_form => "the form is unknown",
        };
    }
};

pub const Outcome = union(enum) {
    cast: Spell,
    refused: Refusal,
};

pub fn find_word(book: *const Book, entity: EntityId) ?Word {
    for (book.words) |word| if (word.entity == entity) return word;
    return null;
}

/// The spell a triple names, or null when the combination is not in the book.
pub fn resolve(book: *const Book, power: EntityId, element: EntityId, form: EntityId) ?Spell {
    const wanted = [3]EntityId{ power, element, form };
    for (book.spells) |spell| {
        if (spell.words[0] == wanted[0] and spell.words[1] == wanted[1] and spell.words[2] == wanted[2]) return spell;
    }
    return null;
}

/// The spell a name names, or null.
pub fn named(book: *const Book, entity: EntityId) ?Spell {
    for (book.spells) |spell| if (spell.entity == entity) return spell;
    return null;
}

/// The spell whose name matches `text`, ignoring ASCII case. A typed line reaches a spell this
/// way because the command bar lowercases what the player types.
pub fn named_text(book: *const Book, world: *const World, text: []const u8) ?Spell {
    for (book.spells) |spell| {
        const name = world.get_entity_name(spell.entity) orelse continue;
        if (std.ascii.eqlIgnoreCase(name, text)) return spell;
    }
    return null;
}

/// What the caster knows: `Knows` or `Believes`, unless `Rejects` says otherwise.
pub fn knows(world: *const World, caster: EntityId, entity: EntityId) bool {
    if (world.lookup_relation(REJECTS_RELATION)) |relation| {
        if (world.has_fact(caster, relation, entity.to_int())) return false;
    }
    for ([_][]const u8{ KNOWS_RELATION, BELIEVES_RELATION }) |name| {
        if (world.lookup_relation(name)) |relation| {
            if (world.has_fact(caster, relation, entity.to_int())) return true;
        }
    }
    return false;
}

/// Checks every word of a resolved spell against what the caster knows. The first unknown word
/// refuses the whole combination, so a cast never half-happens.
pub fn check(world: *const World, caster: EntityId, spell: Spell) Outcome {
    for (spell.words, 0..) |entity, i| {
        if (knows(world, caster, entity)) continue;
        return .{ .refused = switch (i) {
            0 => .unlearned_power,
            1 => .unlearned_element,
            else => .unlearned_form,
        } };
    }
    return .{ .cast = spell };
}

/// Casts the named spell for `caster`, gated by the words the caster knows.
pub fn cast(book: *const Book, world: *const World, caster: EntityId, name: EntityId) Outcome {
    const spell = named(book, name) orelse return .{ .refused = .no_such_spell };
    return check(world, caster, spell);
}

/// Combines three words, gated by the words the caster knows. An invalid triple is refused
/// without changing any state.
pub fn combine(book: *const Book, world: *const World, caster: EntityId, power: EntityId, element: EntityId, form: EntityId) Outcome {
    const spell = resolve(book, power, element, form) orelse return .{ .refused = .no_such_spell };
    return check(world, caster, spell);
}

fn triple_eql(a: Spell, b: Spell) bool {
    return a.words[0] == b.words[0] and a.words[1] == b.words[1] and a.words[2] == b.words[2];
}

/// Refuses a book a host could not use: a word or spell without an entity, a word outside its
/// kind, a tier outside the declared range, a repeated tier or name, a spell that names an
/// undeclared word or a word of the wrong kind, and two spells that resolve the same triple.
pub fn validate(declaration: Declaration) Error!void {
    const book = declaration.book;
    if (book.entity == .none) return Error.InvalidSpellbook;
    if (book.words.len == 0 or book.words.len > MAX_WORDS) return Error.InvalidSpellbook;
    if (book.spells.len == 0 or book.spells.len > MAX_SPELLS) return Error.InvalidSpellbook;

    var counts = [3]usize{ 0, 0, 0 };
    for (book.words, 0..) |word, i| {
        if (word.entity == .none) return Error.InvalidSpellbook;
        const slot = word.kind.index();
        if (counts[slot] == MAX_WORDS_PER_KIND) return Error.InvalidSpellbook;
        if (word.tier == 0 or word.tier > MAX_WORDS_PER_KIND) return Error.InvalidSpellbook;
        counts[slot] += 1;
        for (book.words[0..i]) |prior| {
            if (prior.entity == word.entity) return Error.InvalidSpellbook;
            if (prior.kind == word.kind and prior.tier == word.tier) return Error.InvalidSpellbook;
        }
    }

    for (book.spells, 0..) |spell, i| {
        if (spell.entity == .none) return Error.InvalidSpellbook;
        for (spell.words, 0..) |entity, slot| {
            const word = find_word(&book, entity) orelse return Error.InvalidSpellbook;
            if (word.kind.index() != slot) return Error.InvalidSpellbook;
        }
        for (book.spells[0..i]) |prior| {
            if (prior.entity == spell.entity) return Error.InvalidSpellbook;
            if (triple_eql(prior, spell)) return Error.InvalidSpellbook;
        }
        for (book.words) |word| if (word.entity == spell.entity) return Error.InvalidSpellbook;
    }
}

/// Validates a program's books together. One book is allowed; word and spell entities must be
/// unique across the file because both are interned by name.
pub fn validate_all(declarations: []const Declaration) Error!void {
    if (declarations.len > MAX_BOOKS) return Error.InvalidSpellbook;
    for (declarations, 0..) |declaration, i| {
        try validate(declaration);
        for (declarations[0..i]) |prior| {
            if (prior.book.entity == declaration.book.entity) return Error.InvalidSpellbook;
            for (prior.book.words) |word| for (declaration.book.words) |other| {
                if (word.entity == other.entity) return Error.InvalidSpellbook;
            };
            for (prior.book.spells) |spell| for (declaration.book.spells) |other| {
                if (spell.entity == other.entity) return Error.InvalidSpellbook;
            };
        }
    }
}

test "P44-04: a valid triple resolves, and an invalid one is refused" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const forge = try world.intern_entity("Forge");
    const ember = try world.intern_entity("Ember");
    const bolt = try world.intern_entity("Bolt");
    const spark = try world.intern_entity("Spark");
    const ward = try world.intern_entity("Ward");
    const kindle = try world.intern_entity("Kindle");
    const words = [_]Word{
        .{ .entity = spark, .kind = .power, .tier = 1 },
        .{ .entity = forge, .kind = .power, .tier = 2 },
        .{ .entity = ember, .kind = .element, .tier = 1 },
        .{ .entity = bolt, .kind = .form, .tier = 1 },
        .{ .entity = ward, .kind = .form, .tier = 2 },
    };
    const spells = [_]Spell{.{ .entity = kindle, .words = .{ forge, ember, bolt } }};
    const book = Book{ .entity = try world.intern_entity("Grimoire"), .words = &words, .spells = &spells };
    try validate(.{ .book = book });

    try testing.expectEqual(kindle, resolve(&book, forge, ember, bolt).?.entity);
    try testing.expect(resolve(&book, forge, ember, ward) == null);
    try testing.expectEqual(kindle, named_text(&book, &world, "kindle").?.entity);
    try testing.expect(named_text(&book, &world, "temper") == null);
}

test "P44-04: validation refuses a wrong-kind word, a duplicate triple, and a repeated tier" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const forge = try world.intern_entity("Forge");
    const ember = try world.intern_entity("Ember");
    const bolt = try world.intern_entity("Bolt");
    const kindle = try world.intern_entity("Kindle");
    const douse = try world.intern_entity("Douse");
    var words = [_]Word{
        .{ .entity = forge, .kind = .power, .tier = 1 },
        .{ .entity = ember, .kind = .element, .tier = 1 },
        .{ .entity = bolt, .kind = .form, .tier = 1 },
    };
    var single = [1]Spell{.{ .entity = kindle, .words = .{ forge, ember, bolt } }};
    const book_entity = try world.intern_entity("Grimoire");
    const book = Book{ .entity = book_entity, .words = &words, .spells = &single };

    // The element slot names a power.
    single[0].words = .{ ember, forge, bolt };
    try testing.expectError(Error.InvalidSpellbook, validate(.{ .book = book }));

    // Two spells resolve the same triple.
    single[0].words = .{ forge, ember, bolt };
    var pair = [2]Spell{
        .{ .entity = kindle, .words = .{ forge, ember, bolt } },
        .{ .entity = douse, .words = .{ forge, ember, bolt } },
    };
    try testing.expectError(Error.InvalidSpellbook, validate(.{ .book = .{ .entity = book_entity, .words = &words, .spells = &pair } }));

    // Two powers share tier one.
    const second_power = try world.intern_entity("Spark");
    var repeated = [_]Word{
        .{ .entity = forge, .kind = .power, .tier = 1 },
        .{ .entity = second_power, .kind = .power, .tier = 1 },
        .{ .entity = ember, .kind = .element, .tier = 1 },
        .{ .entity = bolt, .kind = .form, .tier = 1 },
    };
    try testing.expectError(Error.InvalidSpellbook, validate(.{ .book = .{ .entity = book_entity, .words = &repeated, .spells = &single } }));
    repeated[1].tier = 2;
    try validate(.{ .book = .{ .entity = book_entity, .words = &repeated, .spells = &single } });
}

test "P44-04: each word is gated by discovery, and Rejects overrides Knows" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const caster = try world.intern_entity("Maren");
    const forge = try world.intern_entity("Forge");
    const ember = try world.intern_entity("Ember");
    const bolt = try world.intern_entity("Bolt");
    const kindle = try world.intern_entity("Kindle");
    const words = [_]Word{
        .{ .entity = forge, .kind = .power, .tier = 1 },
        .{ .entity = ember, .kind = .element, .tier = 1 },
        .{ .entity = bolt, .kind = .form, .tier = 1 },
    };
    const spells = [_]Spell{.{ .entity = kindle, .words = .{ forge, ember, bolt } }};
    const book = Book{ .entity = try world.intern_entity("Grimoire"), .words = &words, .spells = &spells };

    // Nothing known: the power refuses first.
    try testing.expectEqual(Refusal.unlearned_power, cast(&book, &world, caster, kindle).refused);

    const knows_rel = try world.intern_relation(KNOWS_RELATION, .set);
    try world.remember(caster, knows_rel, forge.to_int(), 0);
    try testing.expectEqual(Refusal.unlearned_element, cast(&book, &world, caster, kindle).refused);

    // `Believes` counts as knowledge.
    const believes = try world.intern_relation(BELIEVES_RELATION, .set);
    try world.remember(caster, believes, ember.to_int(), 0);
    try testing.expectEqual(Refusal.unlearned_form, cast(&book, &world, caster, kindle).refused);

    try world.remember(caster, knows_rel, bolt.to_int(), 0);
    const outcome = cast(&book, &world, caster, kindle);
    try testing.expectEqual(kindle, outcome.cast.entity);
    try testing.expectEqual(kindle, combine(&book, &world, caster, forge, ember, bolt).cast.entity);

    // A rejected word is not known, whatever Knows says.
    const rejects = try world.intern_relation(REJECTS_RELATION, .set);
    try world.remember(caster, rejects, ember.to_int(), 0);
    try testing.expectEqual(Refusal.unlearned_element, cast(&book, &world, caster, kindle).refused);

    // An absent spell and an invalid triple are refused before any word is checked.
    const unknown = try world.intern_entity("Temper");
    try testing.expectEqual(Refusal.no_such_spell, cast(&book, &world, caster, unknown).refused);
    try testing.expectEqual(Refusal.no_such_spell, combine(&book, &world, caster, forge, bolt, ember).refused);
}
