const std = @import("std");

const Token = @This();

pub const TextEffect = enum {
    newline,
    math,
    math_block,
    bold,
    italic,

    pub fn appendStart(self: TextEffect, html: *std.ArrayList(u8)) !void {
        switch (self) {
            .newline => {},
            .math => try html.appendSlice("$"),
            .math_block => try html.appendSlice("$$"),
            .bold => try html.appendSlice("<strong>"),
            .italic => try html.appendSlice("<em>"),
        }
    }

    pub fn appendEnd(self: TextEffect, html: *std.ArrayList(u8)) !void {
        switch (self) {
            .newline => try html.appendSlice("\n"),
            .math => try html.appendSlice("$"),
            .math_block => try html.appendSlice("$$"),
            .bold => try html.appendSlice("</strong>"),
            .italic => try html.appendSlice("</em>"),
        }
    }
};

contents: []const u8,
active_effects: []TextEffect,
