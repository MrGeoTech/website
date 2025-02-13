const std = @import("std");

const Token = @This();

pub const TextEffect = enum {
    none,
    math,
    bold,
    italic,
};

contents: []const u8,
active_effects: []TextEffect,
