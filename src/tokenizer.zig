const std = @import("std");

//const TokenList = std.ArrayList(Token);

const eql = std.mem.eql;
const assert = std.debug.assert;

pub const TokenType = enum {
    indent,
    text,
    newline,
    forced_newline,
    html,
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

    pub fn isEscapeable(self: TokenType) bool {
        return self != .text and self != .newline and self != .forced_newline;
    }
};

//pub const Token = struct {
//    token_type: TokenType,
//    value: union(enum) {
//        lexeme: []const u8,
//        children: TokenList,
//    },
//    line: usize,
//
//    pub fn getLexeme(self: Token) []const u8 {
//        return switch (self.value) {
//            .lexeme => |lexeme| lexeme,
//            .children => |children| blk: {
//                if (children.items.len < 1) break :blk "";
//
//                const lexeme_start = children.items[0].getLexeme();
//                const lexeme_end = children.items[children.items.len - 1].getLexeme();
//
//                const index_start: usize = @intFromPtr(lexeme_start.ptr);
//                const index_end = @as(usize, lexeme_end.ptr) + lexeme_end.len;
//
//                break :blk lexeme_start.ptr[0 .. index_end - index_start];
//            },
//        };
//    }
//
//    pub fn write(self: Token, writer: anytype) !void {
//        try writer.writeAll("Token{token_type:");
//        try writer.writeAll(@tagName(self.token_type));
//        try writer.writeAll(",lexeme:");
//        var iterator = std.mem.splitScalar(u8, self.lexeme, '\n');
//        while (iterator.next()) |line| {
//            try writer.writeAll(line);
//            if (iterator.peek() != null)
//                try writer.writeAll("\\n");
//        }
//        try writer.writeAll(",line:");
//        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
//        try writer.writeByte('}');
//    }
//
//    test "write" {
//        const token = Token{
//            .token_type = .text,
//            .lexeme = "Hello World",
//            .children = null,
//            .line = 1,
//        };
//
//        var output = std.ArrayList(u8).init(std.testing.allocator);
//        defer output.deinit();
//
//        try token.write(output.writer());
//
//        try std.testing.expectEqualStrings("Token{token_type:text,lexeme:Hello World,line:1}", output.items);
//    }
//};
//
//pub fn tokenize(allocator: std.mem.Allocator, lexemes: @import("lexer.zig").LexemeList) !TokenList {
//    assert(state.markdown.len > 0);
//    while (state.current < state.markdown.len) {
//        try state.scanToken();
//    }
//
//    if (state.start < state.current) try state.addText();
//
//    var writer = std.io.getStdOut().writer();
//    for (state.tokens.items) |token| {
//        try token.write(writer);
//        try writer.writeByte('\n');
//    }
//
//    try writer.writeAll("---------------\n");
//
//    try cleanTokens(&state.tokens);
//
//    for (state.tokens.items) |token| {
//        try token.write(writer);
//        try writer.writeByte('\n');
//    }
//
//    return state.tokens;
//}
//
//fn cleanTokens(tokens: *TokenList) !void {
//    var new_tokens = TokenList.init(tokens.allocator);
//
//    var i: usize = 0;
//
//    // Handle metadata
//    //if (tokens.items[0].token_type == .horizontal_rule) {
//    //    while (i < tokens.items.len and tokens.items[i].token_type != .horizontal_rule) i += 1;
//
//    //    const end_token = tokens.items[i];
//    //    const end_ptr_int = @as(usize, @intFromPtr(end_token.lexeme.ptr)) + end_token.lexeme.len;
//    //    const start_ptr_int: usize = @intFromPtr(tokens.items[0].lexeme.ptr);
//
//    //    try new_tokens.append(.{
//    //        .token_type = .metadata,
//    //        .lexeme = tokens.items[0].lexeme[0 .. end_ptr_int - start_ptr_int],
//    //        .line = 1,
//    //    });
//    //}
//
//    while (i < tokens.items.len) : (i += 1) {
//        const token = tokens.items[i];
//        switch (token.token_type) {
//            .header_1, .header_2, .header_3, .header_4, .header_5, .header_6 => {
//                try combineNewLine(token.token_type, &i, tokens, &new_tokens);
//            },
//            .bold, .italic, .bold_italic => {
//                try combine(token.token_type, false, &i, tokens, &new_tokens);
//            },
//            else => try new_tokens.append(token),
//        }
//    }
//
//    tokens.deinit();
//    tokens.* = new_tokens;
//}
//
//fn combineNewLine(
//    token_type: TokenType,
//    index: *usize,
//    tokens: *const TokenList,
//    new_tokens: *TokenList,
//) !void {
//    const start_index = index.* + 1;
//    while (index.* < tokens.items.len and
//        tokens.items[index.*].token_type != .newline) index.* += 1;
//
//    const start_token = tokens.items[start_index];
//    const end_token = tokens.items[index.* - 1];
//
//    const start: usize = @intFromPtr(start_token.lexeme.ptr);
//    const end = @as(usize, @intFromPtr(end_token.lexeme.ptr)) + end_token.lexeme.len;
//    const total_len = end - start;
//
//    return new_tokens.append(.{
//        .token_type = token_type,
//        .lexeme = start_token.lexeme.ptr[0..total_len],
//        .line = start_token.line,
//    });
//}
//
//fn combine(
//    token_type: TokenType,
//    comptime is_multiline: bool,
//    index: *usize,
//    tokens: *const TokenList,
//    new_tokens: *TokenList,
//) !void {
//    const start_index = index.*;
//    const start_token = tokens.items[start_index];
//    std.log.debug("{s} {s}", .{ @tagName(token_type), @tagName(start_token.token_type) });
//
//    index.* += 1;
//    while (tokens.items[index.*].token_type != token_type) : (index.* += 1) {
//        const token = tokens.items[index.*];
//        std.log.debug("{s}", .{@tagName(token.token_type)});
//        // Handle if the line ends before the closing tag
//        if (!is_multiline and
//            (token.token_type == .newline or
//            token.token_type == .forced_newline))
//        {
//            index.* = start_index;
//            return new_tokens.append(.{
//                .token_type = .text,
//                .lexeme = start_token.lexeme,
//                .line = start_token.line,
//            });
//        }
//    }
//
//    const start: usize = @intFromPtr(start_token.lexeme.ptr) + start_token.lexeme.len;
//    const end = @as(usize, @intFromPtr(tokens.items[index.*].lexeme.ptr)) +
//        tokens.items[index.*].lexeme.len;
//    const total_len = end - start;
//
//    return new_tokens.append(.{
//        .token_type = token_type,
//        .lexeme = tokens.items[start_index].lexeme.ptr[start_token.lexeme.len..total_len],
//        .line = tokens.items[start_index].line,
//    });
//}
