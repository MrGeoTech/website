const std = @import("std");

const Token = @import("token.zig");
const TokenList = struct {
    list: *std.ArrayList(Token),

    pub fn init(allocator: std.mem.Allocator) !TokenList {
        const list = try allocator.create(std.ArrayList(Token));
        list.* = std.ArrayList(Token).init(allocator);
        return .{ .list = list };
    }

    pub fn replaceWith(self: TokenList, new_self: TokenList) void {
        self.deinit();
        self.list.* = new_self.list.*;
    }

    pub fn deinit(self: TokenList) void {
        const allocator = self.list.allocator;

        for (self.list.items) |item| {
            allocator.free(item.active_effects);
        }
        self.list.deinit();
        allocator.destroy(self.list);
    }

    pub fn toHtml(self: TokenList) ![]const u8 {
        var html = std.ArrayList(u8).init(self.list.allocator);
        defer html.deinit();

        for (self.list.items) |token| {
            for (token.active_effects) |effect| {
                try effect.appendStart(&html);
            }
            try html.appendSlice(token.contents);
            for (token.active_effects) |effect| {
                try effect.appendEnd(&html);
            }
        }

        return try self.list.allocator.dupe(u8, html.items);
    }
};

pub fn tokenize(allocator: std.mem.Allocator, markdown: []const u8) !TokenList {
    var tokens = try TokenList.init(allocator);
    errdefer tokens.deinit();

    // Add markdown as a token
    try tokens.list.append(.{
        .contents = markdown,
        .active_effects = try allocator.alloc(Token.TextEffect, 0),
    });

    try tokenizeMath(tokens);
    try tokenizeNewLines(tokens);
    try tokenizeBold(tokens);
    try tokenizeItalics(tokens);

    return tokens;
}

pub fn tokenizeMath(tokens: TokenList) !void {
    const allocator = tokens.list.allocator;

    var new_tokens = try TokenList.init(allocator);
    errdefer new_tokens.deinit();

    for (tokens.list.items) |token| {
        // Find math blocks
        try addSplitTokens(token, new_tokens, "$$", .math);
        // Find inline math
        try addSplitTokens(token, new_tokens, "$", .math);
    }

    // Update tokens to new tokens
    tokens.replaceWith(new_tokens);
}

pub fn tokenizeNewLines(tokens: TokenList) !void {
    const allocator = tokens.list.allocator;

    var new_tokens = try TokenList.init(allocator);
    errdefer new_tokens.deinit();

    for (tokens.list.items) |token| {
        if (token.active_effects.len > 0) continue;

        var split_iterator = std.mem.split(u8, token.contents, "\n");
        if (split_iterator.peek() != null) {
            while (split_iterator.next()) |item| {
                if (split_iterator.peek() == null) {
                    try new_tokens.list.append(.{ .contents = item, .active_effects = try allocator.dupe(Token.TextEffect, token.active_effects) });
                } else {
                    try new_tokens.list.append(.{
                        .contents = item,
                        .active_effects = try append(Token.TextEffect, allocator, token.active_effects, .newline),
                    });
                }
            }
        }
    }

    // Update tokens to new tokens
    tokens.replaceWith(new_tokens);
}

pub fn tokenizeBold(tokens: TokenList) !void {
    const allocator = tokens.list.allocator;

    var new_tokens = try TokenList.init(allocator);
    errdefer new_tokens.deinit();

    for (tokens.list.items) |token| {
        var should_continue = false;
        for (token.active_effects) |effect| {
            if (effect == .math) {
                should_continue = true;
                break;
            }
        }
        if (should_continue) continue;

        // Find bold blocks
        try addSplitTokens(token, new_tokens, "**", .bold);
    }

    // Update tokens to new tokens
    tokens.replaceWith(new_tokens);
}

pub fn tokenizeItalics(tokens: TokenList) !void {
    const allocator = tokens.list.allocator;

    var new_tokens = try TokenList.init(allocator);
    errdefer new_tokens.deinit();

    for (tokens.list.items) |token| {
        var should_continue = false;
        for (token.active_effects) |effect| {
            if (effect == .math) {
                should_continue = true;
                break;
            }
        }
        if (should_continue) continue;

        // Find bold blocks
        try addSplitTokens(token, new_tokens, "*", .italic);
    }

    // Update tokens to new tokens
    tokens.replaceWith(new_tokens);
}

fn addSplitTokens(
    token: Token,
    new_tokens: TokenList,
    comptime needle: []const u8,
    comptime effect: Token.TextEffect,
) !void {
    const allocator = new_tokens.list.allocator;

    var split_iterator = std.mem.split(u8, token.contents, needle);
    if (split_iterator.peek() != null) {
        var is_enabled = false;
        while (split_iterator.next()) |item| {
            std.log.debug("--------------\n{s}", .{item});
            if (is_enabled) {
                try new_tokens.list.append(.{
                    .contents = item,
                    .active_effects = try append(Token.TextEffect, allocator, token.active_effects, effect),
                });
            } else {
                try new_tokens.list.append(.{ .contents = item, .active_effects = try allocator.dupe(Token.TextEffect, token.active_effects) });
            }
            is_enabled = !is_enabled;
        }
    }
}

fn append(comptime T: anytype, allocator: std.mem.Allocator, current: []const T, new_item: T) ![]T {
    const new_array = try allocator.alloc(T, current.len + 1);
    @memcpy(new_array[0..current.len], current);
    new_array[current.len] = new_item;
    return new_array;
}
