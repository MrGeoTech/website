const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const CompileState = struct {
    html: *std.ArrayList(u8),
    token: *const tokenizer.Token,
};

pub fn compile(allocator: std.mem.Allocator, tokens: tokenizer.TokenList) error{OutOfMemory}![]u8 {
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html.deinit();

    var index: usize = 0;
    while (index < tokens.tokens.len) : (index += 1)
        appendToken(.{ .html = &html, .token = &tokens[index]});

    return allocator.dupe(u8, html.items);
}

fn appendToken(state: CompileState) error{OutOfMemory}!void {

}

fn appendLexeme(state: CompileState, with_trailing_space: bool) error{OutOfMemory}!void {

}
