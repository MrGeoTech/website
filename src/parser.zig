const std = @import("std");

const ParserState = struct {
    is_heading: bool = false,
    is_bold: bool = false,
    is_italic: bool = false,
    /// The previous character
    prev_char: u8 = '\n',
    /// How many of the previous character are in a line
    prev_count: u8 = 0,
};

pub fn parseMarkdown(arena: *std.heap.ArenaAllocator, markdown: []const u8) ![]const u8 {
    const allocator = arena.allocator();

    var html_slices = std.ArrayList([]const u8).init(allocator);
    defer html_slices.deinit();

    var last_index: usize = 0;
    var state = ParserState{};
    for (markdown, 0..) |char, i| {
        // Bold/Italics
        if (state.prev_char == '*') {
            if (char == '*') {
                // Handle 3+ asterisks
                if (state.prev_count == 2) {
                    state.is_bold = !state.is_bold;
                    if (state.is_bold) {
                        try html_slices.append(markdown[last_index .. i - 2]);
                        last_index = i;
                        try html_slices.append("<strong>");
                    } else {
                        try html_slices.append(markdown[last_index .. i - 2]);
                        last_index = i;
                        try html_slices.append("</strong>");
                    }
                    state.prev_count = 0;
                }
            } else {
                // Handle either bold or italic
                if (state.prev_count == 2) {
                    state.is_bold = !state.is_bold;
                    if (state.is_bold) {
                        try html_slices.append(markdown[last_index .. i - 2]);
                        last_index = i;
                        try html_slices.append("<strong>");
                    } else {
                        try html_slices.append(markdown[last_index .. i - 2]);
                        last_index = i;
                        try html_slices.append("</strong>");
                    }
                } else {
                    state.is_italic = !state.is_italic;
                    if (state.is_italic) {
                        try html_slices.append(markdown[last_index .. i - 1]);
                        last_index = i;
                        try html_slices.append("<em>");
                    } else {
                        try html_slices.append(markdown[last_index .. i - 1]);
                        last_index = i;
                        try html_slices.append("</em>");
                    }
                }
            }
            continue;
        }

        // Handle Heading
        if (state.prev_char == '#' and char != '#') {}

        // Update previous values
        if (state.prev_char == char)
            state.prev_count += 1
        else
            state.prev_count = 1;
        state.prev_char = char;
    }
    try html_slices.append(markdown[last_index..markdown.len]);

    var length: usize = 0;
    for (html_slices.items) |item| {
        length += item.len;
    }

    const html = try allocator.alloc(u8, length);

    var offset: usize = 0;
    for (html_slices.items) |item| {
        @memcpy(html[offset .. offset + item.len], item);
        offset += item.len;
    }

    return html;
}
