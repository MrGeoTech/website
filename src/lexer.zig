const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const TokenType = tokenizer.TokenType;
pub const LexemeList = std.ArrayList(Lexeme);

const assert = std.debug.assert;

pub const Lexeme = struct {
    lexeme_type: TokenType,
    value: []const u8,
    line: usize,
};

const LexerState = struct {
    markdown: []const u8,
    tokens: LexemeList,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,

    fn scanNewLine(state: *LexerState) !void {
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
                1 => state.addLexeme(.header_1),
                2 => state.addLexeme(.header_2),
                3 => state.addLexeme(.header_3),
                4 => state.addLexeme(.header_4),
                5 => state.addLexeme(.header_5),
                6 => state.addLexeme(.header_6),
                else => error.InvalidHeader,
            },
            else => state.current = state.start,
        };
    }

    fn scanLexeme(state: *LexerState) !void {
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
                try state.addLexeme(.html);
            },
            '*', '_' => {
                try state.addText();
                if (state.matches(3))
                    try state.addLexeme(.bold_italic)
                else if (state.matches(2))
                    try state.addLexeme(.bold)
                else if (state.matches(1))
                    try state.addLexeme(.italic);
            },
            ' ' => {
                try state.addText();
                if (state.matchesString("  \n"))
                    state.addLexeme(.forced_newline)
                else {
                    state.current += 1;
                    state.start = state.current;
                }
            },
            '\t', '\r' => {
                try state.addText();
                state.current += 1;
            },
            '\n' => {
                try state.addText();
                state.current += 1;
                try state.addLexeme(.newline);
                if (state.current >= state.markdown.len) return;
                try state.scanNewLine();
                state.line += 1;
            },
            else => state.current += 1,
        }
    }

    test "scanLexeme" {
        var state = LexerState{
            .markdown = "**test***more",
            .tokens = LexemeList.init(std.testing.allocator),
            .current = 0,
        };
        defer state.tokens.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.tokens.items.len);
        try std.testing.expectEqual(.bold, state.tokens.items[0].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[0].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[0].line);

        // The loop will just continue to call scan token
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();

        try std.testing.expectEqual(3, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[1].token_type);
        try std.testing.expectEqualStrings("test", state.tokens.items[1].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[1].line);
        try std.testing.expectEqual(.bold, state.tokens.items[2].token_type);
        try std.testing.expectEqualStrings("**", state.tokens.items[2].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[2].line);

        try state.scanLexeme();

        // The loop will call scan token until current >= markdown.len
        // Then, it will see that start < current and call addText one more time.
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.addText();

        try std.testing.expectEqual(4, state.tokens.items.len);
        try std.testing.expectEqual(.text, state.tokens.items[3].token_type);
        try std.testing.expectEqualStrings("more", state.tokens.items[3].lexeme);
        try std.testing.expectEqual(1, state.tokens.items[3].line);
    }

    fn addLexeme(state: *LexerState, token_type: TokenType) !void {
        if (state.start >= state.current) return;

        try state.tokens.append(.{
            .token_type = token_type,
            .lexeme = state.markdown[state.start..state.current],
            .line = state.line,
        });
        state.start = state.current;
    }

    fn addText(state: *LexerState) !void {
        if (state.current == 0) return;
        if (state.start >= state.current) return;

        try state.tokens.append(.{
            .token_type = .text,
            .lexeme = state.markdown[state.start .. state.current - 1],
            .line = state.line,
        });
        state.start = state.current - 1;
    }

    test "addLexeme/addText" {
        var state = LexerState{
            .markdown = "**test**more",
            .tokens = LexemeList.init(std.testing.allocator),
            .current = 1,
        };
        defer state.tokens.deinit();

        try state.addLexeme(.bold);

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

        try state.addLexeme(.bold);

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

    fn matches(self: *LexerState, comptime total_count: comptime_int) bool {
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
        var state = LexerState{
            .markdown = "**test**",
            .tokens = LexemeList.init(std.testing.allocator),
        };
        defer state.tokens.deinit();

        try std.testing.expect(state.matches(1));
        try std.testing.expectEqual(1, state.current);

        state.current = 6;

        try std.testing.expect(state.matches(2));
        try std.testing.expectEqual(7, state.current);
    }

    fn matchesString(self: *LexerState, comptime string: []const u8) bool {
        if (self.current + string.len >= self.markdown.len) return false;
        if (!std.mem.eql(u8, self.markdown[self.current + 1 ..][0..string.len], string)) return false;

        self.current += string.len;
        return true;
    }

    test "matchesString" {
        var state = LexerState{
            .markdown = "**test**",
            .tokens = LexemeList.init(std.testing.allocator),
        };
        defer state.tokens.deinit();

        try std.testing.expect(state.matchesString("*"));
        try std.testing.expectEqual(1, state.current);

        state.current = 6;

        try std.testing.expect(state.matchesString("*"));
        try std.testing.expectEqual(7, state.current);
    }
};
