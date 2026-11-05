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

    // Identifiers & Literals
    identifier,
    number,
    dice, // e.g. 2d6

    // Symbols & Punctuation
    lparen,
    rparen,
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
                if (scan < self.source.len and (self.source[scan] == '\n' or self.source[scan] == '\r' or self.source[scan] == '#')) {
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

            // Skip comments
            if (self.pos < self.source.len and self.source[self.pos] == '#') {
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
                    if (std.ascii.isAlphanumeric(peek) or peek == '_') {
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
