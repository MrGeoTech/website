const std = @import("std");

const Token = @import("tokenizer.zig").Token;

pub fn compileToHTML(allocator: std.mem.Allocator, tokens: std.ArrayList(Token)) !std.ArrayList(u8) {
    var html = std.ArrayList(u8).init(allocator);
}
