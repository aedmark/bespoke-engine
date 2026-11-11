const std = @import("std");

pub const TokenTag = enum {
    // Keywords
    kw_entity,
    kw_relation,
    kw_property,
    kw_remember,
    kw_forget,
    kw_for,
    kw_ticks,
    kw_routine,
    kw_loop,
    kw_wait,
    kw_until,
    kw_interrupt,
    kw_with,
    kw_on,
    kw_cue,
    kw_when,
    kw_where,
    kw_and,
    kw_or,
    kw_not,
    kw_if,
    kw_else,
    kw_roll,
    kw_walk,
    kw_to,
    kw_face,
    kw_toward,
    kw_verb,
    kw_say,
    kw_scene,
    kw_cast,
    kw_props,
    kw_marks,
    kw_now,
    kw_is,
    kw_are,
    kw_stops,
    kw_forgets,
    kw_arrives,
    kw_being,
    kw_animate,
    kw_stop,
    kw_during,
    kw_state,
    kw_resume,
    kw_done,
    kw_currently,
    kw_in,
    kw_the,
    kw_transition,
    kw_choice,
    kw_draft,
    kw_weave,
    kw_society,
    kw_duel,
    kw_degradation,
    kw_path,
    kw_grid,
    kw_agenda,
    kw_command,
    kw_alias,

    // Identifiers & Literals
    identifier,
    number,
    dice, // e.g. 2d6
    string_literal,

    // Symbols & Punctuation
    lparen,
    rparen,
    lbracket,
    rbracket,
    comma,
    colon,
    underscore,
    gte,
    lte,
    eq,
    neq,
    gt,
    lt,

    // Layout
    newline,
    indent,
    dedent,

    eof,
};

pub const Token = struct {
    tag: TokenTag,
    slice: []const u8,
    line: u32,
    col: u32,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    indent_stack: std.ArrayList(u32),
    pending_dedents: u32,
    at_line_start: bool,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        var stack = std.ArrayList(u32).init(allocator);
        stack.append(0) catch {}; // base level

        return Lexer{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
            .indent_stack = stack,
            .pending_dedents = 0,
            .at_line_start = true,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.indent_stack.deinit();
    }

    fn peek_char(self: *const Lexer) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance_char(self: *mut_self) ?u8 {
        if (self.pos >= self.source.len) return null;
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
            self.at_line_start = true;
        } else {
            self.col += 1;
        }
        return c;
    }

    const mut_self = Lexer;

    pub fn next(self: *Lexer) !Token {
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return Token{
                .tag = .dedent,
                .slice = "",
                .line = self.line,
                .col = self.col,
            };
        }

        // Handle line starts and indentation
        while (self.pos < self.source.len) {
            if (self.at_line_start) {
                // Count indentation spaces
                var indent_spaces: u32 = 0;
                var scan = self.pos;
                while (scan < self.source.len and self.source[scan] == ' ') : (scan += 1) {
                    indent_spaces += 1;
                }

                // If blank line or comment, skip
                if (scan < self.source.len and (self.source[scan] == '\n' or self.source[scan] == '\r' or self.source[scan] == '#' or self.source[scan] == '~')) {
                    self.pos = scan;
                    _ = self.advance_char();
                    continue;
                }

                // If at EOF, emit dedents for remaining levels
                if (scan >= self.source.len) {
                    self.pos = scan;
                    break;
                }

                // Consume the spaces
                self.pos = scan;
                self.col += indent_spaces;
                self.at_line_start = false;

                const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];
                if (indent_spaces > current_indent) {
                    try self.indent_stack.append(indent_spaces);
                    return Token{
                        .tag = .indent,
                        .slice = "",
                        .line = self.line,
                        .col = self.col,
                    };
                } else if (indent_spaces < current_indent) {
                    var dedent_count: u32 = 0;
                    while (self.indent_stack.items.len > 1 and self.indent_stack.items[self.indent_stack.items.len - 1] > indent_spaces) {
                        _ = self.indent_stack.pop();
                        dedent_count += 1;
                    }
                    if (dedent_count > 0) {
                        self.pending_dedents = dedent_count - 1;
                        return Token{
                            .tag = .dedent,
                            .slice = "",
                            .line = self.line,
                            .col = self.col,
                        };
                    }
                }
            }

            // Skip inline whitespace
            while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t' or self.source[self.pos] == '\r')) {
                _ = self.advance_char();
            }

            // Skip comments (# or ~)
            if (self.pos < self.source.len and (self.source[self.pos] == '#' or self.source[self.pos] == '~')) {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    _ = self.advance_char();
                }
                continue;
            }

            if (self.pos >= self.source.len) break;

            const start_pos = self.pos;
            const start_col = self.col;
            const c = self.advance_char().?;

            if (c == '\n') {
                return Token{
                    .tag = .newline,
                    .slice = "\n",
                    .line = self.line - 1,
                    .col = start_col,
                };
            }

            // Single and multi-char symbols
            switch (c) {
                '(' => return Token{ .tag = .lparen, .slice = "(", .line = self.line, .col = start_col },
                ')' => return Token{ .tag = .rparen, .slice = ")", .line = self.line, .col = start_col },
                '[' => return Token{ .tag = .lbracket, .slice = "[", .line = self.line, .col = start_col },
                ']' => return Token{ .tag = .rbracket, .slice = "]", .line = self.line, .col = start_col },
                ',' => return Token{ .tag = .comma, .slice = ",", .line = self.line, .col = start_col },
                ':' => return Token{ .tag = .colon, .slice = ":", .line = self.line, .col = start_col },
                '_' => {
                    // Check if identifier or wildcard
                    if (self.peek_char()) |next_c| {
                        if (std.ascii.isAlphanumeric(next_c) or next_c == '_') {
                            while (self.peek_char()) |peek| {
                                if (std.ascii.isAlphanumeric(peek) or peek == '_') {
                                    _ = self.advance_char();
                                } else break;
                            }
                            return Token{
                                .tag = .identifier,
                                .slice = self.source[start_pos..self.pos],
                                .line = self.line,
                                .col = start_col,
                            };
                        }
                    }
                    return Token{ .tag = .underscore, .slice = "_", .line = self.line, .col = start_col };
                },
                '>' => {
                    if (self.peek_char() == '=') {
                        _ = self.advance_char();
                        return Token{ .tag = .gte, .slice = ">=", .line = self.line, .col = start_col };
                    }
                    return Token{ .tag = .gt, .slice = ">", .line = self.line, .col = start_col };
                },
                '<' => {
                    if (self.peek_char() == '=') {
                        _ = self.advance_char();
                        return Token{ .tag = .lte, .slice = "<=", .line = self.line, .col = start_col };
                    }
                    return Token{ .tag = .lt, .slice = "<", .line = self.line, .col = start_col };
                },
                '=' => {
                    if (self.peek_char() == '=') {
                        _ = self.advance_char();
                        return Token{ .tag = .eq, .slice = "==", .line = self.line, .col = start_col };
                    }
                    return Token{ .tag = .eq, .slice = "=", .line = self.line, .col = start_col };
                },
                '!' => {
                    if (self.peek_char() == '=') {
                        _ = self.advance_char();
                        return Token{ .tag = .neq, .slice = "!=", .line = self.line, .col = start_col };
                    }
                },
                '"' => {
                    const str_start = self.pos;
                    while (self.peek_char()) |sc| {
                        if (sc == '"') {
                            _ = self.advance_char();
                            break;
                        }
                        _ = self.advance_char();
                    }
                    return Token{
                        .tag = .string_literal,
                        .slice = self.source[str_start .. self.pos - 1],
                        .line = self.line,
                        .col = start_col,
                    };
                },
                else => {},
            }

            // Number or Dice literal
            if (std.ascii.isDigit(c)) {
                var is_dice = false;
                while (self.peek_char()) |peek| {
                    if (std.ascii.isDigit(peek)) {
                        _ = self.advance_char();
                    } else if (peek == 'd' and !is_dice) {
                        is_dice = true;
                        _ = self.advance_char();
                    } else break;
                }
                const slice = self.source[start_pos..self.pos];
                return Token{
                    .tag = if (is_dice) .dice else .number,
                    .slice = slice,
                    .line = self.line,
                    .col = start_col,
                };
            }

            // Identifier or Keyword
            if (std.ascii.isAlphabetic(c) or c == '_') {
                while (self.peek_char()) |peek| {
                    if (std.ascii.isAlphanumeric(peek) or peek == '_' or peek == '-') {
                        _ = self.advance_char();
                    } else break;
                }
                const slice = self.source[start_pos..self.pos];
                const tag = resolve_keyword(slice);
                return Token{
                    .tag = tag,
                    .slice = slice,
                    .line = self.line,
                    .col = start_col,
                };
            }
        }

        // Emit any remaining dedents before EOF
        if (self.indent_stack.items.len > 1) {
            _ = self.indent_stack.pop();
            return Token{
                .tag = .dedent,
                .slice = "",
                .line = self.line,
                .col = self.col,
            };
        }

        return Token{
            .tag = .eof,
            .slice = "",
            .line = self.line,
            .col = self.col,
        };
    }
};

fn resolve_keyword(ident: []const u8) TokenTag {
    const map = std.StaticStringMap(TokenTag).initComptime(.{
        .{ "entity", .kw_entity },
        .{ "relation", .kw_relation },
        .{ "property", .kw_property },
        .{ "remember", .kw_remember },
        .{ "forget", .kw_forget },
        .{ "for", .kw_for },
        .{ "ticks", .kw_ticks },
        .{ "routine", .kw_routine },
        .{ "loop", .kw_loop },
        .{ "wait", .kw_wait },
        .{ "until", .kw_until },
        .{ "interrupt", .kw_interrupt },
        .{ "with", .kw_with },
        .{ "on", .kw_on },
        .{ "cue", .kw_cue },
        .{ "when", .kw_when },
        .{ "where", .kw_where },
        .{ "and", .kw_and },
        .{ "or", .kw_or },
        .{ "not", .kw_not },
        .{ "if", .kw_if },
        .{ "else", .kw_else },
        .{ "roll", .kw_roll },
        .{ "walk", .kw_walk },
        .{ "to", .kw_to },
        .{ "face", .kw_face },
        .{ "toward", .kw_toward },
        .{ "verb", .kw_verb },
        .{ "say", .kw_say },
        .{ "says", .kw_say },
        .{ "scene", .kw_scene },
        .{ "cast", .kw_cast },
        .{ "props", .kw_props },
        .{ "marks", .kw_marks },
        .{ "now", .kw_now },
        .{ "is", .kw_is },
        .{ "are", .kw_are },
        .{ "stops", .kw_stops },
        .{ "forgets", .kw_forgets },
        .{ "arrives", .kw_arrives },
        .{ "being", .kw_being },
        .{ "animate", .kw_animate },
        .{ "stop", .kw_stop },
        .{ "during", .kw_during },
        .{ "state", .kw_state },
        .{ "resume", .kw_resume },
        .{ "done", .kw_done },
        .{ "currently", .kw_currently },
        .{ "in", .kw_in },
        .{ "the", .kw_the },
        .{ "towards", .kw_toward },
        .{ "transition", .kw_transition },
        .{ "choice", .kw_choice },
        .{ "draft", .kw_draft },
        .{ "weave", .kw_weave },
        .{ "society", .kw_society },
        .{ "duel", .kw_duel },
        .{ "degradation", .kw_degradation },
        .{ "path", .kw_path },
        .{ "grid", .kw_grid },
        .{ "agenda", .kw_agenda },
        .{ "command", .kw_command },
        .{ "alias", .kw_alias },
    });

    return map.get(ident) orelse .identifier;
}

test "P4-01: lexer tokenizes vertical slice script" {
    const testing = std.testing;
    const script =
        \\entity Guard, Bard
        \\relation Carries(holder, item)
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
    ;

    var lexer = Lexer.init(testing.allocator, script);
    defer lexer.deinit();

    var token_count: usize = 0;
    while (true) {
        const tok = try lexer.next();
        token_count += 1;
        if (tok.tag == .eof) break;
    }

    try testing.expect(token_count > 20);
}

test "P7-02: lexer tokenizes verbs, say statements, and string literals" {
    const testing = std.testing;
    const src =
        \\verb LookAt(actor, target):
        \\  say actor: "A cozy hearth."
    ;
    var lexer = Lexer.init(testing.allocator, src);
    defer lexer.deinit();

    try testing.expectEqual(TokenTag.kw_verb, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // LookAt
    try testing.expectEqual(TokenTag.lparen, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // actor
    try testing.expectEqual(TokenTag.comma, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // target
    try testing.expectEqual(TokenTag.rparen, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.indent, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_say, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // actor
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);

    const str_tok = try lexer.next();
    try testing.expectEqual(TokenTag.string_literal, str_tok.tag);
    try testing.expectEqualStrings("A cozy hearth.", str_tok.slice);
}

test "P10-01: lexer tokenizes stageplay taxonomy, state keywords, brackets, and tilde comments" {
    const testing = std.testing;
    const src =
        \\scene: Spitting Competition
        \\cast: Guybrush, Organiser
        \\props: Flags
        \\marks: Starting Line, Offstage
        \\remember Distracted[Organiser, Onlookers] for 100 ticks ~ inline comment
        \\now Flags are tampered with
        \\animate wind-blowing
        \\
    ;
    var lexer = Lexer.init(testing.allocator, src);
    defer lexer.deinit();

    try testing.expectEqual(TokenTag.kw_scene, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Spitting
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Competition
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_cast, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Guybrush
    try testing.expectEqual(TokenTag.comma, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Organiser
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_props, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Flags
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_marks, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Starting
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Line
    try testing.expectEqual(TokenTag.comma, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Offstage
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_remember, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Distracted
    try testing.expectEqual(TokenTag.lbracket, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Organiser
    try testing.expectEqual(TokenTag.comma, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Onlookers
    try testing.expectEqual(TokenTag.rbracket, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_for, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.number, (try lexer.next()).tag); // 100
    try testing.expectEqual(TokenTag.kw_ticks, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_now, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Flags
    try testing.expectEqual(TokenTag.kw_are, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // tampered
    try testing.expectEqual(TokenTag.kw_with, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_animate, (try lexer.next()).tag);
    const anim_tok = try lexer.next();
    try testing.expectEqual(TokenTag.identifier, anim_tok.tag);
    try testing.expectEqualStrings("wind-blowing", anim_tok.slice);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.eof, (try lexer.next()).tag);
}

test "P12-01: lexer tokenizes scene transition keywords" {
    const testing = std.testing;
    const script =
        \\transition to scene: Wine Cellar
        \\transition to scene Garden
    ;

    var lexer = Lexer.init(testing.allocator, script);
    defer lexer.deinit();

    try testing.expectEqual(TokenTag.kw_transition, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_to, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_scene, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    const wc_tok = try lexer.next();
    try testing.expectEqual(TokenTag.identifier, wc_tok.tag);
    try testing.expectEqualStrings("Wine", wc_tok.slice);
    const cellar_tok = try lexer.next();
    try testing.expectEqual(TokenTag.identifier, cellar_tok.tag);
    try testing.expectEqualStrings("Cellar", cellar_tok.slice);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_transition, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_to, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.kw_scene, (try lexer.next()).tag);
    const garden_tok = try lexer.next();
    try testing.expectEqual(TokenTag.identifier, garden_tok.tag);
    try testing.expectEqualStrings("Garden", garden_tok.slice);
    try testing.expectEqual(TokenTag.eof, (try lexer.next()).tag);
}

test "P13-01: lexer tokenizes dialogue choice keywords" {
    const testing = std.testing;
    const script =
        \\choice "Rent motorcycle" if Carries(Gabriel, License):
        \\choice "Leave shop":
    ;

    var lexer = Lexer.init(testing.allocator, script);
    defer lexer.deinit();

    try testing.expectEqual(TokenTag.kw_choice, (try lexer.next()).tag);
    const s1 = try lexer.next();
    try testing.expectEqual(TokenTag.string_literal, s1.tag);
    try testing.expectEqualStrings("Rent motorcycle", s1.slice);
    try testing.expectEqual(TokenTag.kw_if, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Carries
    try testing.expectEqual(TokenTag.lparen, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // Gabriel
    try testing.expectEqual(TokenTag.comma, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag); // License
    try testing.expectEqual(TokenTag.rparen, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.newline, (try lexer.next()).tag);

    try testing.expectEqual(TokenTag.kw_choice, (try lexer.next()).tag);
    const s2 = try lexer.next();
    try testing.expectEqual(TokenTag.string_literal, s2.tag);
    try testing.expectEqualStrings("Leave shop", s2.slice);
    try testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try testing.expectEqual(TokenTag.eof, (try lexer.next()).tag);
}
