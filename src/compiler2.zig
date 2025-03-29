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
    children_default_options: bool = false,
};

const assert = std.debug.assert;

const should_compress = @import("builtin").mode != .Debug;
const image_url_prefix = "/img?path=";
const link_url_prefix = "/?open=";

pub fn compile(
    allocator: std.mem.Allocator,
    tokens: tokenizer.TokenList,
    current_path: []const u8,
    comptime options: CompileOptions,
) error{OutOfMemory}![]u8 {
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html.deinit();

    var state = CompileState{
        .allocator = html.allocator,
        .html = html.writer(),
        .tokens = tokens.items,
    };
    while (state.current < tokens.items.len) : (state.current += 1) {
        try appendToken(&state, current_path, options);
    }

    return allocator.dupe(u8, html.items);
}

fn appendToken(
    state: *CompileState,
    current_path: []const u8,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    try switch (token.token_type) {
        .metadata => return,
        .header_1 => append(state, &.{"h1"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .header_2 => append(state, &.{"h2"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .header_3 => append(state, &.{"h3"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .header_4 => append(state, &.{"h4"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .header_5 => append(state, &.{"h5"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .header_6 => append(state, &.{"h6"}, .{
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
        }, current_path),
        .forced_newline => appendBreak(state, options),
        .bold => append(state, &.{"strong"}, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }, current_path),
        .italic => append(state, &.{"em"}, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }, current_path),
        .bold_italic => append(state, &.{ "strong", "em" }, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }, current_path),
        .blockquote => append(state, &.{"blockquote"}, .{
            .text_children = false,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
            .children_default_options = true,
        }, current_path),
        .ordered_list, .unordered_list => appendList(state, .{
            .text_children = false,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
            .children_default_options = true,
        }, current_path),
        .code => append(state, &.{"code"}, .{
            .text_children = true,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = true,
            .ignore_paragraph_children_end = true,
        }, current_path),
        .code_block => appendCodeBlock(state, .{
            .text_children = true,
            .ignore_paragraph_start = options.ignore_paragraph_start,
            .ignore_paragraph_end = options.ignore_paragraph_end,
        }),
        .math => {
            if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
            try state.html.writeByte('$');
            try append(state, &.{}, .{
                .text_children = true,
                .ignore_paragraph_start = true,
                .ignore_paragraph_end = true,
                .ignore_paragraph_children_end = true,
            }, current_path);
            try state.html.writeByte('$');
        },
        .math_block => {
            if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
            try state.html.writeAll("$$\n");
            try append(state, &.{}, .{
                .text_children = true,
                .ignore_paragraph_start = true,
                .ignore_paragraph_end = true,
                .ignore_paragraph_children_end = true,
            }, current_path);
            try state.html.writeAll("$$\n");
        },
        .horizontal_rule => appendText(state, "<hr/>", options),
        .image => appendImage(state, options, current_path),
        .link => appendLink(state, options, current_path),
        .ampersand => appendText(state, "&amp;", options),
        .html_start => appendText(state, "&lt;", options),
        .html_end => appendText(state, "&gt;", options),
        .html => {
            if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
            try token.writeLexeme(state.html, true);
        },
        else => {
            try append(state, null, options, current_path);
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
    current_path: []const u8, // I know this is in the "wrong" spot but it looks best when calling the function
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
            .tokens = token.value.children.items,
            .is_in_paragraph = state.is_in_paragraph,
        };
        while (s.current < s.tokens.len) : (s.current += 1) {
            try appendToken(&s, current_path, if (options.children_default_options) .{} else options);
        }
        if (!options.ignore_paragraph_children_end and s.is_in_paragraph) try endParagraph(&s);
    } else {
        try token.writeLexeme(state.html, false);
    }

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
    if (token.has_following_space) try state.html.writeByte(' ');
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
    current_path: []const u8,
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
        .tokens = token.value.children.items,
        .is_in_paragraph = false,
    };

    while (list_state.current < list_state.tokens.len) : (list_state.current += 1) {
        try append(&list_state, &.{"li"}, .{
            .text_children = options.text_children,
            .ignore_paragraph_start = true,
            .ignore_paragraph_end = options.ignore_paragraph_end,
            .children_default_options = options.children_default_options,
        }, current_path);
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
    current_path: []const u8,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(token.token_type == .image);
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.items.len == 2);

    const alt_token = token.value.children.items[0];
    const url_token = token.value.children.items[1];
    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    const url_lexeme = url_token.value.lexeme;
    assert(url_lexeme.len > 0);
    assert(current_path.len > 0);

    const has_following_slash = current_path[current_path.len - 1] == '/';
    const has_beginning_slash = url_lexeme[0] == '/';
    const is_uri = blk: {
        for (url_lexeme) |c| {
            if (!isSchemeChar(c))
                break :blk c == ':';
        }
        break :blk false;
    };

    const url = if (is_uri) url_lexeme else blk: {
        var temp = std.ArrayList(u8).init(state.allocator);
        defer temp.deinit();

        try temp.appendSlice(image_url_prefix);
        try temp.appendSlice(current_path);
        if (!has_beginning_slash and !has_following_slash) try temp.append('/');
        try temp.appendSlice(url_lexeme[if (has_following_slash and has_beginning_slash) 1 else 0..]);

        break :blk try state.allocator.dupe(u8, temp.items);
    };
    defer if (!is_uri) state.allocator.free(url);

    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);
    try state.html.print("<img alt=\"{s}\" src=\"{s}\"/>", .{
        alt_token.value.lexeme,
        url,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}

fn isSchemeChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '-', '.' => true,
        else => false,
    };
}

fn appendLink(
    state: *CompileState,
    comptime options: CompileOptions,
    current_path: []const u8,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(token.token_type == .link);
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.items.len == 2);

    const alt_token = token.value.children.items[0];
    const url_token = token.value.children.items[1];
    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    const url_lexeme = url_token.value.lexeme;
    assert(url_lexeme.len > 0);
    assert(current_path.len > 0);

    const has_following_slash = current_path[current_path.len - 1] == '/';
    const has_beginning_slash = url_lexeme[0] == '/';
    const is_uri = blk: {
        for (url_lexeme) |c| {
            if (!isSchemeChar(c))
                break :blk c == ':';
        }
        break :blk false;
    };

    const url = if (is_uri) url_lexeme else blk: {
        var temp = std.ArrayList(u8).init(state.allocator);
        defer temp.deinit();

        try temp.appendSlice(link_url_prefix);
        try temp.appendSlice(current_path);
        if (!has_beginning_slash and !has_following_slash) try temp.append('/');
        try temp.appendSlice(url_lexeme[if (has_following_slash and has_beginning_slash) 1 else 0..]);

        break :blk try state.allocator.dupe(u8, temp.items);
    };
    defer if (!is_uri) state.allocator.free(url);

    if (!options.ignore_paragraph_start and !state.is_in_paragraph) try startParagraph(state);
    try state.html.print("<a href=\"{s}\">{s}</a>", .{
        url,
        alt_token.value.lexeme,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}

fn appendCodeBlock(
    state: *CompileState,
    comptime options: CompileOptions,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];

    assert(std.meta.activeTag(token.value) == .children);
    const children = token.value.children;

    if (children.items.len == 0) return;
    const code_lang: ?[]const u8 = if (children.items[0].token_type == .code_lang) blk: {
        const lang = children.items[0];
        assert(std.meta.activeTag(lang.value) == .lexeme);
        break :blk lang.value.lexeme;
    } else null;

    if (!options.ignore_paragraph_end and state.is_in_paragraph) try endParagraph(state);

    if (code_lang) |lang|
        try state.html.print("<pre><code lang=\"{s}\">", .{lang})
    else
        try state.html.writeAll("<pre><code>");

    const code_children = children.items[(if (code_lang) |_| 1 else 0)..];
    std.log.debug("Code Children: {d} {d}", .{ code_children.len, children.items.len });

    for (code_children) |t| {
        try t.writeLexeme(state.html, false);
        if (t.has_following_space) try state.html.writeByte(' ');
    }

    try state.html.writeAll("</code></pre>");
}
