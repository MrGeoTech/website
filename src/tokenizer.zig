const std = @import("std");

const TokenList = std.ArrayList(Token);

const eql = std.mem.eql;
const assert = std.debug.assert;

pub const TokenType = enum {
    text,
    html,
    newline,
    forced_newline,
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
    bold,
    italic,
    bold_italic,

    pub fn isEscapeable(self: TokenType) bool {
        return self != .text and self != .newline and self != .forced_newline;
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
        var iterator = std.mem.splitScalar(u8, self.lexeme, '\n');
        while (iterator.next()) |line| {
            try writer.writeAll(line);
            if (iterator.peek() != null)
                try writer.writeAll("\\n");
        }
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

    fn scanNewLine(state: *TokenizerState) !void {
        if (state.current >= state.markdown.len) return;

        const char = state.markdown[state.current];
        while (state.markdown[state.current] == char) {
            state.current += 1;
            if (state.current >= state.markdown.len) {
                state.current = state.start;
                return;
            }
        }

        const count = state.current - (state.start);
        state.current -= 1;

        return switch (char) {
            '#' => switch (count) {
                1 => state.addToken(.header_1),
                2 => state.addToken(.header_2),
                3 => state.addToken(.header_3),
                4 => state.addToken(.header_4),
                5 => state.addToken(.header_5),
                6 => state.addToken(.header_6),
                else => error.InvalidHeader,
            },
            else => state.current = state.start,
        };
    }

    fn scanToken(state: *TokenizerState) !void {
        switch (state.markdown[state.current]) {
            '<' => blk: {
                var offset: usize = 0;
                while (state.markdown[state.current + offset] != '>') {
                    // Check if it is not an html tag
                    if (std.ascii.isWhitespace(state.markdown[state.current + offset])) break :blk;
                    offset += 1;
                }
                state.current += offset + 1;
                try state.addText();
                try state.addToken(.html);
            },
            '*', '_' => {
                try state.addText();
                if (state.matches(3))
                    try state.addToken(.bold_italic)
                else if (state.matches(2))
                    try state.addToken(.bold)
                else
                    try state.addToken(.italic);
            },
            ' ' => {
                try state.addText();
                // Skip multiple spaces
                while (state.markdown[state.current] == ' ') state.current += 1;
                state.start = state.current;
            },
            '\t', '\r' => {
                try state.addText();
                state.current += 1;
            },
            '\n' => {
                try state.addText();
                try state.addToken(.newline);
                if (state.current >= state.markdown.len) return;
                try state.scanNewLine();
                state.line += 1;
            },
            else => state.current += 1,
        }
    }

    test "scanToken" {
        var state = TokenizerState{
            .markdown = "**test***more",
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

        try state.scanToken();

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
        state.current += 1;
        if (state.start >= state.current) return;

        try state.tokens.append(.{
            .token_type = token_type,
            .lexeme = state.markdown[state.start..state.current],
            .line = state.line,
        });
        state.start = state.current;
    }

    fn addText(state: *TokenizerState) !void {
        if (state.current == 0) return;
        if (state.start >= state.current) return;

        try state.tokens.append(.{
            .token_type = .text,
            .lexeme = state.markdown[state.start .. state.current - 1],
            .line = state.line,
        });
        state.start = state.current - 1;
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

    fn matches(self: *TokenizerState, comptime total_count: comptime_int) bool {
        comptime assert(total_count > 0);
        if (total_count == 1) {
            self.current += 1;
            return true;
        }

        if (self.current + total_count - 1 >= self.markdown.len) return false;

        const char = self.markdown[self.current];
        for (1..total_count - 1) |i| {
            if (self.markdown[self.current + i] != char) return false;
        }

        self.current += total_count - 1;
        return true;
    }

    test "matches" {
        var state = TokenizerState{
            .markdown = "**test**",
            .tokens = TokenList.init(std.testing.allocator),
        };
        defer state.tokens.deinit();

        try std.testing.expect(state.matches(1));
        try std.testing.expectEqual(1, state.current);

        state.current = 6;

        try std.testing.expect(state.matches(2));
        try std.testing.expectEqual(7, state.current);
    }
};

pub fn tokenize(allocator: std.mem.Allocator, markdown: []const u8) !TokenList {
    var state = TokenizerState{
        .markdown = markdown,
        .tokens = TokenList.init(allocator),
    };

    assert(state.markdown.len > 0);
    while (state.current < state.markdown.len) {
        try state.scanToken();
    }

    if (state.start < state.current) try state.addText();

    var writer = std.io.getStdOut().writer();
    for (state.tokens.items) |token| {
        try token.write(writer);
        try writer.writeByte('\n');
    }

    try writer.writeAll("---------------\n");

    try cleanTokens(&state.tokens);

    for (state.tokens.items) |token| {
        try token.write(writer);
        try writer.writeByte('\n');
    }

    return state.tokens;
}

fn cleanTokens(tokens: *TokenList) !void {
    var new_tokens = TokenList.init(tokens.allocator);

    var i: usize = 0;

    // Handle metadata
    //if (tokens.items[0].token_type == .horizontal_rule) {
    //    while (i < tokens.items.len and tokens.items[i].token_type != .horizontal_rule) i += 1;

    //    const end_token = tokens.items[i];
    //    const end_ptr_int = @as(usize, @intFromPtr(end_token.lexeme.ptr)) + end_token.lexeme.len;
    //    const start_ptr_int: usize = @intFromPtr(tokens.items[0].lexeme.ptr);

    //    try new_tokens.append(.{
    //        .token_type = .metadata,
    //        .lexeme = tokens.items[0].lexeme[0 .. end_ptr_int - start_ptr_int],
    //        .line = 1,
    //    });
    //}

    while (i < tokens.items.len) : (i += 1) {
        const token = tokens.items[i];
        switch (token.token_type) {
            .header_1, .header_2, .header_3, .header_4, .header_5, .header_6 => {
                try combineNewLine(token.token_type, &i, tokens, &new_tokens);
            },
            else => try new_tokens.append(token),
        }
    }

    tokens.deinit();
    tokens.* = new_tokens;
}

fn combineNewLine(
    token_type: TokenType,
    index: *usize,
    tokens: *const TokenList,
    new_tokens: *TokenList,
) !void {
    const start_index = index.* + 1;
    while (tokens.items[index.*].token_type != .newline) index.* += 1;

    const start_token = tokens.items[start_index];
    const end_token = tokens.items[index.* - 1];

    const start: usize = @intFromPtr(start_token.lexeme.ptr);
    const end = @as(usize, @intFromPtr(end_token.lexeme.ptr)) + end_token.lexeme.len;
    const total_len = end - start;

    return new_tokens.append(.{
        .token_type = token_type,
        .lexeme = start_token.lexeme.ptr[0..total_len],
        .line = start_token.line,
    });
}

fn combine(
    comptime token_type: TokenType,
    comptime is_multiline: bool,
    index: *usize,
    tokens: *const TokenList,
    new_tokens: *TokenList,
) !void {
    const start_index = index.*;

    index.* += 1;
    while (tokens.items[index.*].token_type != token_type) : (index.* += 1) {
        const token = tokens.items[index.*];
        // Handle if the line ends before the closing tag
        if (!is_multiline and
            (token.token_type != .newline or
            token.token_type != .force_newline))
        {
            index.* = start_index;
            return new_tokens.append(.{
                .token_type = .text,
                .lexeme = tokens.items[start_index].lexeme,
                .line = tokens.items[start_index].line,
            });
        }
    }

    const start: usize = @intFromPtr(tokens.items[start_index].lexeme.ptr);
    const end = @as(usize, @intFromPtr(tokens.items[index.*].lexeme.ptr)) +
        tokens.items[index.*].lexeme.len;
    const total_len = end - start;

    return new_tokens.append(.{
        .token_type = token_type,
        .lexeme = tokens.items[start_index].lexeme.ptr[0..total_len],
        .line = tokens.items[start_index].line,
    });
}
