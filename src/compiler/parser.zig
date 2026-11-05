const std = @import("std");
const lexer_mod = @import("lexer.zig");
pub const Lexer = lexer_mod.Lexer;
pub const Token = lexer_mod.Token;
pub const TokenTag = lexer_mod.TokenTag;

pub const FactPattern = struct {
    relation: []const u8,
    args: []const []const u8, // e.g. ["Guard", "Cheese"] or ["victim", "_"]
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

pub const WhenRule = struct {
    trigger_pattern: FactPattern,
    body: []const Stmt,
};

pub const RelationDecl = struct {
    name: []const u8,
    is_property: bool,
};

pub const AST = struct {
    entities: std.ArrayList([]const u8),
    relations: std.ArrayList(RelationDecl),
    initial_stmts: std.ArrayList(Stmt),
    routines: std.ArrayList(Routine),
    cue_handlers: std.ArrayList(CueHandler),
    when_rules: std.ArrayList(WhenRule),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AST {
        return AST{
            .entities = std.ArrayList([]const u8).init(allocator),
            .relations = std.ArrayList(RelationDecl).init(allocator),
            .initial_stmts = std.ArrayList(Stmt).init(allocator),
            .routines = std.ArrayList(Routine).init(allocator),
            .cue_handlers = std.ArrayList(CueHandler).init(allocator),
            .when_rules = std.ArrayList(WhenRule).init(allocator),
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
    }
};

pub const Parser = struct {
    lexer: *Lexer,
    current: Token,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, lexer: *Lexer) !Parser {
        var p = Parser{
            .lexer = lexer,
            .current = undefined,
            .allocator = allocator,
        };
        try p.advance();
        return p;
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
            return error.UnexpectedToken;
        }
        const tok = self.current;
        try self.advance();
        return tok;
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
                .kw_when => {
                    try self.advance();
                    const pat = try self.parse_fact_pattern();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.when_rules.append(.{
                        .trigger_pattern = pat,
                        .body = body,
                    });
                },
                else => {
                    _ = try self.advance();
                },
            }
        }

        return ast;
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
                .kw_walk => {
                    try self.advance();
                    const ent = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.kw_to);
                    const target = (try self.expect(.identifier)).slice;
                    try list.append(.{ .walk = .{ .entity = ent, .target = target } });
                },
                .kw_face => {
                    try self.advance();
                    const ent = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.kw_toward);
                    const target = (try self.expect(.identifier)).slice;
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
                    const ent = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.kw_with);
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const int_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .interrupt_with = .{ .entity = ent, .body = int_body } });
                },
                else => {
                    _ = try self.advance();
                },
            }
        }

        return try list.toOwnedSlice();
    }

    fn parse_remember_stmt(self: *Parser) !Stmt {
        try self.advance(); // consume 'remember'
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

    fn parse_fact_pattern(self: *Parser) !FactPattern {
        const rel_name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.lparen);
        var args = std.ArrayList([]const u8).init(self.allocator);
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            try args.append(self.current.slice);
            try self.advance();
            if (self.current.tag == .comma) try self.advance();
        }
        _ = try self.expect(.rparen);

        return FactPattern{
            .relation = rel_name,
            .args = try args.toOwnedSlice(),
        };
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
    var ast = try parser.parse_program();
    _ = &ast;

    try testing.expectEqual(@as(usize, 4), ast.entities.items.len);
    try testing.expectEqual(@as(usize, 2), ast.relations.items.len);
    try testing.expectEqual(@as(usize, 1), ast.initial_stmts.items.len);
    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    try testing.expectEqual(@as(usize, 2), ast.cue_handlers.items.len);
    try testing.expectEqual(@as(usize, 1), ast.when_rules.items.len);
}
