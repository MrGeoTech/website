const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const ByteArrayList = std.ArrayList(u8);

const CompileState = struct {
    allocator: std.mem.Allocator,
    html: ByteArrayList.Writer,
    tokens: []const tokenizer.Token,
    current: usize = 0,
    is_in_paragraph: bool = false,
};

pub const CompileOptions = struct {
    text_children: bool = false,
    ignore_paragraph_start: bool = false,
    ignore_paragraph_end: bool = false,
    ignore_paragraph_children_end: bool = false,
};

const assert = std.debug.assert;

const should_compress = @import("builtin").mode != .Debug;

pub fn compile(
    allocator: std.mem.Allocator,
    tokens: tokenizer.TokenList,
    comptime options: CompileOptions,
) error{OutOfMemory}![]u8 {
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html.deinit();

    try html.appendSlice("<div id=\"markdown\">");

    var state = CompileState{
        .allocator = html.allocator,
        .html = html.writer(),
        .tokens = tokens.tokens,
    };
    while (state.current < tokens.tokens.len) : (state.current += 1) {
        try appendToken(&state, options);
    }

    try html.appendSlice("</div>");

    return allocator.dupe(u8, html.items);
}

fn appendToken(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    try switch (state.tokens[state.current].token_type) {
        .metadata => return,
        .header_1 => append(state, &.{"h1"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .header_2 => append(state, &.{"h2"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .header_3 => append(state, &.{"h3"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .header_4 => append(state, &.{"h4"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .header_5 => append(state, &.{"h5"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .header_6 => append(state, &.{"h6"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .forced_newline => appendBreak(state, options),
        .bold => append(state, &.{"strong"}, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }),
        .italic => append(state, &.{"em"}, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }),
        .bold_italic => append(state, &.{ "strong", "em" }, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }),
        .blockquote => append(state, &.{"blockquote"}, .{
            .text_children = false,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .ordered_list, .unordered_list => appendList(state, .{
            .text_children = false,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }),
        .code => append(state, &.{"code"}, .{
            .text_children = true,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }),
        .code_block => append(state, &.{ "pre", "code" }, .{
            .text_children = true,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = options.ignore_paragraph_end,
        }),
        .math => {
            try state.html.writeByte('$');
            try append(state, &.{}, .{
                .text_children = true,
                .ignore_paragraph_start = options.ignore_paragraph_start,
                .ignore_paragraph_end = options.ignore_paragraph_end,
                .ignore_paragraph_children_end = true,
            });
            try state.html.writeByte('$');
        },
        .math_block => {
            try state.html.writeAll("$$\n");
            try append(state, &.{}, .{
                .text_children = true,
                .ignore_paragraph_start = options.ignore_paragraph_start,
                .ignore_paragraph_end = options.ignore_paragraph_end,
            });
            try state.html.writeAll("$$\n");
        },
        .horizontal_rule => appendText(state, "<hr/>", options),
        .image => appendImage(state, options),
        .link => appendLink(state, options),
        .ampersand => appendText(state, "&amp;", options),
        .html_start => appendText(state, "&lt;", options),
        .html_end => appendText(state, "&gt;", options),
        else => {
            try append(state, null, options);
        },
    };
}

fn startParagraph(state: *CompileState) error{OutOfMemory}!void {
    state.is_in_paragraph = true;
    try state.html.writeAll("<p>");
}

fn endParagraph(state: *CompileState) error{OutOfMemory}!void {
    state.is_in_paragraph = false;
    try state.html.writeAll("</p>");
}

fn append(
    state: *CompileState,
    comptime tags: ?[]const []const u8,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.tokens.len > state.current);
    const token = state.tokens[state.current];
    const has_children = std.meta.activeTag(token.value) == .children;

    if (tags) |t| {
        if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);
        if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
        inline for (t) |tag| {
            try state.html.writeAll("<" ++ tag ++ ">");
        }
    } else if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);

    if (has_children and !options.text_children) {
        var s = CompileState{
            .allocator = state.allocator,
            .html = state.html,
            .tokens = token.value.children.tokens,
            .is_in_paragraph = state.is_in_paragraph,
        };
        while (s.current < s.tokens.len) : (s.current += 1) {
            try appendToken(&s, options);
        }
        if (!options.ignore_paragraph_children_end and s.is_in_paragraph) try endParagraph(&s);
    } else {
        try token.writeLexeme(state.html);
    }
    if (token.has_following_space) try state.html.writeByte(' ');

    if (tags) |t| {
        const reverse_tags = comptime blk: {
            var rt: [t.len][]const u8 = undefined;
            @memcpy(&rt, t);
            std.mem.reverse([]const u8, &rt);
            break :blk rt;
        };
        inline for (reverse_tags) |tag| {
            try state.html.writeAll("</" ++ tag ++ ">");
        }
    }
}

fn appendBreak(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);
    if (state.current + 1 < state.tokens.len and
        state.tokens[state.current + 1].token_type == .horizontal_rule)
        return;
    try state.html.writeAll(if (should_compress) "<br/>" else "\n<br/>\n");
}

fn appendList(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(token.token_type == .ordered_list or token.token_type == .unordered_list);
    assert(std.meta.activeTag(token.value) == .children);

    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);

    const is_ordered = token.token_type == .ordered_list;
    try state.html.writeAll(if (is_ordered) @as([]const u8, "<ol>") else "<ul>");
    if (!should_compress) try state.html.writeByte('\n');

    var list_state = CompileState{
        .allocator = state.allocator,
        .html = state.html,
        .tokens = token.value.children.tokens,
        .is_in_paragraph = false,
    };

    while (list_state.current < list_state.tokens.len) : (list_state.current += 1) {
        try append(&list_state, &.{"li"}, .{
            .ignore_paragraph_start = true,
        });
        if (!should_compress) try state.html.writeByte('\n');
    }

    try state.html.writeAll(if (is_ordered) @as([]const u8, "</ol>") else "</ul>");
    if (!should_compress) try state.html.writeByte('\n');
}

fn appendText(
    state: *CompileState,
    text: []const u8,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);
    try state.html.writeAll(text);
}

fn appendImage(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.tokens.len == 2);

    const alt_token = token.value.children.tokens[0];
    const url_token = token.value.children.tokens[1];

    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);
    try state.html.print("<img alt=\"{s}\" src=\"{s}\"/>", .{
        alt_token.value.lexeme,
        url_token.value.lexeme,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}

fn appendLink(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.tokens.len == 2);

    const alt_token = token.value.children.tokens[0];
    const url_token = token.value.children.tokens[1];

    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
    try state.html.print("<a href=\"{s}\">{s}</a>", .{
        url_token.value.lexeme,
        alt_token.value.lexeme,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}
