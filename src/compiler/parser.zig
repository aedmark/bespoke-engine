const std = @import("std");
const lexer_mod = @import("lexer.zig");
pub const Lexer = lexer_mod.Lexer;
pub const Token = lexer_mod.Token;
pub const TokenTag = lexer_mod.TokenTag;
const draft_mod = @import("../draft.zig");
pub const Note = draft_mod.Note;
pub const Notes = draft_mod.Notes;

pub const FactPattern = struct {
    relation: []const u8,
    args: []const []const u8, // e.g. ["Holder", "Item"] or ["victim", "_"]
};

pub const Expr = union(enum) {
    roll_gte: struct { count: u8, sides: u8, threshold: u32 },
    not_fact: FactPattern,
    has_fact: FactPattern,
};

pub const Stmt = union(enum) {
    remember: struct {
        relation: []const u8,
        args: []const []const u8,
        ttl_ticks: u32,
    },
    forget: struct {
        relation: []const u8,
        args: []const []const u8,
    },
    walk: struct {
        entity: []const u8,
        target: []const u8,
    },
    face: struct {
        entity: []const u8,
        target: []const u8,
    },
    wait_ticks: u32,
    wait_until: Expr,
    loop_stmt: []const Stmt,
    if_stmt: struct {
        cond: Expr,
        body: []const Stmt,
    },
    interrupt_with: struct {
        entity: []const u8,
        body: []const Stmt,
    },
    say: struct {
        speaker: []const u8,
        text: []const u8,
    },
    animate: struct {
        target: []const u8,
        clip: []const u8,
        is_stop: bool = false,
    },
    transition_scene: struct {
        target_scene: []const u8,
    },
    choice_block: []const DialogueChoice,
    resume_stmt: void,
    /// `weave <Draft> on <Target>`: caster is the executing fiber's owner (P22-01, D-029).
    weave: struct {
        draft: []const u8,
        target: []const u8,
    },
};

/// `draft <Name>(n1, n2, n3, n4) [reverse <Inverse>]` (P22-01, D-029).
pub const DraftDecl = struct {
    name: []const u8,
    notes: Notes,
    reverse_name: ?[]const u8 = null,
};

/// Source position of a `weave` statement, kept so undeclared drafts report where they were used.
const WeaveRef = struct {
    draft: []const u8,
    line: u32,
    column: u32,
};

pub const DialogueChoice = struct {
    text: []const u8,
    guard: ?Expr = null,
    where_patterns: []const FactPattern = &[_]FactPattern{},
    body: []const Stmt,
};

pub const Routine = struct {
    name: []const u8,
    entity: []const u8,
    body: []const Stmt,
};

pub const CueHandler = struct {
    cue_name: []const u8,
    params: []const []const u8,
    where_patterns: []const FactPattern,
    body: []const Stmt,
};

pub const WhenEdge = enum {
    rising, // when Condition: (or when currently Condition:)
    falling, // when Condition stops being State:
    on_expire, // when Entity forgets Relation:
    on_arrive, // when Actor arrives at Mark:
};

/// Relation naming the single trigger pattern of an arrival rule: `ArrivesAt(Actor, Mark)`.
/// It is never asserted as a fact; codegen resolves the mark to a waypoint id (P32-18, D-036).
pub const ARRIVES_RELATION = "ArrivesAt";

pub const WhenRule = struct {
    edge: WhenEdge = .rising,
    trigger_patterns: []const FactPattern,
    body: []const Stmt,
};

pub const RelationDecl = struct {
    name: []const u8,
    is_property: bool,
};

pub const SceneDef = struct {
    name: []const u8,
    cast: std.ArrayList([]const u8),
    props: std.ArrayList([]const u8),
    marks: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) SceneDef {
        return .{
            .name = name,
            .cast = std.ArrayList([]const u8).init(allocator),
            .props = std.ArrayList([]const u8).init(allocator),
            .marks = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *SceneDef) void {
        self.cast.deinit();
        self.props.deinit();
        self.marks.deinit();
    }
};

pub const AST = struct {
    entities: std.ArrayList([]const u8),
    relations: std.ArrayList(RelationDecl),
    initial_stmts: std.ArrayList(Stmt),
    routines: std.ArrayList(Routine),
    cue_handlers: std.ArrayList(CueHandler),
    when_rules: std.ArrayList(WhenRule),
    scenes: std.ArrayList([]const u8),
    scene_defs: std.ArrayList(SceneDef),
    cast: std.ArrayList([]const u8),
    props: std.ArrayList([]const u8),
    marks: std.ArrayList([]const u8),
    drafts: std.ArrayList(DraftDecl),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AST {
        return AST{
            .entities = std.ArrayList([]const u8).init(allocator),
            .relations = std.ArrayList(RelationDecl).init(allocator),
            .initial_stmts = std.ArrayList(Stmt).init(allocator),
            .routines = std.ArrayList(Routine).init(allocator),
            .cue_handlers = std.ArrayList(CueHandler).init(allocator),
            .when_rules = std.ArrayList(WhenRule).init(allocator),
            .scenes = std.ArrayList([]const u8).init(allocator),
            .scene_defs = std.ArrayList(SceneDef).init(allocator),
            .cast = std.ArrayList([]const u8).init(allocator),
            .props = std.ArrayList([]const u8).init(allocator),
            .marks = std.ArrayList([]const u8).init(allocator),
            .drafts = std.ArrayList(DraftDecl).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AST) void {
        self.entities.deinit();
        self.relations.deinit();
        self.initial_stmts.deinit();
        self.routines.deinit();
        self.cue_handlers.deinit();
        self.when_rules.deinit();
        self.scenes.deinit();
        for (self.scene_defs.items) |*sd| {
            sd.deinit();
        }
        self.scene_defs.deinit();
        self.cast.deinit();
        self.props.deinit();
        self.marks.deinit();
        self.drafts.deinit();
    }
};

pub const Diagnostic = struct {
    line: u32,
    column: u32,
    message: []const u8,
};

/// Source position of an arrival rule's mark, kept so undeclared marks report where they were used.
const ArrivalRef = struct {
    mark: []const u8,
    line: u32,
    column: u32,
};

pub const Parser = struct {
    lexer: *Lexer,
    current: Token,
    allocator: std.mem.Allocator,
    diagnostic: ?Diagnostic = null,
    diag_buf: [256]u8 = undefined,
    weave_refs: std.ArrayList(WeaveRef),
    arrival_refs: std.ArrayList(ArrivalRef),

    pub fn init(allocator: std.mem.Allocator, lexer: *Lexer) !Parser {
        var p = Parser{
            .lexer = lexer,
            .current = undefined,
            .allocator = allocator,
            .diagnostic = null,
            .diag_buf = undefined,
            .weave_refs = std.ArrayList(WeaveRef).init(allocator),
            .arrival_refs = std.ArrayList(ArrivalRef).init(allocator),
        };
        try p.advance();
        return p;
    }

    pub fn set_error(self: *Parser, comptime fmt: []const u8, args: anytype) error{UnexpectedToken} {
        const msg = std.fmt.bufPrint(&self.diag_buf, fmt, args) catch "syntax error";
        self.diagnostic = .{
            .line = self.current.line,
            .column = self.current.col,
            .message = msg,
        };
        return error.UnexpectedToken;
    }

    pub fn get_diagnostic(self: *const Parser) ?Diagnostic {
        return self.diagnostic;
    }

    fn advance(self: *Parser) !void {
        self.current = try self.lexer.next();
        // Skip superfluous newlines
        while (self.current.tag == .newline) {
            self.current = try self.lexer.next();
        }
    }

    fn expect(self: *Parser, tag: TokenTag) !Token {
        if (self.current.tag != tag) {
            return self.set_error("expected {s}, found {s} ('{s}')", .{
                @tagName(tag),
                @tagName(self.current.tag),
                self.current.slice,
            });
        }
        const tok = self.current;
        try self.advance();
        return tok;
    }

    fn parse_name(self: *Parser) ![]const u8 {
        const first_tok = try self.expect(.identifier);
        const first = first_tok.slice;
        const line = first_tok.line;
        if ((self.current.tag != .identifier and self.current.tag != .number) or self.current.line != line) {
            return first;
        }
        var buf = std.ArrayList(u8).init(self.allocator);
        try buf.appendSlice(first);
        while ((self.current.tag == .identifier or self.current.tag == .number) and self.current.line == line) {
            try buf.append(' ');
            try buf.appendSlice(self.current.slice);
            try self.advance();
        }
        return try buf.toOwnedSlice();
    }

    pub fn parse_program(self: *Parser) !AST {
        var ast = AST.init(self.allocator);

        while (self.current.tag != .eof) {
            switch (self.current.tag) {
                .kw_entity => {
                    try self.advance(); // consume 'entity'
                    while (true) {
                        const name = (try self.expect(.identifier)).slice;
                        try ast.entities.append(name);
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_relation, .kw_property => {
                    const is_prop = self.current.tag == .kw_property;
                    try self.advance();
                    const name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        _ = try self.advance();
                    }
                    _ = try self.expect(.rparen);
                    try ast.relations.append(.{ .name = name, .is_property = is_prop });
                },
                .kw_remember => {
                    const stmt = try self.parse_remember_stmt();
                    try ast.initial_stmts.append(stmt);
                },
                .kw_transition => {
                    try self.advance(); // consume 'transition'
                    _ = try self.expect(.kw_to);
                    _ = try self.expect(.kw_scene);
                    if (self.current.tag == .colon) try self.advance();
                    const target_scene = try self.parse_name();
                    try ast.initial_stmts.append(.{ .transition_scene = .{ .target_scene = target_scene } });
                },
                .kw_choice => {
                    var choices = std.ArrayList(DialogueChoice).init(self.allocator);
                    while (self.current.tag == .kw_choice) {
                        try self.advance(); // consume 'choice'
                        const text = if (self.current.tag == .string_literal)
                            (try self.expect(.string_literal)).slice
                        else
                            try self.parse_name();
                        var guard: ?Expr = null;
                        if (self.current.tag == .kw_if) {
                            try self.advance();
                            guard = try self.parse_expr();
                        }
                        var where_patterns = std.ArrayList(FactPattern).init(self.allocator);
                        if (self.current.tag == .kw_where) {
                            try self.advance();
                            while (true) {
                                const pat = try self.parse_fact_pattern();
                                try where_patterns.append(pat);
                                if (self.current.tag == .kw_and) {
                                    try self.advance();
                                } else break;
                            }
                        }
                        _ = try self.expect(.colon);
                        _ = try self.expect(.indent);
                        const body = try self.parse_stmt_list();
                        _ = try self.expect(.dedent);
                        try choices.append(.{
                            .text = text,
                            .guard = guard,
                            .where_patterns = try where_patterns.toOwnedSlice(),
                            .body = body,
                        });
                    }
                    try ast.initial_stmts.append(.{ .choice_block = try choices.toOwnedSlice() });
                },
                .kw_draft => {
                    const decl = try self.parse_draft_decl(ast.drafts.items);
                    try ast.drafts.append(decl);
                    try ast.entities.append(decl.name);
                    if (decl.reverse_name) |rn| try ast.entities.append(rn);
                },
                .kw_weave => {
                    return self.set_error("'weave' must appear inside a routine, cue, or rule body; it needs a caster", .{});
                },
                .kw_routine => {
                    try self.advance();
                    const name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    const entity = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.rparen);
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);

                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.routines.append(.{
                        .name = name,
                        .entity = entity,
                        .body = body,
                    });
                },
                .kw_on => {
                    try self.advance(); // consume 'on'
                    _ = try self.expect(.kw_cue);
                    const cue_name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    var params = std.ArrayList([]const u8).init(self.allocator);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        try params.append(self.current.slice);
                        try self.advance();
                        if (self.current.tag == .comma) try self.advance();
                    }
                    if (params.items.len == 0) {
                        return self.set_error("a cue handler needs an actor parameter", .{});
                    }
                    _ = try self.expect(.rparen);

                    var where_patterns = std.ArrayList(FactPattern).init(self.allocator);
                    if (self.current.tag == .kw_where) {
                        try self.advance();
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try where_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.cue_handlers.append(.{
                        .cue_name = cue_name,
                        .params = try params.toOwnedSlice(),
                        .where_patterns = try where_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_verb => {
                    try self.advance(); // consume 'verb' (P7-02, D-009)
                    const verb_name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    var params = std.ArrayList([]const u8).init(self.allocator);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        try params.append(self.current.slice);
                        try self.advance();
                        if (self.current.tag == .comma) try self.advance();
                    }
                    if (params.items.len == 0) {
                        return self.set_error("a cue handler needs an actor parameter", .{});
                    }
                    _ = try self.expect(.rparen);

                    var where_patterns = std.ArrayList(FactPattern).init(self.allocator);
                    if (self.current.tag == .kw_where) {
                        try self.advance();
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try where_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.cue_handlers.append(.{
                        .cue_name = verb_name,
                        .params = try params.toOwnedSlice(),
                        .where_patterns = try where_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_when => {
                    try self.advance();
                    var edge: WhenEdge = .rising;
                    if (self.current.tag == .kw_currently) {
                        try self.advance();
                    }
                    var trigger_patterns = std.ArrayList(FactPattern).init(self.allocator);

                    if (self.current.tag == .identifier) {
                        const first_name = try self.parse_name();
                        if (self.current.tag == .kw_forgets) {
                            try self.advance();
                            const rel_name = try self.parse_name();
                            edge = .on_expire;
                            var pat_args = try self.allocator.alloc([]const u8, 2);
                            pat_args[0] = first_name;
                            pat_args[1] = "_";
                            try trigger_patterns.append(.{
                                .relation = rel_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_arrives) {
                            try self.advance();
                            // `at` stays an ordinary word so names may still contain it.
                            if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.slice, "at")) {
                                return self.set_error("expected 'at' after 'arrives', found '{s}'", .{self.current.slice});
                            }
                            try self.advance();
                            const mark_tok = self.current;
                            const mark_name = try self.parse_name();
                            try self.arrival_refs.append(.{ .mark = mark_name, .line = mark_tok.line, .column = mark_tok.col });
                            edge = .on_arrive;
                            var pat_args = try self.allocator.alloc([]const u8, 2);
                            pat_args[0] = first_name;
                            pat_args[1] = mark_name;
                            try trigger_patterns.append(.{
                                .relation = ARRIVES_RELATION,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_stops) {
                            try self.advance();
                            if (self.current.tag == .kw_being) try self.advance();
                            const state_name = try self.parse_name();
                            edge = .falling;
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = state_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                            try self.advance();
                            const state_name = try self.parse_name();
                            edge = .rising;
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = state_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .lparen or self.current.tag == .lbracket) {
                            const pat = try self.finish_fact_pattern(first_name);
                            try trigger_patterns.append(pat);
                            while (self.current.tag == .kw_and) {
                                try self.advance();
                                try trigger_patterns.append(try self.parse_fact_pattern());
                            }
                        } else {
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = first_name,
                                .args = pat_args,
                            });
                        }
                    } else {
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try trigger_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.when_rules.append(.{
                        .edge = edge,
                        .trigger_patterns = try trigger_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_scene => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    const name = try self.parse_name();
                    try ast.scenes.append(name);
                    try ast.entities.append(name);
                    try ast.scene_defs.append(SceneDef.init(self.allocator, name));
                },
                .kw_cast => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.cast.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].cast.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_props => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.props.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].props.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_marks => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.marks.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].marks.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_during => {
                    try self.advance();
                    const name = try self.parse_name();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try ast.routines.append(.{
                        .name = name,
                        .entity = name,
                        .body = body,
                    });
                },
                .kw_now => {
                    const stmt = try self.parse_now_stmt();
                    try ast.initial_stmts.append(stmt);
                },
                .identifier => {
                    const ident = try self.parse_name();
                    if (self.current.tag == .kw_with) {
                        _ = try self.advance();
                    }
                    if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                        try self.advance();
                        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "a")) {
                            try self.advance();
                            if (self.current.tag == .kw_state) {
                                const state_line = self.current.line;
                                try self.advance();
                                try ast.relations.append(.{ .name = ident, .is_property = false });
                                while (self.current.line == state_line and self.current.tag != .eof) {
                                    try self.advance();
                                }
                                continue;
                            }
                        }
                        const stmt = try self.finish_state_stmt(ident);
                        try ast.initial_stmts.append(stmt);
                    }
                },
                else => {
                    _ = try self.advance();
                },
            }
        }

        // Every woven draft must be declared somewhere in the program (P22-01, D-029).
        for (self.weave_refs.items) |ref| {
            if (!draft_declared(ast.drafts.items, ref.draft)) {
                const msg = std.fmt.bufPrint(&self.diag_buf, "weave of undeclared draft '{s}'", .{ref.draft}) catch "weave of undeclared draft";
                self.diagnostic = .{ .line = ref.line, .column = ref.column, .message = msg };
                return error.UnexpectedToken;
            }
        }

        // An arrival rule must name a declared mark: an unknown one could never fire (D-036).
        for (self.arrival_refs.items) |ref| {
            if (!mark_declared(&ast, ref.mark)) {
                const msg = std.fmt.bufPrint(&self.diag_buf, "arrival at undeclared mark '{s}'", .{ref.mark}) catch "arrival at undeclared mark";
                self.diagnostic = .{ .line = ref.line, .column = ref.column, .message = msg };
                return error.UnexpectedToken;
            }
        }

        return ast;
    }

    fn mark_declared(ast: *const AST, name: []const u8) bool {
        for (ast.marks.items) |m| {
            if (std.mem.eql(u8, m, name)) return true;
        }
        for (ast.scene_defs.items) |scene| {
            for (scene.marks.items) |m| {
                if (std.mem.eql(u8, m, name)) return true;
            }
        }
        return false;
    }

    /// Parses `draft <Name>(n1, n2, n3, n4) [reverse <Inverse>]` and rejects any sequence that
    /// would make note lookup ambiguous: a played sequence must name exactly one draft, read in
    /// either direction, so `VM.weave_notes` never needs a tie-break (D-029).
    fn parse_draft_decl(self: *Parser, prior: []const DraftDecl) !DraftDecl {
        try self.advance(); // consume 'draft'
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.lparen);
        var notes: Notes = undefined;
        var count: usize = 0;
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            if (count == notes.len) {
                return self.set_error("draft '{s}' has more than {d} notes", .{ name, notes.len });
            }
            const tok = try self.expect(.identifier);
            notes[count] = Note.from_name(tok.slice) orelse {
                return self.set_error("unknown note '{s}' in draft '{s}'; expected one of C D E F G A B", .{ tok.slice, name });
            };
            count += 1;
            if (self.current.tag == .comma) try self.advance();
        }
        if (count != notes.len) {
            return self.set_error("draft '{s}' has {d} notes; drafts have exactly {d}", .{ name, count, notes.len });
        }
        _ = try self.expect(.rparen);

        var reverse_name: ?[]const u8 = null;
        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "reverse")) {
            try self.advance();
            reverse_name = (try self.expect(.identifier)).slice;
        }

        if (reverse_name) |rn| {
            if (std.mem.eql(u8, rn, name)) {
                return self.set_error("draft '{s}' cannot be its own reverse", .{name});
            }
            if (draft_mod.is_palindrome(notes)) {
                return self.set_error("draft '{s}' is a palindrome; its reverse '{s}' would play the same notes", .{ name, rn });
            }
        }

        for (prior) |p| {
            const new_names = [_]?[]const u8{ name, reverse_name };
            for (new_names) |maybe_new| {
                const nn = maybe_new orelse continue;
                if (std.mem.eql(u8, nn, p.name) or (p.reverse_name != null and std.mem.eql(u8, nn, p.reverse_name.?))) {
                    return self.set_error("draft name '{s}' is already declared", .{nn});
                }
            }
            if (draft_mod.notes_eql(notes, p.notes) or draft_mod.notes_eql(notes, draft_mod.reversed(p.notes))) {
                return self.set_error("draft '{s}' plays the same notes as draft '{s}' (forward or reversed)", .{ name, p.name });
            }
        }

        return .{ .name = name, .notes = notes, .reverse_name = reverse_name };
    }

    fn draft_declared(drafts: []const DraftDecl, name: []const u8) bool {
        for (drafts) |d| {
            if (std.mem.eql(u8, d.name, name)) return true;
            if (d.reverse_name) |rn| if (std.mem.eql(u8, rn, name)) return true;
        }
        return false;
    }

    fn parse_stmt_list(self: *Parser) ![]const Stmt {
        var list = std.ArrayList(Stmt).init(self.allocator);

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            switch (self.current.tag) {
                .kw_remember => {
                    try list.append(try self.parse_remember_stmt());
                },
                .kw_forget => {
                    try self.advance();
                    const pat = try self.parse_fact_pattern();
                    try list.append(.{ .forget = .{
                        .relation = pat.relation,
                        .args = pat.args,
                    } });
                },
                .kw_now => {
                    try list.append(try self.parse_now_stmt());
                },
                .kw_transition => {
                    try self.advance(); // consume 'transition'
                    _ = try self.expect(.kw_to);
                    _ = try self.expect(.kw_scene);
                    if (self.current.tag == .colon) try self.advance();
                    const target_scene = try self.parse_name();
                    try list.append(.{ .transition_scene = .{ .target_scene = target_scene } });
                },
                .kw_choice => {
                    var choices = std.ArrayList(DialogueChoice).init(self.allocator);
                    while (self.current.tag == .kw_choice) {
                        try self.advance(); // consume 'choice'
                        const text = if (self.current.tag == .string_literal)
                            (try self.expect(.string_literal)).slice
                        else
                            try self.parse_name();
                        var guard: ?Expr = null;
                        if (self.current.tag == .kw_if) {
                            try self.advance();
                            guard = try self.parse_expr();
                        }
                        var where_patterns = std.ArrayList(FactPattern).init(self.allocator);
                        if (self.current.tag == .kw_where) {
                            try self.advance();
                            while (true) {
                                const pat = try self.parse_fact_pattern();
                                try where_patterns.append(pat);
                                if (self.current.tag == .kw_and) {
                                    try self.advance();
                                } else break;
                            }
                        }
                        _ = try self.expect(.colon);
                        _ = try self.expect(.indent);
                        const body = try self.parse_stmt_list();
                        _ = try self.expect(.dedent);
                        try choices.append(.{
                            .text = text,
                            .guard = guard,
                            .where_patterns = try where_patterns.toOwnedSlice(),
                            .body = body,
                        });
                    }
                    try list.append(.{ .choice_block = try choices.toOwnedSlice() });
                },
                .kw_walk => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_to);
                    const target = try self.parse_name();
                    try list.append(.{ .walk = .{ .entity = ent, .target = target } });
                },
                .kw_face => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_toward);
                    const target = try self.parse_name();
                    try list.append(.{ .face = .{ .entity = ent, .target = target } });
                },
                .kw_wait => {
                    try self.advance();
                    if (self.current.tag == .number) {
                        const num_str = self.current.slice;
                        try self.advance();
                        _ = try self.expect(.kw_ticks);
                        const ticks = try std.fmt.parseInt(u32, num_str, 10);
                        try list.append(.{ .wait_ticks = ticks });
                    } else if (self.current.tag == .kw_until) {
                        try self.advance();
                        const expr = try self.parse_expr();
                        try list.append(.{ .wait_until = expr });
                    }
                },
                .kw_loop => {
                    try self.advance();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const loop_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .loop_stmt = loop_body });
                },
                .kw_if => {
                    try self.advance();
                    const cond = try self.parse_expr();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const if_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .if_stmt = .{ .cond = cond, .body = if_body } });
                },
                .kw_interrupt => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_with);
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const int_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .interrupt_with = .{ .entity = ent, .body = int_body } });
                },
                .kw_say => {
                    try self.advance(); // consume 'say' (P7-04, D-009)
                    const speaker = try self.parse_name();
                    if (self.current.tag == .kw_to) {
                        try self.advance();
                        _ = try self.parse_name();
                    }
                    _ = try self.expect(.colon);
                    const text = if (self.current.tag == .string_literal)
                        (try self.expect(.string_literal)).slice
                    else if (self.current.tag == .lparen) blk: {
                        try self.advance();
                        var paren_buf = std.ArrayList(u8).init(self.allocator);
                        while (self.current.tag != .rparen and self.current.tag != .eof) {
                            if (paren_buf.items.len > 0) try paren_buf.append(' ');
                            try paren_buf.appendSlice(self.current.slice);
                            try self.advance();
                        }
                        if (self.current.tag == .rparen) try self.advance();
                        break :blk try paren_buf.toOwnedSlice();
                    } else (try self.parse_name());
                    try list.append(.{ .say = .{ .speaker = speaker, .text = text } });
                },
                .kw_animate => {
                    try self.advance();
                    if (self.current.tag == .lparen) {
                        try self.advance();
                        const target = try self.parse_name();
                        _ = try self.expect(.comma);
                        const clip = try self.parse_name();
                        _ = try self.expect(.rparen);
                        try list.append(.{ .animate = .{ .target = target, .clip = clip, .is_stop = false } });
                    } else {
                        const clip = try self.parse_name();
                        try list.append(.{ .animate = .{ .target = "Scene", .clip = clip, .is_stop = false } });
                    }
                },
                .kw_stop => {
                    try self.advance();
                    _ = try self.expect(.kw_animate);
                    const clip = try self.parse_name();
                    try list.append(.{ .animate = .{ .target = "Scene", .clip = clip, .is_stop = true } });
                },
                .kw_resume => {
                    try self.advance();
                    while (self.current.tag == .identifier) {
                        _ = try self.parse_name();
                    }
                    try list.append(.{ .resume_stmt = {} });
                },
                .kw_done => {
                    try self.advance();
                    try list.append(.{ .resume_stmt = {} });
                },
                .kw_weave => {
                    try self.advance(); // consume 'weave'
                    const draft_tok = self.current;
                    const draft_name = try self.parse_name();
                    _ = try self.expect(.kw_on);
                    const target = try self.parse_name();
                    try self.weave_refs.append(.{ .draft = draft_name, .line = draft_tok.line, .column = draft_tok.col });
                    try list.append(.{ .weave = .{ .draft = draft_name, .target = target } });
                },
                .identifier => {
                    const subj = try self.parse_name();
                    if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                        try self.advance();
                        const stmt = try self.finish_state_stmt(subj);
                        try list.append(stmt);
                    }
                },
                else => {
                    _ = try self.advance();
                },
            }
        }

        return try list.toOwnedSlice();
    }

    fn parse_now_stmt(self: *Parser) !Stmt {
        try self.advance(); // consume 'now'
        const target = try self.parse_name();
        if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
            try self.advance();
        }
        return self.finish_state_stmt(target);
    }

    fn finish_state_stmt(self: *Parser, target: []const u8) !Stmt {
        var is_neg = false;
        if (self.current.tag == .kw_not) {
            is_neg = true;
            try self.advance();
        }
        const state = try self.parse_name();
        if (self.current.tag == .kw_with) {
            try self.advance();
        }
        if (self.current.tag == .kw_in) {
            try self.advance();
            if (self.current.tag == .kw_the) try self.advance();
            if (self.current.tag == .identifier or self.current.tag == .kw_scene) _ = try self.advance();
        }
        var args = try self.allocator.alloc([]const u8, 1);
        args[0] = target;
        if (is_neg) {
            return Stmt{
                .forget = .{
                    .relation = state,
                    .args = args,
                },
            };
        } else {
            return Stmt{
                .remember = .{
                    .relation = state,
                    .args = args,
                    .ttl_ticks = 0,
                },
            };
        }
    }

    fn parse_remember_stmt(self: *Parser) !Stmt {
        try self.advance(); // consume 'remember'
        if (self.current.tag == .colon) try self.advance();
        const pat = try self.parse_fact_pattern();
        var ttl: u32 = 0;
        if (self.current.tag == .kw_for) {
            try self.advance();
            const num_tok = try self.expect(.number);
            _ = try self.expect(.kw_ticks);
            ttl = try std.fmt.parseInt(u32, num_tok.slice, 10);
        }
        return Stmt{
            .remember = .{
                .relation = pat.relation,
                .args = pat.args,
                .ttl_ticks = ttl,
            },
        };
    }

    fn finish_fact_pattern(self: *Parser, rel_name: []const u8) !FactPattern {
        const is_bracket = self.current.tag == .lbracket;
        if (is_bracket) {
            try self.advance();
        } else {
            _ = try self.expect(.lparen);
        }
        var args = std.ArrayList([]const u8).init(self.allocator);
        const end_tag = if (is_bracket) TokenTag.rbracket else TokenTag.rparen;
        while (self.current.tag != end_tag and self.current.tag != .eof) {
            try args.append(self.current.slice);
            try self.advance();
            if (self.current.tag == .comma) try self.advance();
        }
        _ = try self.expect(end_tag);

        return FactPattern{
            .relation = rel_name,
            .args = try args.toOwnedSlice(),
        };
    }

    fn parse_fact_pattern(self: *Parser) !FactPattern {
        const rel_name = (try self.expect(.identifier)).slice;
        return self.finish_fact_pattern(rel_name);
    }

    fn parse_expr(self: *Parser) !Expr {
        if (self.current.tag == .kw_roll) {
            try self.advance();
            const dice_tok = try self.expect(.dice); // e.g. "2d6"
            // Parse "2d6"
            var it = std.mem.splitScalar(u8, dice_tok.slice, 'd');
            const count_str = it.next() orelse "1";
            const sides_str = it.next() orelse "6";
            const count = try std.fmt.parseInt(u8, count_str, 10);
            const sides = try std.fmt.parseInt(u8, sides_str, 10);

            _ = try self.expect(.gte);
            const num_tok = try self.expect(.number);
            const thresh = try std.fmt.parseInt(u32, num_tok.slice, 10);
            return Expr{ .roll_gte = .{ .count = count, .sides = sides, .threshold = thresh } };
        } else if (self.current.tag == .kw_not) {
            try self.advance();
            const pat = try self.parse_fact_pattern();
            return Expr{ .not_fact = pat };
        } else if (self.current.tag == .identifier) {
            const first = try self.parse_name();
            if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                try self.advance();
                var is_neg = false;
                if (self.current.tag == .kw_not) {
                    is_neg = true;
                    try self.advance();
                }
                const state = try self.parse_name();
                if (self.current.tag == .kw_with) try self.advance();
                var pat_args = try self.allocator.alloc([]const u8, 1);
                pat_args[0] = first;
                if (is_neg) {
                    return Expr{ .not_fact = .{ .relation = state, .args = pat_args } };
                } else {
                    return Expr{ .has_fact = .{ .relation = state, .args = pat_args } };
                }
            } else if (self.current.tag == .kw_say) {
                try self.advance(); // e.g. "Hero says 'Hello!'"
                const txt = if (self.current.tag == .string_literal)
                    (try self.expect(.string_literal)).slice
                else
                    try self.parse_name();
                var pat_args = try self.allocator.alloc([]const u8, 2);
                pat_args[0] = first;
                pat_args[1] = txt;
                return Expr{ .has_fact = .{ .relation = "Said", .args = pat_args } };
            } else {
                const pat = try self.finish_fact_pattern(first);
                return Expr{ .has_fact = pat };
            }
        } else {
            const pat = try self.parse_fact_pattern();
            return Expr{ .has_fact = pat };
        }
    }
};

test "P4-02: parser parses complete tavern heist AST" {
    const testing = std.testing;
    const script =
        \\entity Guard, Bard, Cat, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  loop:
        \\    walk Guard to Cellar
        \\    wait 120 ticks
        \\
        \\on cue PlayLute(Bard, target):
        \\  if roll 2d6 >= 8:
        \\    remember CharmedBy(target, Bard) for 180 ticks
        \\
        \\when CharmedBy(listener, musician):
        \\  interrupt listener with:
        \\    face listener toward musician
        \\    wait until not CharmedBy(listener, musician)
        \\
        \\on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
        \\  forget Carries(victim, loot)
        \\  remember Carries(Cat, loot)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();
    _ = &ast;

    try testing.expectEqual(@as(usize, 4), ast.entities.items.len);
    try testing.expectEqual(@as(usize, 2), ast.relations.items.len);
    try testing.expectEqual(@as(usize, 1), ast.initial_stmts.items.len);
    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    try testing.expectEqual(@as(usize, 2), ast.cue_handlers.items.len);
    try testing.expectEqual(@as(usize, 1), ast.when_rules.items.len);
}

test "P8-01: multi-clause when rule parsing" {
    const testing = std.testing;
    const script =
        \\entity Guard, Bard, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\when Carries(Guard, Cheese) and CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    face Guard toward Bard
        \\    wait 10 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.when_rules.items.len);
    const rule = ast.when_rules.items[0];
    try testing.expectEqual(@as(usize, 2), rule.trigger_patterns.len);
    try testing.expectEqualStrings("Carries", rule.trigger_patterns[0].relation);
    try testing.expectEqualStrings("CharmedBy", rule.trigger_patterns[1].relation);
}

test "P10-01: parser parses stageplay taxonomy, state declarations, and falling-edge/expiration rules" {
    const testing = std.testing;
    const script =
        \\scene: Spitting Competition
        \\cast: Guybrush, Organiser, Onlookers
        \\props: Flags
        \\marks: Starting Line, Looking Offstage
        \\
        \\Tampered with is a state, which can be tampered with or not tampered with.
        \\Distracted is a state, which can be distracted or not distracted.
        \\
        \\remember: Carries(Guybrush, Horn) ~ inline comment
        \\now Flags are tampered with
        \\
        \\routine EggingCrowd(Organiser):
        \\  loop:
        \\    walk Organiser to Onlookers
        \\    say Organiser to Onlookers: "Come on!"
        \\    wait 30 ticks
        \\
        \\when currently Wind is blowing:
        \\  interrupt Organiser with:
        \\    animate wind-blowing
        \\
        \\when Wind stops being blowing:
        \\  interrupt Organiser with:
        \\    stop animate wind-blowing
        \\
        \\when Organiser forgets Distracted:
        \\  interrupt Organiser with:
        \\    walk Organiser to Starting Line
        \\    resume previous action
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.scenes.items.len);
    try testing.expectEqualStrings("Spitting Competition", ast.scenes.items[0]);

    try testing.expectEqual(@as(usize, 3), ast.cast.items.len);
    try testing.expectEqualStrings("Guybrush", ast.cast.items[0]);
    try testing.expectEqualStrings("Organiser", ast.cast.items[1]);
    try testing.expectEqualStrings("Onlookers", ast.cast.items[2]);

    try testing.expectEqual(@as(usize, 1), ast.props.items.len);
    try testing.expectEqualStrings("Flags", ast.props.items[0]);

    try testing.expectEqual(@as(usize, 2), ast.marks.items.len);
    try testing.expectEqualStrings("Starting Line", ast.marks.items[0]);
    try testing.expectEqualStrings("Looking Offstage", ast.marks.items[1]);

    try testing.expectEqual(@as(usize, 3), ast.when_rules.items.len);
    try testing.expectEqual(WhenEdge.rising, ast.when_rules.items[0].edge);
    try testing.expectEqual(WhenEdge.falling, ast.when_rules.items[1].edge);
    try testing.expectEqual(WhenEdge.on_expire, ast.when_rules.items[2].edge);
}

test "P12-01: parser parses scene transition statements" {
    const testing = std.testing;
    const script =
        \\scene: Tavern
        \\cast: Guybrush
        \\transition to scene: Wine Cellar
        \\
        \\routine EnterCellar(Guybrush):
        \\  transition to scene Wine Cellar
        \\  wait 10 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    // Verify top-level initial transition statement
    try testing.expectEqual(@as(usize, 1), ast.initial_stmts.items.len);
    switch (ast.initial_stmts.items[0]) {
        .transition_scene => |ts| try testing.expectEqualStrings("Wine Cellar", ts.target_scene),
        else => try testing.expect(false),
    }

    // Verify routine statement transition
    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const routine = ast.routines.items[0];
    try testing.expectEqualStrings("EnterCellar", routine.name);
    try testing.expectEqual(@as(usize, 2), routine.body.len);
    switch (routine.body[0]) {
        .transition_scene => |ts| try testing.expectEqualStrings("Wine Cellar", ts.target_scene),
        else => try testing.expect(false),
    }
}

test "P12-02: parser groups multiple scenes with scoped cast, props, and marks" {
    const testing = std.testing;
    const script =
        \\scene: Tavern
        \\cast: Guybrush, Barkeep
        \\props: Mug
        \\marks: Hearth, Counter
        \\
        \\scene: Wine Cellar
        \\cast: Guard
        \\props: Cask
        \\marks: CaskMark, SecretDoor
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.scene_defs.items.len);

    const s1 = ast.scene_defs.items[0];
    try testing.expectEqualStrings("Tavern", s1.name);
    try testing.expectEqual(@as(usize, 2), s1.cast.items.len);
    try testing.expectEqualStrings("Guybrush", s1.cast.items[0]);
    try testing.expectEqualStrings("Barkeep", s1.cast.items[1]);
    try testing.expectEqual(@as(usize, 1), s1.props.items.len);
    try testing.expectEqualStrings("Mug", s1.props.items[0]);
    try testing.expectEqual(@as(usize, 2), s1.marks.items.len);
    try testing.expectEqualStrings("Hearth", s1.marks.items[0]);
    try testing.expectEqualStrings("Counter", s1.marks.items[1]);

    const s2 = ast.scene_defs.items[1];
    try testing.expectEqualStrings("Wine Cellar", s2.name);
    try testing.expectEqual(@as(usize, 1), s2.cast.items.len);
    try testing.expectEqualStrings("Guard", s2.cast.items[0]);
    try testing.expectEqual(@as(usize, 1), s2.props.items.len);
    try testing.expectEqualStrings("Cask", s2.props.items[0]);
    try testing.expectEqual(@as(usize, 2), s2.marks.items.len);
    try testing.expectEqualStrings("CaskMark", s2.marks.items[0]);
    try testing.expectEqualStrings("SecretDoor", s2.marks.items[1]);
}

test "P13-01: parser parses conditionally guarded dialogue choice blocks" {
    const testing = std.testing;
    const script =
        \\routine TalkToButhane(Gabriel):
        \\  choice "I'd like to rent a motorcycle." if Carries(Gabriel, License):
        \\    say Buthane: "Here are the keys."
        \\  choice "Do you know whose cat that is?" if not KnowsAboutCat(Gabriel):
        \\    say Buthane: "It belongs to the rector."
        \\    remember KnowsAboutCat(Gabriel, true)
        \\  choice "Just browsing, thanks.":
        \\    say Buthane: "Bonne journée!"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const r = ast.routines.items[0];
    try testing.expectEqualStrings("TalkToButhane", r.name);
    try testing.expectEqual(@as(usize, 1), r.body.len);

    switch (r.body[0]) {
        .choice_block => |choices| {
            try testing.expectEqual(@as(usize, 3), choices.len);

            // Choice 0: Carries(Gabriel, License) guard
            try testing.expectEqualStrings("I'd like to rent a motorcycle.", choices[0].text);
            try testing.expect(choices[0].guard != null);
            switch (choices[0].guard.?) {
                .has_fact => |pat| {
                    try testing.expectEqualStrings("Carries", pat.relation);
                    try testing.expectEqual(@as(usize, 2), pat.args.len);
                    try testing.expectEqualStrings("Gabriel", pat.args[0]);
                    try testing.expectEqualStrings("License", pat.args[1]);
                },
                else => try testing.expect(false),
            }
            try testing.expectEqual(@as(usize, 1), choices[0].body.len);

            // Choice 1: not KnowsAboutCat(Gabriel) guard
            try testing.expectEqualStrings("Do you know whose cat that is?", choices[1].text);
            try testing.expect(choices[1].guard != null);
            switch (choices[1].guard.?) {
                .not_fact => |pat| {
                    try testing.expectEqualStrings("KnowsAboutCat", pat.relation);
                    try testing.expectEqual(@as(usize, 1), pat.args.len);
                    try testing.expectEqualStrings("Gabriel", pat.args[0]);
                },
                else => try testing.expect(false),
            }
            try testing.expectEqual(@as(usize, 2), choices[1].body.len);

            // Choice 2: unconditional
            try testing.expectEqualStrings("Just browsing, thanks.", choices[2].text);
            try testing.expect(choices[2].guard == null);
            try testing.expectEqual(@as(usize, 1), choices[2].body.len);
        },
        else => try testing.expect(false),
    }
}

test "P13-01: parser parses relational where-clause guarded dialogue choices" {
    const testing = std.testing;
    const script =
        \\routine InsultDuel(Guybrush):
        \\  choice "How appropriate. You fight like a cow!" where MasteredReply(Guybrush, ReplyCow) and Counters(ReplyCow, InsultFarmer):
        \\    say Guybrush: "How appropriate. You fight like a cow!"
        \\  choice "I am shaking, I am shaking!":
        \\    say Guybrush: "I am shaking, I am shaking!"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    var ast = try parser.parse_program();
    defer ast.deinit();

    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const r = ast.routines.items[0];
    switch (r.body[0]) {
        .choice_block => |choices| {
            try testing.expectEqual(@as(usize, 2), choices.len);
            try testing.expectEqualStrings("How appropriate. You fight like a cow!", choices[0].text);
            try testing.expectEqual(@as(usize, 2), choices[0].where_patterns.len);
            try testing.expectEqualStrings("MasteredReply", choices[0].where_patterns[0].relation);
            try testing.expectEqualStrings("Counters", choices[0].where_patterns[1].relation);
            try testing.expectEqualStrings("I am shaking, I am shaking!", choices[1].text);
            try testing.expectEqual(@as(usize, 0), choices[1].where_patterns.len);
        },
        else => try testing.expect(false),
    }
}

test "P15-03: parser captures accurate line and column diagnostics on syntax errors" {
    const testing = std.testing;
    const invalid_script =
        \\routine Patrol Guard):
        \\  walk Guard to Cellar
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, invalid_script);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    const result = parser.parse_program();
    try testing.expectError(error.UnexpectedToken, result);

    const diag = parser.get_diagnostic();
    try testing.expect(diag != null);
    try testing.expectEqual(@as(u32, 1), diag.?.line);
    try testing.expectEqual(@as(u32, 16), diag.?.column);
    try testing.expect(std.mem.indexOf(u8, diag.?.message, "expected lparen") != null);
}

fn expect_draft_error(source: []const u8, needle: []const u8, line: u32) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    try testing.expectError(error.UnexpectedToken, parser.parse_program());
    const diag = parser.get_diagnostic().?;
    if (std.mem.indexOf(u8, diag.message, needle) == null) {
        std.debug.print("diagnostic was: {s}\n", .{diag.message});
        return error.TestUnexpectedResult;
    }
    try testing.expectEqual(line, diag.line);
}

test "P22-01: parser parses draft declarations with reverse and weave statements" {
    const testing = std.testing;
    const source =
        \\entity Player, Brazier
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Mend(D, A, A, D)
        \\routine Ritual(Player):
        \\  weave Kindle on Brazier
        \\  weave Douse on Brazier
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.drafts.items.len);
    const kindle = ast.drafts.items[0];
    try testing.expectEqualStrings("Kindle", kindle.name);
    try testing.expectEqualStrings("Douse", kindle.reverse_name.?);
    try testing.expect(std.mem.eql(Note, &kindle.notes, &[_]Note{ .C, .E, .G, .E }));
    try testing.expect(ast.drafts.items[1].reverse_name == null);

    const body = ast.routines.items[0].body;
    try testing.expectEqual(@as(usize, 2), body.len);
    try testing.expectEqualStrings("Kindle", body[0].weave.draft);
    try testing.expectEqualStrings("Brazier", body[0].weave.target);
    try testing.expectEqualStrings("Douse", body[1].weave.draft);
}

test "P22-01: parser rejects malformed and ambiguous drafts with located diagnostics" {
    try expect_draft_error("draft Kindle(C, E, H, E)", "unknown note 'H'", 1);
    try expect_draft_error("draft Kindle(C, E, G)", "has 3 notes", 1);
    try expect_draft_error("draft Kindle(C, E, G, E, C)", "more than 4 notes", 1);
    try expect_draft_error("draft Mend(D, A, A, D) reverse Rend", "palindrome", 1);
    try expect_draft_error("draft Kindle(C, E, G, E) reverse Kindle", "its own reverse", 1);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E)
        \\draft Ember(E, G, E, C)
    , "same notes as draft 'Kindle'", 2);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Douse(F, F, G, A)
    , "already declared", 2);
}

test "P22-01: parser rejects weaving undeclared drafts and top-level weaves" {
    try expect_draft_error(
        \\entity Player, Brazier
        \\routine Ritual(Player):
        \\  wait 1 ticks
        \\  weave Kindle on Brazier
    , "undeclared draft 'Kindle'", 4);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E)
        \\weave Kindle on Brazier
    , "inside a routine", 2);
}
