const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const TokenType = tokenizer.TokenType;
const LexemeList = std.ArrayList(Lexeme);

const assert = std.debug.assert;

pub const Lexeme = struct {
    lexeme_type: TokenType,
    value: []const u8,
    line: usize,
    has_following_space: bool,

    pub fn write(self: Lexeme, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll("Lexeme{lexeme_type:");
        if (self.lexeme_type.isEscapeable())
            try writer.writeAll("\x1B[0;32m");
        try writer.writeAll(@tagName(self.lexeme_type));
        if (self.lexeme_type.isEscapeable())
            try writer.writeAll("\x1B[0m");
        try writer.writeAll(",value:");
        var iterator = std.mem.splitScalar(u8, self.value, '\n');
        while (iterator.next()) |line| {
            try writer.writeAll(line);
            if (iterator.peek() != null)
                try writer.writeAll("\\n");
        }
        try writer.writeAll(",line:");
        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
        try writer.print(",has_following_space:{}}}", .{self.has_following_space});
    }

    test "write" {
        const lexeme = Lexeme{
            .lexeme_type = .text,
            .value = "Hello World",
            .line = 1,
            .has_following_space = false,
        };

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try lexeme.write(output.writer());

        try std.testing.expectEqualStrings("Lexeme{lexeme_type:text,value:Hello World,line:1,has_following_space:false}", output.items);
    }
};

const LexerState = struct {
    markdown: []const u8,
    lexemes: LexemeList,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,

    fn scanNewLine(state: *LexerState) error{ OutOfMemory, InvalidHeader }!void {
        if (state.current >= state.markdown.len) return;
        if (state.markdown[state.current] == ' ') {
            if (state.current + 1 >= state.markdown.len) return;
            state.current += 1;
            state.start += 1;
        }

        const char = state.markdown[state.current];

        switch (char) {
            '\\' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.escape);
                // Still process the rest of the line like a new line and handle it in the tokenizer
                try state.scanNewLine();
            },
            '#' => {
                while (state.markdown[state.current] == char) {
                    state.current += 1;
                    if (state.current >= state.markdown.len) break;
                }
                return switch (state.current - state.start) {
                    1 => state.addLexeme(.header_1),
                    2 => state.addLexeme(.header_2),
                    3 => state.addLexeme(.header_3),
                    4 => state.addLexeme(.header_4),
                    5 => state.addLexeme(.header_5),
                    6 => state.addLexeme(.header_6),
                    else => error.InvalidHeader,
                };
            },
            '>' => {
                while (state.markdown[state.current] == '>') {
                    state.current += 1;
                    try state.addLexeme(.blockquote);
                }
                try state.scanNewLine();
            },
            '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                while (state.markdown[state.current] >= '0' and
                    state.markdown[state.current] <= '9') state.current += 1;

                if (state.markdown[state.current] != '.') {
                    state.current = state.start;
                    return;
                }

                state.current += 1;
                try state.addLexeme(.ordered_list);
            },
            '+' => {
                if (state.markdown[state.current + 1] != ' ') return;

                state.current += 1;
                try state.addLexeme(.unordered_list);
            },
            '-', '*' => {
                if (state.current + 1 > state.markdown.len) return;
                // Check if it is an unordered list
                if (state.markdown[state.current + 1] == ' ') {
                    state.current += 1;
                    try state.addLexeme(.unordered_list);
                    return;
                }
                if (state.markdown[state.current + 1] != char) return;

                // Return if the horizontal rule doesn't start the the start of the line
                if (state.current > 0 and state.markdown[state.current - 1] != '\n') return;

                var count: usize = 1;
                while (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] == char) count += 1;

                if (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] != '\n')
                    return;

                if (count >= 3) {
                    state.current += count;
                    try state.addLexeme(.horizontal_rule);
                }
            },
            '_' => {
                // Return if the horizontal rule doesn't start the the start of the line
                if (state.current > 0 and state.markdown[state.current - 1] != '\n') return;

                var count: usize = 1;
                while (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] == char) count += 1;

                if (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] != '\n')
                    return;

                if (count >= 3) {
                    state.current += count;
                    try state.addLexeme(.horizontal_rule);
                }
            },
            '`' => {
                // Return if the code block doesn't start the the start of the line
                if (state.current > 0 and state.markdown[state.current - 1] != '\n') return;

                if (!state.matches(3)) return;
                try state.addLexeme(.code_block);

                if (state.current < state.markdown.len and
                    std.ascii.isWhitespace(state.markdown[state.current])) return;

                while (state.current < state.markdown.len and
                    state.markdown[state.current] != '\n') state.current += 1;

                try state.addLexeme(.code_lang);
            },
            '$' => {
                // Return if the math block doesn't start the the start of the line
                if (state.current > 0 and state.markdown[state.current - 1] != '\n') return;

                var count: usize = 1;
                while (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] == char) count += 1;

                if (state.current + count < state.markdown.len and
                    state.markdown[state.current + count] != '\n')
                    return;

                if (count == 2) {
                    state.current += count;
                    try state.addLexeme(.math_block);
                }
            },
            ' ' => {
                // Adjust to skipping first space
                state.current -= 1;
                state.start -= 1;
                while (state.matches(4)) try state.addLexeme(.indent);
                while (state.markdown[state.current] == ' ') state.current += 1;
                state.start = state.current;
                try state.scanNewLine();
            },
            '\t' => {
                while (state.markdown[state.current] == '\t') {
                    state.current += 1;
                    try state.addLexeme(.indent);
                }
                try state.scanNewLine();
            },
            else => state.current = state.start,
        }
    }

    fn scanLexeme(state: *LexerState) error{ OutOfMemory, InvalidHeader }!void {
        switch (state.markdown[state.current]) {
            '<' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.html_start);
            },
            '>' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.html_end);
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
                    try state.addLexeme(.forced_newline);
                    state.line += 1;
                    try state.scanNewLine();
                } else {
                    state.current += 1;
                    state.start = state.current;
                }
            },
            '`' => {
                try state.addLexeme(.text);
                if (state.matches(2))
                    try state.addLexeme(.code_escaped)
                else if (state.matches(1))
                    try state.addLexeme(.code);
            },
            '!' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.image_start);
            },
            '[' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.alt_start);
            },
            ']' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.alt_end);
            },
            '(' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.url_start);
            },
            ')' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.url_end);
            },
            '$' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.math);
            },
            '&' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.ampersand);
            },
            '\t', '\r' => {
                try state.addLexeme(.text);
                state.start += 1;
                state.current += 1;
            },
            '\n' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.newline);
                state.line += 1;
                try state.scanNewLine();
            },
            '\\' => {
                try state.addLexeme(.text);
                state.current += 1;
                try state.addLexeme(.escape);
            },
            else => state.current += 1,
        }
    }

    fn addLexeme(state: *LexerState, lexeme_type: TokenType) error{OutOfMemory}!void {
        if (state.current > state.markdown.len) return;
        if (state.start >= state.current) return;

        const has_following_space = if (state.current < state.markdown.len) blk: {
            const char = state.markdown[state.current];
            break :blk char == ' ' or char == '\n' or char == '\t' or char == '\r';
        } else false;

        try state.lexemes.append(.{
            .lexeme_type = lexeme_type,
            .value = state.markdown[state.start..state.current],
            .line = state.line,
            .has_following_space = has_following_space,
        });
        state.start = state.current;
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

    fn matchesString(self: *LexerState, comptime string: []const u8) bool {
        if (self.current + string.len > self.markdown.len) return false;
        if (!std.mem.eql(u8, self.markdown[self.current..][0..string.len], string)) return false;

        self.current += string.len;
        return true;
    }

    test "scanNewLine Do Nothing" {
        var state = LexerState{
            .markdown = "\n ### Test doing nothing",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Begining Extra Space" {
        var state = LexerState{
            .markdown = " # Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_1, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Escaped Header" {
        var state = LexerState{
            .markdown = "\\# Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.escape, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("\\", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.header_1, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(true, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Single Space Indent" {
        var state = LexerState{
            .markdown = "    # Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.indent, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("    ", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.header_1, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(true, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Multiple Space Indent" {
        var state = LexerState{
            .markdown = "        # Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.indent, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("    ", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.indent, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("    ", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(.header_1, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);
        try std.testing.expectEqual(true, state.lexemes.items[2].has_following_space);
        try std.testing.expectEqual(9, state.start);
        try std.testing.expectEqual(9, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Single Tab Indent" {
        var state = LexerState{
            .markdown = "\t# Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.indent, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("\t", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.header_1, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(true, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Multiple Tab Indent" {
        var state = LexerState{
            .markdown = "\t\t# Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.indent, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("\t", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.indent, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("\t", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(.header_1, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);
        try std.testing.expectEqual(true, state.lexemes.items[2].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header EOF" {
        var state = LexerState{
            .markdown = "#",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_1, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 1" {
        var state = LexerState{
            .markdown = "# Test header 1",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_1, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("#", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 2" {
        var state = LexerState{
            .markdown = "## Test header 2",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_2, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("##", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 3" {
        var state = LexerState{
            .markdown = "### Test header 3",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_3, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("###", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 4" {
        var state = LexerState{
            .markdown = "#### Test header 4",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_4, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("####", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(4, state.start);
        try std.testing.expectEqual(4, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 5" {
        var state = LexerState{
            .markdown = "##### Test header 5",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_5, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("#####", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Header 6" {
        var state = LexerState{
            .markdown = "###### Test header 6",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.header_6, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("######", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(6, state.start);
        try std.testing.expectEqual(6, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Invalid Header" {
        var state = LexerState{
            .markdown = "####### Test Invalid Header",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try std.testing.expectError(error.InvalidHeader, state.scanNewLine());

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Single Blockquote" {
        var state = LexerState{
            .markdown = "> Test single blockquote",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.blockquote, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings(">", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Multiple Blockquote" {
        var state = LexerState{
            .markdown = ">>> Test single blockquote",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.blockquote, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings(">", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.blockquote, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings(">", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(.blockquote, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings(">", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);
        try std.testing.expectEqual(true, state.lexemes.items[2].has_following_space);
        try std.testing.expectEqual(4, state.start);
        try std.testing.expectEqual(4, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Ordered List" {
        var state = LexerState{
            .markdown = "3823. Test ordered list",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.ordered_list, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("3823.", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Non-Ordered List" {
        var state = LexerState{
            .markdown = "3823 Test not quite an ordered list",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Not Unordered List" {
        var state = LexerState{
            .markdown = "-Test not an unordered list.",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Unordered List" {
        var state = LexerState{
            .markdown = "- Test unordered list",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.unordered_list, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("-", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Not Unordered List" {
        var state = LexerState{
            .markdown = "*Test not an unordered list. This should be italic",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Unordered List" {
        var state = LexerState{
            .markdown = "* Test unordered list",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.unordered_list, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("*", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '+' Not Unordered List" {
        var state = LexerState{
            .markdown = "+Test not an unordered list.",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '+' Unordered List" {
        var state = LexerState{
            .markdown = "+ Test unordered list",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.unordered_list, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("+", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Code Block" {
        var state = LexerState{
            .markdown = "```",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.code_block, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("```", state.lexemes.items[0].value);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine Code Block With Language" {
        var state = LexerState{
            .markdown = "```zig",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.code_block, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("```", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.code_lang, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("zig", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(6, state.start);
        try std.testing.expectEqual(6, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Not Horizontal Rule" {
        var state = LexerState{
            .markdown = "--",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Not Horizontal Rule Text After" {
        var state = LexerState{
            .markdown = "---test",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Horizontal Rule Minimum" {
        var state = LexerState{
            .markdown = "---",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("---", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '-' Horizontal Rule Many" {
        var state = LexerState{
            .markdown = "---------------",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("---------------", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(15, state.start);
        try std.testing.expectEqual(15, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Not Horizontal Rule" {
        var state = LexerState{
            .markdown = "**",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Not Horizontal Rule Text After" {
        var state = LexerState{
            .markdown = "***test",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Horizontal Rule Minimum" {
        var state = LexerState{
            .markdown = "***",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("***", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '*' Horizontal Rule Many" {
        var state = LexerState{
            .markdown = "***************",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("***************", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(15, state.start);
        try std.testing.expectEqual(15, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '_' Not Horizontal Rule" {
        var state = LexerState{
            .markdown = "__",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '_' Horizontal Rule Minimum" {
        var state = LexerState{
            .markdown = "___",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("___", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '_' Not Horizontal Rule Text After" {
        var state = LexerState{
            .markdown = "___test",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(0, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanNewLine '_' Horizontal Rule Many" {
        var state = LexerState{
            .markdown = "_______________",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanNewLine();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.horizontal_rule, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("_______________", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(15, state.start);
        try std.testing.expectEqual(15, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Text" {
        var state = LexerState{
            .markdown = "test",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(0, state.lexemes.items.len);
        try std.testing.expectEqual(0, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Space" {
        var state = LexerState{
            .markdown = "test ",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 4,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Tab" {
        var state = LexerState{
            .markdown = "test\t",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 4,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Return" {
        var state = LexerState{
            .markdown = "test\r",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 4,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme New Line" {
        var state = LexerState{
            .markdown = "test\n",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 4,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.newline, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("\n", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(5, state.start);
        try std.testing.expectEqual(5, state.current);
        try std.testing.expectEqual(2, state.line);
    }

    test "scanLexeme HTML Start" {
        var state = LexerState{
            .markdown = "test <html>",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 5,
            .current = 5,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.html_start, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("<", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(6, state.start);
        try std.testing.expectEqual(6, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme HTML End" {
        var state = LexerState{
            .markdown = "test <html>",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 10,
            .current = 10,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.html_end, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings(">", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(11, state.start);
        try std.testing.expectEqual(11, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '*' Italic" {
        var state = LexerState{
            .markdown = "*italic*",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.italic, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("*", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '_' Italic" {
        var state = LexerState{
            .markdown = "_italic_",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.italic, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("_", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '*' Bold" {
        var state = LexerState{
            .markdown = "**bold**",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '_' Bold" {
        var state = LexerState{
            .markdown = "__bold__",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("__", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '*' Bold and Italic" {
        var state = LexerState{
            .markdown = "***bold italic***",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold_italic, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("***", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme '_' Bold and Italic" {
        var state = LexerState{
            .markdown = "___bold italic___",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold_italic, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("___", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(3, state.start);
        try std.testing.expectEqual(3, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Forced Newline" {
        var state = LexerState{
            .markdown = "test  \n",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 4,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(.forced_newline, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("  \n", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);
        try std.testing.expectEqual(7, state.start);
        try std.testing.expectEqual(7, state.current);
        try std.testing.expectEqual(2, state.line);
    }

    test "scanLexeme Code" {
        var state = LexerState{
            .markdown = "`code`",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.code, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("`", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Code Escaped" {
        var state = LexerState{
            .markdown = "`````",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.code_escaped, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("``", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Image Start" {
        var state = LexerState{
            .markdown = "![Image](url)",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.image_start, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("!", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Alt Start" {
        var state = LexerState{
            .markdown = "![Image](url)",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 1,
            .current = 1,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.alt_start, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("[", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(2, state.start);
        try std.testing.expectEqual(2, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Alt End" {
        var state = LexerState{
            .markdown = "![Image](url)",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 7,
            .current = 7,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.alt_end, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("]", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(8, state.start);
        try std.testing.expectEqual(8, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme URL Start" {
        var state = LexerState{
            .markdown = "![Image](url)",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 8,
            .current = 8,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.url_start, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("(", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(9, state.start);
        try std.testing.expectEqual(9, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme URL End" {
        var state = LexerState{
            .markdown = "![Image](url)",
            .lexemes = LexemeList.init(std.testing.allocator),
            .start = 12,
            .current = 12,
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.url_end, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings(")", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(13, state.start);
        try std.testing.expectEqual(13, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "scanLexeme Ampersand" {
        var state = LexerState{
            .markdown = "&",
            .lexemes = LexemeList.init(std.testing.allocator),
        };
        defer state.lexemes.deinit();

        try state.scanLexeme();

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.ampersand, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("&", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(false, state.lexemes.items[0].has_following_space);
        try std.testing.expectEqual(1, state.start);
        try std.testing.expectEqual(1, state.current);
        try std.testing.expectEqual(1, state.line);
    }

    test "addLexeme" {
        var state = LexerState{
            .markdown = "** test**more",
            .lexemes = LexemeList.init(std.testing.allocator),
            .current = 2,
        };
        defer state.lexemes.deinit();

        try state.addLexeme(.bold);

        try std.testing.expectEqual(1, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[0].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[0].value);
        try std.testing.expectEqual(1, state.lexemes.items[0].line);
        try std.testing.expectEqual(true, state.lexemes.items[0].has_following_space);

        state.start += 1;
        state.current += 5;
        try state.addLexeme(.text);

        try std.testing.expectEqual(2, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[1].lexeme_type);
        try std.testing.expectEqualStrings("test", state.lexemes.items[1].value);
        try std.testing.expectEqual(1, state.lexemes.items[1].line);
        try std.testing.expectEqual(false, state.lexemes.items[1].has_following_space);

        state.current += 2;
        try state.addLexeme(.bold);

        try std.testing.expectEqual(3, state.lexemes.items.len);
        try std.testing.expectEqual(.bold, state.lexemes.items[2].lexeme_type);
        try std.testing.expectEqualStrings("**", state.lexemes.items[2].value);
        try std.testing.expectEqual(1, state.lexemes.items[2].line);
        try std.testing.expectEqual(false, state.lexemes.items[2].has_following_space);

        state.current += 4;
        try state.addLexeme(.text);

        try std.testing.expectEqual(4, state.lexemes.items.len);
        try std.testing.expectEqual(.text, state.lexemes.items[3].lexeme_type);
        try std.testing.expectEqualStrings("more", state.lexemes.items[3].value);
        try std.testing.expectEqual(1, state.lexemes.items[3].line);
        try std.testing.expectEqual(false, state.lexemes.items[3].has_following_space);

        // Ignore zero-length strings
        try state.addLexeme(.text);
        try std.testing.expectEqual(4, state.lexemes.items.len);

        // Gracefully handle overrunning the markdown
        state.current += 1;
        try state.addLexeme(.text);
        try std.testing.expectEqual(4, state.lexemes.items.len);
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

pub fn process(allocator: std.mem.Allocator, markdown: []const u8) error{ OutOfMemory, InvalidHeader }!LexemeList {
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

    if (state.start < state.current) try state.addLexeme(.text);

    return state.lexemes;
}

test "process" {
    const markdown = "**This is a test**\nNot really for much though...  \n\nBallz\n";

    const lexemes = try process(std.testing.allocator, markdown);
    defer lexemes.deinit();

    try std.testing.expectEqual(16, lexemes.items.len);
    try std.testing.expectEqual(.bold, lexemes.items[0].lexeme_type);
    try std.testing.expectEqualStrings("**", lexemes.items[0].value);
    try std.testing.expectEqual(1, lexemes.items[0].line);
    try std.testing.expectEqual(.text, lexemes.items[1].lexeme_type);
    try std.testing.expectEqualStrings("This", lexemes.items[1].value);
    try std.testing.expectEqual(1, lexemes.items[1].line);
    try std.testing.expectEqual(.text, lexemes.items[2].lexeme_type);
    try std.testing.expectEqualStrings("is", lexemes.items[2].value);
    try std.testing.expectEqual(1, lexemes.items[2].line);
    try std.testing.expectEqual(.text, lexemes.items[3].lexeme_type);
    try std.testing.expectEqualStrings("a", lexemes.items[3].value);
    try std.testing.expectEqual(1, lexemes.items[3].line);
    try std.testing.expectEqual(.text, lexemes.items[4].lexeme_type);
    try std.testing.expectEqualStrings("test", lexemes.items[4].value);
    try std.testing.expectEqual(1, lexemes.items[4].line);
    try std.testing.expectEqual(.bold, lexemes.items[5].lexeme_type);
    try std.testing.expectEqualStrings("**", lexemes.items[5].value);
    try std.testing.expectEqual(1, lexemes.items[5].line);
    try std.testing.expectEqual(.newline, lexemes.items[6].lexeme_type);
    try std.testing.expectEqualStrings("\n", lexemes.items[6].value);
    try std.testing.expectEqual(1, lexemes.items[6].line);
    try std.testing.expectEqual(.text, lexemes.items[7].lexeme_type);
    try std.testing.expectEqualStrings("Not", lexemes.items[7].value);
    try std.testing.expectEqual(2, lexemes.items[7].line);
    try std.testing.expectEqual(.text, lexemes.items[8].lexeme_type);
    try std.testing.expectEqualStrings("really", lexemes.items[8].value);
    try std.testing.expectEqual(2, lexemes.items[8].line);
    try std.testing.expectEqual(.text, lexemes.items[9].lexeme_type);
    try std.testing.expectEqualStrings("for", lexemes.items[9].value);
    try std.testing.expectEqual(2, lexemes.items[9].line);
    try std.testing.expectEqual(.text, lexemes.items[10].lexeme_type);
    try std.testing.expectEqualStrings("much", lexemes.items[10].value);
    try std.testing.expectEqual(2, lexemes.items[10].line);
    try std.testing.expectEqual(.text, lexemes.items[11].lexeme_type);
    try std.testing.expectEqualStrings("though...", lexemes.items[11].value);
    try std.testing.expectEqual(2, lexemes.items[11].line);
    try std.testing.expectEqual(.forced_newline, lexemes.items[12].lexeme_type);
    try std.testing.expectEqualStrings("  \n", lexemes.items[12].value);
    try std.testing.expectEqual(2, lexemes.items[12].line);
    try std.testing.expectEqual(.newline, lexemes.items[13].lexeme_type);
    try std.testing.expectEqualStrings("\n", lexemes.items[13].value);
    try std.testing.expectEqual(3, lexemes.items[13].line);
    try std.testing.expectEqual(.text, lexemes.items[14].lexeme_type);
    try std.testing.expectEqualStrings("Ballz", lexemes.items[14].value);
    try std.testing.expectEqual(4, lexemes.items[14].line);
    try std.testing.expectEqual(.newline, lexemes.items[15].lexeme_type);
    try std.testing.expectEqualStrings("\n", lexemes.items[15].value);
    try std.testing.expectEqual(4, lexemes.items[15].line);
}

test "process Empty" {
    const lexemes = try process(std.testing.allocator, "");
    defer lexemes.deinit();

    try std.testing.expectEqual(0, lexemes.items.len);
}
