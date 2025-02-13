const std = @import("std");

const Token = @import("token.zig");
const TokenList = struct {
    list: std.ArrayList(Token),

    pub fn deinit(self: *TokenList) void {
        for (self.list.items) |item| {
            self.list.allocator.free(item.active_effects);
        }
        self.list.deinit();
    }
};

pub fn tokenizeMath(tokens: *TokenList) !void {
    const allocator = tokens.list.allocator;

    var new_tokens = try allocator.create(TokenList);
    errdefer allocator.destroy(new_tokens);
    new_tokens.* = .{ .list = std.ArrayList(Token).init(allocator) };
    errdefer new_tokens.deinit();

    for (tokens.items) |token| {
        // Find math blocks
        var split_iterator = std.mem.split(u8, token.contents, "$$");
        if (split_iterator.peek() != null) {
            var is_math_block = false;
            while (split_iterator.next()) |item| {
                if (is_math_block) {
                    new_tokens.list.append(.{
                        .contents = item,
                        .effects = try append(Token.TextEffect, allocator, token.effects, .math),
                    });
                } else {
                    new_tokens.list.append(.{ .contents = item, .active_effects = try allocator.dupe(Token.TextEffect, token) });
                }
                is_math_block = !is_math_block;
            }
        }
        // Find inline math
    }

    // Update tokens to new tokens
    tokens.deinit();
    tokens.allocator.destroy(tokens);
    tokens = new_tokens;
}

fn append(comptime T: anytype, allocator: std.mem.Allocator, current: []const T, new_item: T) ![]T {
    const new_array = allocator.realloc(current.*, current.*.len + 1);
    new_array[current.len] = new_item;
    return new_array;
}
