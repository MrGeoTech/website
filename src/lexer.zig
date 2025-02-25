const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const TokenType = tokenizer.TokenType;
const LexemeList = std.ArrayList(Lexeme);

const assert = std.debug.assert;

pub const Lexeme = struct {
    lexeme_type: TokenType,
    value: []const u8,
    line: usize,

    pub fn write(self: Lexeme, writer: anytype) !void {
        try writer.writeAll("Lexeme{lexeme_type:");
        try writer.writeAll(@tagName(self.lexeme_type));
        try writer.writeAll(",value:");
        var iterator = std.mem.splitScalar(u8, self.value, '\n');
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
        const lexeme = Lexeme{
            .lexeme_type = .text,
            .value = "Hello World",
            .line = 1,
        };

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try lexeme.write(output.writer());

        try std.testing.expectEqualStrings("Lexeme{lexeme_type:text,value:Hello World,line:1}", output.items);
    }
};

const LexerState = struct {
    markdown: []const u8,
    lexemes: LexemeList,
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

        const count = state.current - state.start;

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
            else => state.current = state.start + 1,
        };
    }

    fn scanLexeme(state: *LexerState) !void {
        switch (state.markdown[state.current]) {
            '<' => blk: {
                var offset: usize = 0;
                while (state.markdown[state.current + offset] != '>') {
                    // Check if it is not an html tag
                    if (state.markdown[state.current + offset] == '\n') {
                        state.current += 1;
                        break :blk;
                    }
                    offset += 1;
                }
                try state.addLexeme(.text);
                state.current += offset + 1;
                try state.addLexeme(.html);
            },
            '*', '_' => {
                try state.addLexeme(.text);
                if (state.matches(3))
                    try state.addLexeme(.bold_italic)
                else if (state.matches(2))
                    try state.addLexeme(.bold)
                else if (state.matches(1)) // Will always return true but increments current
                    try state.addLexeme(.italic);
            },
            ' ' => {
                try state.addLexeme(.text);
                if (state.matchesString("  \n")) {
                    state.line += 1;
                    try state.addLexeme(.forced_newline);
                } else {
                    state.current += 1;
                    state.start = state.current;
                }
            },
            '\t', '\r' => {
                try state.addLexeme(.text);
                state.current += 1;
            },
            '\n' => {
                try state.addLexeme(.text);
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
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 0,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);

        // The loop will just continue to call scan lexeme
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(.bold_italic, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings("***", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);

        // The loop will call scan lexeme until current >= markdown.len
        // Then, it will see that start < current and call addText one more time.
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.scanLexeme();
        try state.addLexeme(.text);

        try std.testing.expectEqual(4, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[3].lexeme_type);
        try std.testing.expectEqualStrings("more", state.lexemes.items[3].value);
        try std.testing.expectEqual(1, state.lexemes.items[3].line);
    }

    fn addLexeme(state: *LexerState, lexeme_type: TokenType) !void {
        if (state.start >= state.current) return;

        try state.lexemes.append(.{
            .lexeme_type = lexeme_type,
            .value = state.markdown[state.start..state.current],
            .line = state.line,
        });
        state.start = state.current;
    }

    test "addLexeme" {
        var state = LexerState{
            .markdown = "**test**more",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 2,
        };
        defer state.lexemes.deinit();

        try state.addLexeme(.bold);

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);

        state.current += 4;
        try state.addLexeme(.text);

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);

        state.current += 2;
        try state.addLexeme(.bold);

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);

        state.current += 4;
        try state.addLexeme(.text);

        try std.testing.expectEqual(4, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[3].lexeme_type);
        try std.testing.expectEqualStrings("more", state.lexemes.items[3].value);
        try std.testing.expectEqual(1, state.lexemes.items[3].line);
    }

    fn matches(self: *LexerState, comptime total_count: comptime_int) bool {
        comptime assert(total_count > 0);
        if (total_count == 1) {
            self.current += 1;
            return true;
        }

        if (self.current + total_count - 1 >= self.markdown.len) return false;

        const char = self.markdown[self.current];
        for (1..total_count) |i| {
            if (self.markdown[self.current + i] != char) return false;
        }

        self.current += total_count;
        return true;
    }

    test "matches" {
        var state = LexerState{
            .markdown = "**test**",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try std.testing.expect(state.matches(1));
        try std.testing.expectEqual(1, state.current);
        state.current = 0;
        try std.testing.expect(state.matches(2));
        try std.testing.expectEqual(2, state.current);
        state.current = 0;
        try std.testing.expect(!state.matches(3));
        try std.testing.expectEqual(0, state.current);
        state.current = 5;
        try std.testing.expect(!state.matches(2));
        try std.testing.expectEqual(5, state.current);
        state.current = 6;
        try std.testing.expect(state.matches(2));
        try std.testing.expectEqual(8, state.current);
        state.current = 6;
        try std.testing.expect(!state.matches(3));
        try std.testing.expectEqual(6, state.current);
    }

    fn matchesString(self: *LexerState, comptime string: []const u8) bool {
        if (self.current + string.len > self.markdown.len) return false;
        if (!std.mem.eql(u8, self.markdown[self.current..][0..string.len], string)) return false;

        self.current += string.len;
        return true;
    }

    test "matchesString" {
        var state = LexerState{
            .markdown = "**test**",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try std.testing.expect(state.matchesString("*"));
        try std.testing.expectEqual(1, state.current);
        state.current = 0;
        try std.testing.expect(state.matchesString("**"));
        try std.testing.expectEqual(2, state.current);
        state.current = 0;
        try std.testing.expect(!state.matchesString("***"));
        try std.testing.expectEqual(0, state.current);
        state.current = 5;
        try std.testing.expect(!state.matchesString("**"));
        try std.testing.expectEqual(5, state.current);
        state.current = 6;
        try std.testing.expect(state.matchesString("**"));
        try std.testing.expectEqual(8, state.current);
        state.current = 6;
        try std.testing.expect(!state.matchesString("***"));
        try std.testing.expectEqual(6, state.current);
    }
};

pub fn process(allocator: std.mem.Allocator, markdown: []const u8) !LexemeList {
    var state = LexerState{
        .markdown = markdown,
        .lexemes = LexemeList.init(allocator),
    };

    if (state.markdown.len == 0)
        return state.lexemes;
    try state.scanNewLine();

    while (state.current < state.markdown.len) {
        try state.scanLexeme();
    }

    return state.lexemes;
}
