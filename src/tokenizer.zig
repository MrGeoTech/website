const std = @import("std");

const TokenList = std.ArrayList(Token);

const eql = std.mem.eql;

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

    pub fn isEscapeable(self: TokenType) bool {
        return self != .text and self != .force_newline and self != .newline;
    }

    pub fn of(text: []const u8) TokenType {
        return if (eql(u8, text, "*"))
            .italic
        else if (eql(u8, text, "**"))
            .bold
        else if (eql(u8, text, "$"))
            .math
        else if (eql(u8, text, "$$"))
            .math_block
        else if (eql(u8, text, "`"))
            .code
        else if (eql(u8, text, "```"))
            .code_block
        else if (eql(u8, text, "\\"))
            .escape
        else if (eql(u8, text, "\n"))
            .newline
        else if (eql(u8, text, "  \n"))
            .force_newline
        else
            .text;
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
    tokens: TokenList,
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
            .tokens = TokenList.init(std.testing.allocator),
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
            .tokens = TokenList.init(std.testing.allocator),
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
            .tokens = TokenList.init(std.testing.allocator),
        };
        defer state.tokens.deinit();

        try std.testing.expect(state.matches("*"));
        try std.testing.expectEqual(1, state.current);

        state.current = 6;

        try std.testing.expect(state.matches("*"));
        try std.testing.expectEqual(7, state.current);
    }
};

pub fn tokenize(allocator: std.mem.Allocator, markdown: []const u8) !TokenList {
    var state = TokenizerState{
        .markdown = markdown,
        .tokens = TokenList.init(allocator),
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

pub fn cleanTokens(tokens: *TokenList) !void {
    var new_tokens = TokenList.init(tokens.allocator);
    defer new_tokens.deinit();

    var i: usize = 0;
    while (i < tokens.items.len) : (i += 1) {
        const token = tokens.items[i];
        switch (token.token_type) {
            .text, .force_newline => try new_tokens.append(token),
            .escape => {
                const next_token = tokens.items[i + 1];
                if (!next_token.token_type.isEscapeable()) {
                    try new_tokens.append(.{
                        .token_type = .text,
                        .lexeme = token.lexeme,
                        .line = token.line,
                    });
                } else {
                    try new_tokens.append(.{
                        .token_type = .text,
                        .lexeme = next_token.lexeme[0..1],
                        .line = token.line,
                    });
                    tokens.items[i + 1] = .{
                        .token_type = TokenType.of(next_token.lexeme[1..]),
                        .lexeme = next_token.lexeme[1..],
                        .line = next_token.line,
                    };
                }
            },
            .math => try combine(.math, false, &i, tokens, &new_tokens),
            .math_block => try combine(.math_block, true, &i, tokens, &new_tokens),
            .code => try combine(.code, false, &i, tokens, &new_tokens),
            .code_block => try combine(.code_block, true, &i, tokens, &new_tokens),
            .italic => try combine(.italic, false, &i, tokens, &new_tokens),
            .bold => try combine(.bold, false, &i, tokens, &new_tokens),
        }
    }
}

fn combine(
    comptime token_type: TokenType,
    comptime is_multiline: bool,
    index: *usize,
    tokens: *const TokenList,
    new_tokens: *TokenList,
) !void {
    const start_index = index.*;
    var total_len = tokens.items[start_index].lexeme.len;

    index.* += 1;
    while (tokens.items[index.*].token_type != token_type) : (index.* += 1) {
        // Handle if the line ends before the closing tag
        if (!is_multiline and
            (tokens.items[index.*].token_type != .newline or
            tokens.items[index.*].token_type != .force_newline))
        {
            index.* = start_index;
            return new_tokens.append(.{
                .token_type = .text,
                .lexeme = tokens.items[start_index].lexeme,
                .line = tokens.items[start_index].line,
            });
        }

        total_len += tokens.items[index.*].lexeme.len;
    }

    return new_tokens.append(.{
        .token_type = token_type,
        .lexeme = tokens.items[start_index].lexeme.ptr[0..total_len],
        .line = tokens.items[start_index].line,
    });
}
