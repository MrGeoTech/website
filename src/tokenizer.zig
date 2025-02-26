const std = @import("std");
const lexer = @import("lexer.zig");

const LexemeList = std.ArrayList(lexer.Lexeme);
const TokenList = std.ArrayList(Token);

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
        return self != .newline and self != .forced_newline;
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
                if (children.items.len < 1) break :blk "";

                const lexeme_start = children.items[0].getLexeme();
                const lexeme_end = children.items[children.items.len - 1].getLexeme();

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
            .value = .{ .children = try TokenList.initCapacity(std.testing.allocator, 2) },
            .line = 1,
        };
        defer children_token.value.children.deinit();
        children_token.value.children.appendSliceAssumeCapacity(&[_]Token{ lexeme_token1, lexeme_token2 });

        try std.testing.expectEqualStrings("Hello", lexeme_token1.getLexeme());
        try std.testing.expectEqualStrings("World", lexeme_token2.getLexeme());
        try std.testing.expectEqualStrings("Hello World", children_token.getLexeme());

        // No need for a deinit because nothing is every actually allocated.
        const special_case_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList.init(std.testing.allocator) },
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
                for (children.items) |child| {
                    try child.write(writer);
                }
                try writer.writeByte('\n');
            },
        }
        try writer.writeAll(",line:");
        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
        try writer.writeByte('}');
    }

    test "write" {
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
};

pub fn tokenize(lexemes: LexemeList) !TokenList {
    const allocator = lexemes.allocator;

    var tokens = TokenList.init(allocator);
    errdefer tokens.deinit();

    var current_token_list: *TokenList = &tokens;
    var index: usize = 0;
    while (index < lexemes.items.len) : (index += 1) {
        const lexeme = lexemes.items[index];

        switch (lexeme.lexeme_type) {
            .header_1, .header_2, .header_3, .header_4, .header_5, .header_6 => {
                while (index < lexemes.items.len and lexemes.items[index].lexeme_type.isNewLine()) index += 1;
            },
            else => try current_token_list.append(Token.of(lexeme)),
        }
    }

    return tokens;
}
