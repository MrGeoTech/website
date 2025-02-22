const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub const Element = struct {
    contents: []const u8,
    metadata: []const u8,
    effects: std.ArrayList(tokenizer.TokenType),
};
