const std = @import("std");
const lexer = @import("lexer.zig");

const Allocator = std.mem.Allocator;
const LexemeList = std.ArrayList(lexer.Lexeme);
pub const TokenList = struct {
    tokens: []Token = &.{},

    pub fn append(self: *TokenList, allocator: Allocator, tokens: []const Token) error{OutOfMemory}!void {
        const old_len = self.tokens.len;
        self.tokens = try allocator.realloc(self.tokens, self.tokens.len + tokens.len);
        @memcpy(self.tokens[old_len..], tokens);
    }

    pub fn deinit(self: TokenList, allocator: Allocator) void {
        for (self.tokens) |token| {
            switch (token.value) {
                .children => |children| children.deinit(allocator),
                else => {},
            }
        }

        allocator.free(self.tokens);
    }
};

const eql = std.mem.eql;
const assert = std.debug.assert;

pub const TokenType = enum {
    escape,
    indent,
    text,
    newline,
    forced_newline,
    html,
    html_start,
    html_end,
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
    blockquote,
    bold,
    italic,
    bold_italic,
    ordered_list,
    unordered_list,
    escape_backticks,
    code,
    code_block,
    code_lang,
    horizontal_rule,
    link,
    image,
    image_start,
    alt_start,
    alt_end,
    url_start,
    url_end,
    ampersand,

    pub fn isEscapeable(self: TokenType) bool {
        return self != .text and self != .newline and self != .forced_newline;
    }

    pub fn isNewLine(self: TokenType) bool {
        return self == .newline or self == .forced_newline;
    }

    pub fn isHeader(self: TokenType) bool {
        return self == .header_1 or self == .header_2 or self == .header_3 or
            self == .header_4 or self == .header_5 or self == .header_6;
    }
};

pub const Token = struct {
    token_type: TokenType,
    value: union(enum) {
        lexeme: []const u8,
        children: TokenList,
    },
    line: usize,

    pub fn of(lexeme: lexer.Lexeme) Token {
        return .{
            .token_type = lexeme.lexeme_type,
            .value = .{ .lexeme = lexeme.value },
            .line = lexeme.line,
        };
    }

    test "of" {
        const lexeme = lexer.Lexeme{
            .lexeme_type = .text,
            .value = "Hello",
            .line = 1,
        };
        const actual_token = Token.of(lexeme);

        try std.testing.expectEqual(.text, actual_token.token_type);
        try std.testing.expectEqual(.lexeme, std.meta.activeTag(actual_token.value));
        try std.testing.expectEqualStrings("Hello", actual_token.value.lexeme);
        try std.testing.expectEqual(1, actual_token.line);
    }

    pub fn getLexeme(self: Token) []const u8 {
        return switch (self.value) {
            .lexeme => |lexeme| lexeme,
            .children => |children| blk: {
                if (children.tokens.len < 1) break :blk "";

                const lexeme_start = children.tokens[0].getLexeme();
                const lexeme_end = children.tokens[children.tokens.len - 1].getLexeme();

                const index_start: usize = @intFromPtr(lexeme_start.ptr);
                const index_end = @as(usize, @intFromPtr(lexeme_end.ptr)) + lexeme_end.len;

                break :blk lexeme_start.ptr[0 .. index_end - index_start];
            },
        };
    }

    test "getLexeme" {
        const markdown = "Hello World";
        const lexeme_token1 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[0..5] },
            .line = 1,
        };
        const lexeme_token2 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[6..] },
            .line = 1,
        };
        var children_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{
                .tokens = try std.testing.allocator.dupe(Token, &[_]Token{ lexeme_token1, lexeme_token2 }),
            } },
            .line = 1,
        };
        defer children_token.value.children.deinit(std.testing.allocator);

        try std.testing.expectEqualStrings("Hello", lexeme_token1.getLexeme());
        try std.testing.expectEqualStrings("World", lexeme_token2.getLexeme());
        try std.testing.expectEqualStrings("Hello World", children_token.getLexeme());

        // No need for a deinit because nothing is every actually allocated.
        const special_case_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{} },
            .line = 1,
        };

        try std.testing.expectEqualStrings("", special_case_token.getLexeme());
    }

    pub fn write(self: Token, writer: anytype) !void {
        try writer.writeAll("Token{token_type:");
        try writer.writeAll(@tagName(self.token_type));
        try writer.writeAll(",value:");
        switch (self.value) {
            .lexeme => |lexeme| {
                var iterator = std.mem.splitScalar(u8, lexeme, '\n');
                while (iterator.next()) |line| {
                    try writer.writeAll(line);
                    if (iterator.peek() != null)
                        try writer.writeAll("\\n");
                }
            },
            .children => |children| {
                try writer.writeByte('\n');
                for (children.tokens) |child| {
                    try child.write(writer);
                    try writer.writeByte('\n');
                }
            },
        }
        try writer.writeAll(",line:");
        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
        try writer.writeByte('}');
    }

    test "write Lexeme" {
        const token = Token{
            .token_type = .text,
            .value = .{ .lexeme = "Hello World" },
            .line = 1,
        };

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try token.write(output.writer());

        try std.testing.expectEqualStrings("Token{token_type:text,value:Hello World,line:1}", output.items);
    }

    test "write Children" {
        const markdown = "Hello World";
        const lexeme_token1 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[0..5] },
            .line = 1,
        };
        const lexeme_token2 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[6..] },
            .line = 1,
        };
        var children_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{
                .tokens = try std.testing.allocator.dupe(Token, &[_]Token{ lexeme_token1, lexeme_token2 }),
            } },
            .line = 1,
        };
        defer children_token.value.children.deinit(std.testing.allocator);

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try children_token.write(output.writer());

        try std.testing.expectEqualStrings("Token{token_type:text,value:\nToken{token_type:text,value:Hello,line:1}\nToken{token_type:text,value:World,line:1}\n,line:1}", output.items);
    }
};

const TokenizerState = struct {
    allocator: Allocator,
    lexemes: []lexer.Lexeme,
    tokens: TokenList,
    start: usize = 0,
    current: usize = 0,

    pub fn addNextToken(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current < self.lexemes.len);
        const lexeme = self.lexemes[self.current];

        switch (lexeme.lexeme_type) {
            .header_1, .header_2, .header_3, .header_4, .header_5, .header_6 => {
                try self.addCombineChildren(true); // Add Text
                try self.addHeader();
            },
            .bold => {
                var offset: usize = 1;
                if (self.current + 1 >= self.lexemes.len or
                    self.lexemes[self.current + 1].lexeme_type.isNewLine())
                {
                    self.lexemes[self.start].lexeme_type = .text;
                    self.current += 1;
                    return;
                }

                while (self.lexemes[self.current + offset].lexeme_type != lexeme.lexeme_type) {
                    offset += 1;
                    // If we reach the end and no match has been found, treat it like text
                    if (self.current + offset >= self.lexemes.len or
                        self.lexemes[self.current].lexeme_type.isNewLine())
                    {
                        self.lexemes[self.start].lexeme_type = .text;
                        self.current += 1;
                        return;
                    }
                }
                try self.addCombineChildren(true); // Add Text

                self.current += offset;

                try self.addWithChildren();
                self.start += 1;
            },
            .newline => {
                if (self.current + 1 < self.lexemes.len and self.lexemes[self.current + 1].lexeme_type == .newline) {
                    try self.addCombineChildren(true); // Add Text
                    self.current += 2;
                    try self.addCombineChildren(true); // Add Forced New Line
                    self.tokens.tokens[self.tokens.tokens.len - 1].token_type = .forced_newline;
                } else {
                    // If it is just a single newline, then we have to treat it like a space
                    // To do this, we just set the newline character to a space character
                    self.lexemes[self.current].value[0] = ' ';
                    self.current += 1;
                }
            },
            .forced_newline => {
                try self.addCombineChildren(true); // Add Text
                try self.addCurrent(); // Add Forced New Line
            },
            else => self.current += 1,
        }
    }

    fn addCombineChildren(self: *TokenizerState, inclusive: bool) error{OutOfMemory}!void {
        const inclusive_int: u1 = @intFromBool(!inclusive);
        const should_ignore_start = eql(u8, self.lexemes[self.start + inclusive_int].value, " ");
        const should_ignore_start_int = @intFromBool(should_ignore_start);
        const new_start = self.start + inclusive_int + should_ignore_start_int;

        if (self.current > self.lexemes.len) return;
        if (new_start >= self.current) return;

        const lexeme_type = self.lexemes[self.start];

        if (new_start == self.current) {
            try self.tokens.append(self.allocator, &.{.{
                .token_type = lexeme_type.lexeme_type,
                .value = .{ .lexeme = lexeme_type.value[lexeme_type.value.len..] },
                .line = lexeme_type.line,
            }});
        } else {
            const lexeme_start = self.lexemes[new_start].value;
            const lexeme_end = self.lexemes[self.current - 1].value;

            const ptr_start: usize = @intFromPtr(lexeme_start.ptr);
            const ptr_end = @as(usize, @intFromPtr(lexeme_end.ptr)) + lexeme_end.len;

            try self.tokens.append(self.allocator, &.{.{
                .token_type = lexeme_type.lexeme_type,
                .value = .{ .lexeme = lexeme_start.ptr[0 .. ptr_end - ptr_start] },
                .line = lexeme_type.line,
            }});
        }

        self.start = self.current;
    }

    fn addWithChildren(self: *TokenizerState) error{OutOfMemory}!void {
        if (self.current > self.lexemes.len) return;
        if (self.start + 1 >= self.current) return;

        const capacity = self.current - self.start + 1;

        const lexemes = LexemeList{
            .allocator = self.allocator,
            .items = self.lexemes[],
            .capacity = capacity,
        };

        const children = try tokenize(lexemes);
        errdefer children.deinit(self.allocator);

        try self.tokens.append(self.allocator, &.{.{
            .token_type = self.lexemes[self.start].lexeme_type,
            .value = .{ .children = children },
            .line = self.lexemes[self.start].line,
        }});

        self.start = self.current;
    }

    fn addCurrent(self: *TokenizerState) error{OutOfMemory}!void {
        try self.tokens.append(self.allocator, &.{Token.of(self.lexemes[self.current])});
        self.current += 1;
        self.start += 1;
    }

    fn addHeader(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.start == self.current);
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type.isHeader());

        while (self.current < self.lexemes.len and
            !self.lexemes[self.current].lexeme_type.isNewLine())
            self.current += 1;

        defer self.start += 1;
        return self.addCombineChildren(false);
    }
};

pub fn tokenize(lexemes: LexemeList) error{OutOfMemory}!TokenList {
    var state = TokenizerState{
        .allocator = lexemes.allocator,
        .lexemes = lexemes.items,
        .tokens = TokenList{},
    };

    while (state.current < state.lexemes.len) {
        try state.addNextToken();
    }

    if (state.start != state.current) try state.addCombineChildren(true);

    return state.tokens;
}

test "tokenize" {
    const markdown = "## Test Header\nThat was a test header!";
    const lexemes = try lexer.process(std.testing.allocator, markdown);
    defer lexemes.deinit();

    const tokens = try tokenize(lexemes);
    defer tokens.deinit(lexemes.allocator);

    try std.testing.expectEqual(3, tokens.tokens.len);
}
