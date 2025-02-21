const std = @import("std");

pub const TokenType = enum {
    text,
    newline,
    force_newline,
    escape,
    bold,
    italic,
    math,
    math_block,
    code,
    code_block,

    pub fn toCharacters(self: TokenType) ?[]const u8 {
        return switch (self) {
            .text => null,
            .newline => "\n",
            .force_newline => "  \n",
            .escape => "\\",
            .bold => "**",
            .italic => "*",
            .math => "$",
            .math_block => "$$",
            .code => "`",
            .code_block => "```",
        };
    }
};

pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    line: usize,

    pub fn write(self: Token, writer: anytype) !void {
        try writer.writeAll("Token{token_type:");
        try writer.writeAll(@tagName(self.token_type));
        try writer.writeAll(",lexeme:");
        try writer.writeAll(self.lexeme);
        try writer.writeAll(",line:");
        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
        try writer.writeByte('}');
    }

    test "write" {
        const token = Token{
            .token_type = .text,
            .lexeme = "Hello World",
            .line = 1,
        };

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try token.write(output.writer());

        try std.testing.expectEqualStrings("Token{token_type:text,lexeme:Hello World,line:1}", output.items);
    }
};

const TokenizerState = struct {
    markdown: []const u8,
    tokens: std.ArrayList(Token),
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,

    fn scanToken(state: *TokenizerState) !void {
        switch (state.markdown[state.current]) {
            '\\' => {
                try state.addText();
                try state.addToken(.escape);
            },
            '`' => {
                try state.addText();
                if (state.matches("``"))
                    try state.addToken(.code_block)
                else
                    try state.addToken(.code);
            },
            '$' => {
                try state.addText();
                if (state.matches("$"))
                    try state.addToken(.math_block)
                else
                    try state.addToken(.math);
            },
            '*' => {
                try state.addText();
                if (state.matches("*"))
                    try state.addToken(.bold)
                else
                    try state.addToken(.italic);
            },
            ' ' => {
                try state.addText();
                if (state.matches(" \n")) {
                    try state.addToken(.force_newline);
                    state.line += 1;
                } else {
                    try state.addText();
                }
            },
            '\t', '\r' => {
                try state.addText();
            },
            '\n' => {
                try state.addText();
                try state.addToken(.newline);
                state.line += 1;
            },
            else => {},
        }
        state.current += 1;
    }

    test "scanToken" {
        var state = TokenizerState{
            .markdown = "**test**more",
            .tokens = std.ArrayList(Token).init(std.testing.allocator),
            .current = 0,
        };
        defer state.tokens.deinit();

        try state.scanToken();

        try std.testing.expectEqual(1, state.tokens.items.len);
        try std.testing.expectEqual(.bold, state.tokens.items[0].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[0].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[0].line);

        // The loop will just continue to call scan token
        try state.scanToken();
        try state.scanToken();
        try state.scanToken();
        try state.scanToken();
        try state.scanToken();

        try std.testing.expectEqual(3, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[1].token_type);
        try std.testing.expectEqualStrings("test", state.tokens.items[1].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[1].line);
        try std.testing.expectEqual(.bold, state.tokens.items[2].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[2].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[2].line);

        // The loop will call scan token until current >= markdown.len
        // Then, it will see that start < current and call addText one more time.
        try state.scanToken();
        try state.scanToken();
        try state.scanToken();
        try state.scanToken();
        try state.addText();

        try std.testing.expectEqual(4, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[3].token_type);
        try std.testing.expectEqualStrings("more", state.tokens.items[3].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[3].line);
    }

    fn addToken(state: *TokenizerState, token_type: TokenType) !void {
        try state.tokens.append(.{
            .token_type = token_type,
            .lexeme = state.markdown[state.start .. state.current + 1],
            .line = state.line,
        });
        state.start = state.current + 1;
    }

    fn addText(state: *TokenizerState) !void {
        if (state.current == 0) return;
        if (state.start >= state.current) return;

        try state.tokens.append(.{
            .token_type = .text,
            .lexeme = state.markdown[state.start..state.current],
            .line = state.line,
        });
        state.start = state.current;
    }

    test "addToken/addText" {
        var state = TokenizerState{
            .markdown = "**test**more",
            .tokens = std.ArrayList(Token).init(std.testing.allocator),
            .current = 1,
        };
        defer state.tokens.deinit();

        try state.addToken(.bold);

        try std.testing.expectEqual(1, state.tokens.items.len);
        try std.testing.expectEqual(.bold, state.tokens.items[0].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[0].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[0].line);

        state.current += 5;
        try state.addText();

        try std.testing.expectEqual(2, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[1].token_type);
        try std.testing.expectEqualStrings("test", state.tokens.items[1].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[1].line);

        state.current += 1;
        try state.addToken(.bold);

        try std.testing.expectEqual(3, state.tokens.items.len);
        try std.testing.expectEqual(.bold, state.tokens.items[2].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[2].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[2].line);

        state.current += 5;
        try state.addText();

        try std.testing.expectEqual(4, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[3].token_type);
        try std.testing.expectEqualStrings("more", state.tokens.items[3].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[3].line);
    }

    fn matches(self: *TokenizerState, comptime string: []const u8) bool {
        if (self.current + string.len >= self.markdown.len) return false;
        if (!std.mem.eql(u8, self.markdown[self.current + 1 ..][0..string.len], string)) return false;

        self.current += string.len;
        return true;
    }

    test "matches" {
        var state = TokenizerState{
            .markdown = "**test**",
            .tokens = std.ArrayList(Token).init(std.testing.allocator),
        };
        defer state.tokens.deinit();

        try std.testing.expect(state.matches("*"));
        try std.testing.expectEqual(1, state.current);

        state.current = 6;

        try std.testing.expect(state.matches("*"));
        try std.testing.expectEqual(7, state.current);
    }
};

pub fn tokenize(allocator: std.mem.Allocator, markdown: []const u8) !std.ArrayList(Token) {
    var state = TokenizerState{
        .markdown = markdown,
        .tokens = std.ArrayList(Token).init(allocator),
    };

    std.debug.assert(state.markdown.len > 0);
    while (state.current < state.markdown.len) {
        try state.scanToken();
    }

    if (state.start != state.current) try state.addText();

    return state.tokens;
}

test "tokenize" {
    var tokens = try tokenize(std.testing.allocator, "**test**more");
    defer tokens.deinit();

    try std.testing.expectEqual(4, tokens.items.len);
    try std.testing.expectEqual(.bold, tokens.items[0].token_type);
    try std.testing.expectEqualStrings("**", tokens.items[0].lexeme);
    try std.testing.expectEqual(1, tokens.items[0].line);
    try std.testing.expectEqual(.text, tokens.items[1].token_type);
    try std.testing.expectEqualStrings("test", tokens.items[1].lexeme);
    try std.testing.expectEqual(1, tokens.items[1].line);
    try std.testing.expectEqual(.bold, tokens.items[2].token_type);
    try std.testing.expectEqualStrings("**", tokens.items[2].lexeme);
    try std.testing.expectEqual(1, tokens.items[2].line);
    try std.testing.expectEqual(.text, tokens.items[3].token_type);
    try std.testing.expectEqualStrings("more", tokens.items[3].lexeme);
    try std.testing.expectEqual(1, tokens.items[3].line);
}

pub fn cleanTokens(tokens: *std.ArrayList(Token)) !void {
    var exclude_effects = false;
    for (tokens.items) |token| {
        
    }
}
