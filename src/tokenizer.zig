const std = @import("std");

pub const TokenType = enum {
    text,
    newline,
    escape,
    bold,
    italic,
    math,
    math_block,
    code,
    code_block,
};

pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    line: usize,
};

pub fn tokenize(allocator: std.mem.Allocator, markdown: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);

    var start: usize = 0;
    var current: usize = 0;
    var line: usize = 1;

    while (current < markdown.len) {
        start = current;
        try scanToken(&tokens, markdown, &start, &current, &line);
    }

    return tokens;
}

fn scanToken(
    tokens: *std.ArrayList(Token),
    markdown: []const u8,
    start: *const usize,
    current: *usize,
    line: *usize,
) !void {
    current.* += 1;
    switch (markdown[current]) {
        '\\' => try tokens.append(.{
            .token_type = .escape,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }),
        '`' => if (matches(markdown, current, "``")) tokens.append(.{
            .token_type = .code_block,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }) else tokens.append(.{
            .token_type = .code,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }),
        '$' => if (matches(markdown, current, "$")) tokens.append(.{
            .token_type = .math_block,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }) else tokens.append(.{
            .token_type = .math,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }),
        '*' => if (matches(markdown, current, "*")) tokens.append(.{
            .token_type = .bold,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }) else tokens.append(.{
            .token_type = .italic,
            .lexeme = markdown[start.*..current.*],
            .line = line.*,
        }),
    }
}

fn matches(markdown: []const u8, current: *usize, string: []const u8) bool {
    if (current.* + string.len >= markdown.len) return false;
    if (!std.mem.eql(u8, markdown[current.*..][0..string.len], string)) return false;

    current.* += string.len;
    return true;
}
