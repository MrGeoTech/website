const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const CompileState = struct {
    html: *std.ArrayList(u8),
    tokens: []const tokenizer.Token,
    current: usize,
};

const assert = std.debug.assert;

const should_compress = @import("builtin").mode != .Debug;

pub fn compile(allocator: std.mem.Allocator, tokens: tokenizer.TokenList) error{OutOfMemory}![]u8 {
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html.deinit();

    var state = CompileState{
        .html = &html,
        .tokens = tokens.tokens,
        .current = 0,
    };
    while (state.current < tokens.tokens.len) : (state.current += 1) {
        try appendToken(state);
    }

    return allocator.dupe(u8, html.items);
}

fn appendToken(state: CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    try switch (state.tokens[state.current].token_type) {
        .metadata => return,
        .header_1 => appendHtml(state, &.{"h1"}, true),
        .header_2 => appendHtml(state, &.{"h2"}, true),
        .header_3 => appendHtml(state, &.{"h3"}, true),
        .header_4 => appendHtml(state, &.{"h4"}, true),
        .header_5 => appendHtml(state, &.{"h5"}, true),
        .header_6 => appendHtml(state, &.{"h6"}, true),
        .forced_newline => appendNewline(state),
        .bold => appendHtml(state, &.{"strong"}, false),
        .italic => appendHtml(state, &.{"em"}, false),
        .bold_italic => appendHtml(state, &.{ "strong", "em" }, false),
        .blockquote => appendRecusive(state, &.{"blockquote"}),
        .ordered_list, .unordered_list => appendList(state),
        else => appendHtml(state, null, false),
    };
}

fn appendHtml(
    state: CompileState,
    comptime tags: ?[]const []const u8,
    comptime follow_with_newline: bool,
) error{OutOfMemory}!void {
    if (tags) |t| inline for (t) |tag| try state.html.appendSlice("<" ++ tag ++ ">");
    var add_space = false;
    if (state.current + 1 < state.tokens.len) {
        const lexeme = state.tokens[state.current].getLexeme();
        add_space = lexeme.ptr[lexeme.len] == ' ';
    }

    const lexeme = state.tokens[state.current].getLexeme();
    try appendLexeme(state, state.current < state.tokens.len and
        (lexeme.ptr[lexeme.len] == ' ' or lexeme.ptr[lexeme.len] == '\n'));
    if (tags) |t| inline for (t) |tag| try state.html.appendSlice("</" ++ tag ++ ">");
    if (follow_with_newline and !should_compress) try appendNewline(state);
}

fn appendNewline(state: CompileState) error{OutOfMemory}!void {
    try state.html.appendSlice(if (should_compress) "<br>" else "\n<br>\n");
}

fn appendRecusive(
    state: CompileState,
    comptime tags: ?[]const []const u8,
) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(std.meta.activeTag(token.value) == .children);

    if (tags) |t| inline for (t) |tag| try state.html.appendSlice("<" ++ tag ++ ">");

    const inner_html = try compile(state.html.allocator, token.value.children);
    defer state.html.allocator.free(inner_html);

    try state.html.appendSlice(inner_html);

    if (tags) |t| inline for (t) |tag| try state.html.appendSlice("</" ++ tag ++ ">");
    if (!should_compress) try appendNewline(state);
}

fn appendList(state: CompileState) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    const token = state.tokens[state.current];
    assert(token.token_type == .ordered_list or token.token_type == .unordered_list);
    assert(std.meta.activeTag(token.value) == .children);

    const is_ordered = token.token_type == .ordered_list;

    try state.html.appendSlice(if (is_ordered) @as([]const u8, "<ol>") else "<ul>");
    if (!should_compress) try state.html.append('\n');

    var list_state = CompileState{
        .html = state.html,
        .tokens = token.value.children.tokens,
        .current = 0,
    };

    while (list_state.current < list_state.tokens.len) : (list_state.current += 1)
        try appendRecusive(list_state, &.{"li"});

    try state.html.appendSlice(if (is_ordered) @as([]const u8, "</ol>") else "</ul>");
    if (!should_compress) try state.html.append('\n');
}

fn appendLexeme(state: CompileState, with_trailing_space: bool) error{OutOfMemory}!void {
    assert(state.current < state.tokens.len);
    try state.html.appendSlice(state.tokens[state.current].getLexeme());
    if (with_trailing_space)
        try state.html.append(' ');
}
