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

const assert = std.debug.assert;

const should_compress = @import("builtin").mode != .Debug;

pub fn compile(allocator: std.mem.Allocator, tokens: tokenizer.TokenList, comptime ignore_paragraph: bool,) error{OutOfMemory}![]u8 {
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html.deinit();

    var state = CompileState{
        .allocator = html.allocator,
        .html = html.writer(),
        .tokens = tokens.tokens,
    };
    while (state.current < tokens.tokens.len) : (state.current += 1) {
        try appendToken(&state, ignore_paragraph);
    }

    return allocator.dupe(u8, html.items);
}

fn appendToken(state: *CompileState, comptime ignore_paragraph: bool,) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    try switch (state.tokens[state.current].token_type) {
        .metadata => return,
        .header_1 => appendHtml(state, &.{"h1"}, ignore_paragraph),
        .header_2 => appendHtml(state, &.{"h2"}, ignore_paragraph),
        .header_3 => appendHtml(state, &.{"h3"}, ignore_paragraph),
        .header_4 => appendHtml(state, &.{"h4"}, ignore_paragraph),
        .header_5 => appendHtml(state, &.{"h5"}, ignore_paragraph),
        .header_6 => appendHtml(state, &.{"h6"}, ignore_paragraph),
        .forced_newline => appendNewline(state),
        .bold => appendHtml(state, &.{"strong"}, ignore_paragraph),
        .italic => appendHtml(state, &.{"em"}, ignore_paragraph),
        .bold_italic => appendHtml(state, &.{ "strong", "em" }, ignore_paragraph),
        .blockquote => appendRecusive(state, &.{"blockquote"}, ignore_paragraph, ignore_paragraph),
        .ordered_list, .unordered_list => appendList(state, ignore_paragraph),
        .code => appendRecusive(state, &.{"code"}, ignore_paragraph, true),
        .code_block => appendCodeBlock(state, ignore_paragraph),
        .math => {
            try state.html.writeByte('$');
            try appendRecusive(state, &.{}, ignore_paragraph, true);
            try state.html.writeByte('$');
        },
        .math_block => {
            try state.html.writeAll("$$\n");
            try appendRecusive(state, &.{}, ignore_paragraph, true);
            try state.html.writeAll("$$\n");
        },
        .horizontal_rule => appendText(state, "<hr/>", ignore_paragraph),
        .image => appendImage(state, ignore_paragraph),
        .link => appendLink(state, ignore_paragraph),
        .ampersand => appendText(state, "&amp;", false),
        .html_start => appendText(state, "&lt;", false),
        .html_end => appendText(state, "&gt;", false),
        else => {
            try appendHtml(state, null);
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

fn appendText(state: *CompileState, text: []const u8, comptime ignore_paragraph: bool) error{OutOfMemory}!void {
        if (!ignore_paragraph and !state.is_in_paragraph)
            try startParagraph(state);
    try state.html.writeAll(text);
    if (state.tokens[state.current].has_following_space) try state.html.writeByte(' ');
}

fn appendHtml(
    state: *CompileState,
    comptime tags: ?[]const []const u8,
    comptime ignore_paragraph: bool,
) error{OutOfMemory}!void {
    if (tags) |t| {
        if (!ignore_paragraph and state.is_in_paragraph)
            try endParagraph(state);
        inline for (t) |tag| try state.html.writeAll("<" ++ tag ++ ">");
    } else {
        if (!ignore_paragraph and !state.is_in_paragraph)
            try startParagraph(state);
    }
    try appendLexeme(state);
    if (tags) |t| inline for (t) |tag| try state.html.writeAll("</" ++ tag ++ ">");
    if (state.tokens[state.current].has_following_space) try state.html.writeByte(' ');
}

fn appendNewline(state: *CompileState) error{OutOfMemory}!void {
    try state.html.writeAll(if (should_compress) "<br/>" else "<br/>\n");
}

fn appendRecusive(
    state: *CompileState,
    comptime tags: ?[]const []const u8,
    comptime ignore_paragraph: bool,
    comptime ignore_paragraph_children: bool,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);

    if (state.is_in_paragraph) try endParagraph(state);
    if (tags) |t| inline for (t) |tag| try state.html.writeAll("<" ++ tag ++ ">");

    const inner_html = try compile(state.allocator, token.value.children);
    defer state.allocator.free(inner_html);

    try state.html.writeAll(inner_html);

    if (tags) |t| inline for (t) |tag| try state.html.writeAll("</" ++ tag ++ ">");
    if (state.tokens[state.current].has_following_space) try state.html.writeByte(' ');
}

fn appendList(state: *CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(token.token_type == .ordered_list or token.token_type == .unordered_list);
    assert(std.meta.activeTag(token.value) == .children);

    const is_ordered = token.token_type == .ordered_list;

    if (state.is_in_paragraph) try endParagraph(state);
    try state.html.writeAll(if (is_ordered) @as([]const u8, "<ol>") else "<ul>");
    if (!should_compress) try state.html.writeByte('\n');

    var list_state = CompileState{
        .allocator = state.allocator,
        .html = state.html,
        .tokens = token.value.children.tokens,
    };

    while (list_state.current < list_state.tokens.len) : (list_state.current += 1)
        try appendRecusive(&list_state, &.{"li"});

    try state.html.writeAll(if (is_ordered) @as([]const u8, "</ol>") else "</ul>");
    if (!should_compress) try state.html.writeByte('\n');
}

fn appendCodeBlock(state: *CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);

    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.tokens.len > 0);

    const code_lang: ?tokenizer.Token = if (token.value.children.tokens[0].token_type == .code_lang)
        token.value.children.tokens[0]
    else
        null;

    if (state.is_in_paragraph) try endParagraph(state);
    if (code_lang) |lang| {
        assert(std.meta.activeTag(lang.value) == .lexeme);
        assert(lang.token_type == .code_lang);

        if (!should_compress) try state.html.writeByte('\n');
        try state.html.print(
            "<pre class='language-{s}'><code class='language-{s}'>",
            .{ lang.value.lexeme, lang.value.lexeme },
        );
        if (!should_compress) try state.html.writeByte('\n');
    } else {
        if (!should_compress) try state.html.writeByte('\n');
        try state.html.writeAll("<pre><code>");
        if (!should_compress) try state.html.writeByte('\n');
    }

    const offset: usize = @intFromBool(code_lang != null);

    for (token.value.children.tokens[offset..], 0..) |_, i| {
        var code_state = CompileState{
            .allocator = state.allocator,
            .html = state.html,
            .tokens = token.value.children.tokens,
            .current = offset + i,
        };
        try appendHtml(&code_state, null);
    }

    if (!should_compress) try state.html.writeByte('\n');
    try state.html.writeAll("</code></pre>");
    if (!should_compress) try state.html.writeByte('\n');
}

fn appendImage(state: *CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.tokens.len == 2);

    const alt_token = token.value.children.tokens[0];
    const url_token = token.value.children.tokens[1];

    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    if (state.is_in_paragraph) try endParagraph(state);
    try state.html.print("<img alt=\"{s}\" src=\"{s}\"/>", .{
        alt_token.value.lexeme,
        url_token.value.lexeme,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}

fn appendLink(state: *CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);
    assert(token.value.children.tokens.len == 2);

    const alt_token = token.value.children.tokens[0];
    const url_token = token.value.children.tokens[1];

    assert(std.meta.activeTag(alt_token.value) == .lexeme);
    assert(std.meta.activeTag(url_token.value) == .lexeme);

    if (state.is_in_paragraph) try endParagraph(state);
    try state.html.print("<a href=\"{s}\">{s}</a>", .{
        url_token.value.lexeme,
        alt_token.value.lexeme,
    });
    if (token.has_following_space) try state.html.writeByte(' ');
}

fn appendLexeme(state: *CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    try state.tokens[state.current].writeLexeme(state.html);
}
