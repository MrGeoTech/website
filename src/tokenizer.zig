const std = @import("std");
const lexer = @import("lexer.zig");

const Allocator = std.mem.Allocator;
const LexemeList = std.ArrayList(lexer.Lexeme);
pub const TokenList = struct {
    tokens: []Token = &.{},

    pub fn of(lexemes: LexemeList) !TokenList {
        const tokens = TokenList{
            .tokens = try lexemes.allocator.alloc(Token, lexemes.items.len),
        };

        for (lexemes.items, 0..) |lexeme, i| {
            tokens.tokens[i] = Token.of(lexeme);
        }

        return tokens;
    }

    pub fn insert(self: *TokenList, allocator: Allocator, token: Token) error{OutOfMemory}!void {
        self.tokens = try allocator.realloc(self.tokens, self.tokens.len + 1);
        std.mem.copyBackwards(Token, self.tokens[1..], self.tokens[0 .. self.tokens.len - 1]);
        self.tokens[0] = token;
    }

    pub fn append(self: *TokenList, allocator: Allocator, token: Token) error{OutOfMemory}!void {
        return self.appendAll(allocator, &.{token});
    }

    pub fn appendAll(self: *TokenList, allocator: Allocator, tokens: []const Token) error{OutOfMemory}!void {
        const old_len = self.tokens.len;
        self.tokens = try allocator.realloc(self.tokens, self.tokens.len + tokens.len);
        @memcpy(self.tokens[old_len..], tokens);
    }

    pub fn removeLast(self: *TokenList, allocator: Allocator) error{OutOfMemory}!void {
        self.tokens = try allocator.realloc(self.tokens, self.tokens.len - 1);
    }

    pub fn deinit(self: TokenList, allocator: Allocator) void {
        for (self.tokens) |token| {
            switch (token.value) {
                .children => |children| children.deinit(allocator),
                else => {},
            }
        }

        allocator.free(self.tokens);
    }
};
const TokenizeError = error{OutOfMemory};

const eql = std.mem.eql;
const assert = std.debug.assert;

pub const TokenType = enum {
    escape,
    indent,
    text,
    newline,
    forced_newline,
    metadata,
    html,
    html_start,
    html_end,
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
    blockquote,
    bold,
    italic,
    bold_italic,
    ordered_list,
    unordered_list,
    list_item,
    code,
    code_escaped,
    code_block,
    code_lang,
    math,
    math_block,
    horizontal_rule,
    link,
    image,
    image_start,
    alt_start,
    alt_end,
    url_start,
    url_end,
    ampersand,

    pub fn isEscapeable(self: TokenType) bool {
        return self != .text and self != .indent and self != .newline and self != .forced_newline;
    }

    pub fn isNewLine(self: TokenType) bool {
        return self == .newline or self == .forced_newline;
    }

    pub fn isHeader(self: TokenType) bool {
        return self == .header_1 or self == .header_2 or self == .header_3 or
            self == .header_4 or self == .header_5 or self == .header_6;
    }

    pub fn isSpecialCharacter(self: TokenType) bool {
        return self == .ampersand;
    }
};

pub const Token = struct {
    token_type: TokenType,
    value: union(enum) {
        lexeme: []const u8,
        children: TokenList,
    },
    line: usize,
    has_following_space: bool,

    pub fn of(lexeme: lexer.Lexeme) Token {
        return .{
            .token_type = lexeme.lexeme_type,
            .value = .{ .lexeme = lexeme.value },
            .line = lexeme.line,
            .has_following_space = lexeme.has_following_space,
        };
    }

    test "of" {
        const lexeme = lexer.Lexeme{
            .lexeme_type = .text,
            .value = "Hello",
            .line = 1,
            .has_following_space = false,
        };
        const token = Token.of(lexeme);

        try std.testing.expectEqual(.text, token.token_type);
        try std.testing.expectEqual(.lexeme, std.meta.activeTag(token.value));
        try std.testing.expectEqualStrings("Hello", token.value.lexeme);
        try std.testing.expectEqual(1, token.line);
        try std.testing.expectEqual(false, token.has_following_space);
    }

    pub fn writeLexeme(self: Token, writer: anytype) @TypeOf(writer).Error!void {
        switch (self.value) {
            .lexeme => |lexeme| {
                _ = try writer.write(lexeme);
                if (self.has_following_space) try writer.writeByte(' ');
            },
            .children => |children| {
                for (children.tokens) |token| {
                    try token.writeLexeme(writer);
                }
            },
        }
    }

    pub fn getLexeme(self: Token, allocator: Allocator) error{OutOfMemory}![]const u8 {
        var temp_lexeme = try std.ArrayList(u8).initCapacity(allocator, 1024);
        defer temp_lexeme.deinit();

        try self.writeLexeme(temp_lexeme.writer());

        return allocator.dupe(u8, temp_lexeme.items);
    }

    test "getLexeme" {
        const markdown = "Hello World";

        const lexeme_token1 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[0..5] },
            .line = 1,
            .has_following_space = true,
        };
        const lexeme_token2 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[6..] },
            .line = 1,
            .has_following_space = false,
        };
        var children_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{
                .tokens = try std.testing.allocator.dupe(Token, &[_]Token{ lexeme_token1, lexeme_token2 }),
            } },
            .line = 1,
            .has_following_space = false,
        };
        defer children_token.value.children.deinit(std.testing.allocator);

        const lexeme1 = try lexeme_token1.getLexeme(std.testing.allocator);
        defer std.testing.allocator.free(lexeme1);
        try std.testing.expectEqualStrings("Hello ", lexeme1);
        const lexeme2 = try lexeme_token2.getLexeme(std.testing.allocator);
        defer std.testing.allocator.free(lexeme2);
        try std.testing.expectEqualStrings("World", lexeme2);
        const lexeme3 = try children_token.getLexeme(std.testing.allocator);
        defer std.testing.allocator.free(lexeme3);
        try std.testing.expectEqualStrings("Hello World", lexeme3);

        // No need for a deinit because nothing is every actually allocated.
        const special_case_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{} },
            .line = 1,
            .has_following_space = false,
        };

        try std.testing.expectEqualStrings("", try special_case_token.getLexeme(std.testing.allocator));
    }

    pub fn write(self: Token, writer: anytype) !void {
        return self.writeIndented(writer, 0);
    }

    fn writeIndented(self: Token, writer: anytype, indents: usize) !void {
        for (0..indents) |_| try writer.writeByte('\t');
        try writer.writeAll("Token{token_type:");
        if (self.token_type.isEscapeable())
            try writer.writeAll("\x1B[0;32m");
        try writer.writeAll(@tagName(self.token_type));
        if (self.token_type.isEscapeable())
            try writer.writeAll("\x1B[0m");
        try writer.writeAll(",value:");
        switch (self.value) {
            .lexeme => |lexeme| {
                var iterator = std.mem.splitScalar(u8, lexeme, '\n');
                while (iterator.next()) |line| {
                    try writer.writeAll(line);
                    if (iterator.peek() != null)
                        try writer.writeAll("\\n");
                }
            },
            .children => |children| blk: {
                if (children.tokens.len == 0) break :blk;
                try writer.writeByte('\n');
                for (children.tokens) |child| {
                    try child.writeIndented(writer, indents + 1);
                    try writer.writeByte('\n');
                }
                for (0..indents) |_| try writer.writeByte('\t');
            },
        }
        try writer.writeAll(",line:");
        try std.fmt.formatInt(self.line, 10, .lower, .{}, writer);
        try writer.print(",has_following_space:{}}}", .{self.has_following_space});
    }

    test "write Lexeme" {
        const token = Token{
            .token_type = .text,
            .value = .{ .lexeme = "Hello World" },
            .line = 1,
            .has_following_space = false,
        };

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try token.write(output.writer());

        try std.testing.expectEqualStrings("Token{token_type:text,value:Hello World,line:1,has_following_space:false}", output.items);
    }

    test "write Children" {
        const markdown = "Hello World";
        const lexeme_token1 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[0..5] },
            .line = 1,
            .has_following_space = true,
        };
        const lexeme_token2 = Token{
            .token_type = .text,
            .value = .{ .lexeme = markdown[6..] },
            .line = 1,
            .has_following_space = false,
        };
        var children_token = Token{
            .token_type = .text,
            .value = .{ .children = TokenList{
                .tokens = try std.testing.allocator.dupe(Token, &[_]Token{ lexeme_token1, lexeme_token2 }),
            } },
            .line = 1,
            .has_following_space = false,
        };
        defer children_token.value.children.deinit(std.testing.allocator);

        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        try children_token.write(output.writer());

        try std.testing.expectEqualStrings("Token{token_type:text,value:\n" ++
            "\tToken{token_type:text,value:Hello,line:1,has_following_space:true}\n" ++
            "\tToken{token_type:text,value:World,line:1,has_following_space:false}\n" ++
            ",line:1,has_following_space:false}", output.items);
    }
};

const TokenizerState = struct {
    allocator: Allocator,
    lexemes: []lexer.Lexeme,
    tokens: TokenList,
    current: usize = 0,

    pub fn addNextToken(self: *TokenizerState) TokenizeError!void {
        assert(self.current < self.lexemes.len);
        const lexeme = self.lexemes[self.current];

        switch (lexeme.lexeme_type) {
            .header_1, .header_2, .header_3, .header_4, .header_5, .header_6 => try self.addHeader(),
            .bold, .italic, .bold_italic => try self.addSingleLine(),
            .blockquote => try self.addBlockquote(),
            .ordered_list, .unordered_list => try self.addList(),
            .code, .code_escaped => try self.addSingleLineCombine(.code),
            .code_block, .math_block => try self.addBlock(),
            .indent => try self.addIndentCodeBlock(),
            .math => try self.addSingleLineCombine(.math),
            .alt_start => try self.addLink(),
            .image_start => try self.addImage(),
            .html_start => try self.addHtml(),
            .horizontal_rule => {
                if (lexeme.line == 1)
                    try self.addMetadata()
                else
                    try self.addCurrent();
            },
            .escape => {
                if (self.current + 1 < self.lexemes.len and
                    self.lexemes[self.current + 1].lexeme_type.isEscapeable())
                {
                    self.current += 1;
                    try self.addCurrentAs(.text);
                } else {
                    try self.addCurrentAs(.text);
                }
            },
            .newline => {
                if (self.current + 1 < self.lexemes.len and self.lexemes[self.current + 1].lexeme_type == .newline) {
                    try self.addCombineChildren(.forced_newline, 2);
                } else {
                    self.current += 1;
                }
            },
            .forced_newline => try self.addCurrent(),
            else => try self.addCurrentAs(.text),
        }
    }

    fn addCombineChildren(
        self: *TokenizerState,
        token_type: TokenType,
        count: usize,
    ) error{OutOfMemory}!void {
        if (self.current + count > self.lexemes.len) return;

        var combined_strings = combineStrings(
            self.lexemes[self.current].value,
            self.lexemes[self.current + count - 1].value,
        );

        if (self.lexemes[self.current].has_following_space) {
            const combined_strings_int: usize = @intFromPtr(combined_strings.ptr);
            const new_ptr: [*]const u8 = @ptrFromInt(combined_strings_int - 1);
            combined_strings = new_ptr[0 .. combined_strings.len + 1];
        }

        try self.tokens.append(self.allocator, .{
            .token_type = token_type,
            .value = .{ .lexeme = combined_strings },
            .line = self.lexemes[self.current].line,
            .has_following_space = self.lexemes[self.current + count - 1].has_following_space,
        });

        self.current += count;
    }

    fn addWithChildren(
        self: *TokenizerState,
        token_type: TokenType,
        count: usize,
        comptime is_end: bool,
        comptime tokenize_children: bool,
    ) error{OutOfMemory}!void {
        if (self.current + count > self.lexemes.len) return;

        const lexemes = LexemeList{
            .allocator = self.allocator,
            .items = self.lexemes[self.current..][0..count],
            .capacity = count,
        };

        var children = if (tokenize_children)
            try tokenize(lexemes)
        else
            TokenList.of(lexemes);
        errdefer children.deinit(self.allocator);

        if (self.lexemes[self.current].has_following_space)
            try children.insert(self.allocator, .{
                .token_type = .text,
                .value = .{ .lexeme = "" },
                .line = self.lexemes[self.current].line,
                .has_following_space = true,
            });

        try self.tokens.append(self.allocator, .{
            .token_type = token_type,
            .value = .{ .children = children },
            .line = self.lexemes[self.current].line,
            .has_following_space = self.lexemes[self.current + count - @intFromBool(!is_end)].has_following_space,
        });

        self.current += count;
    }

    fn addCurrent(self: *TokenizerState) error{OutOfMemory}!void {
        try self.tokens.append(self.allocator, Token.of(self.lexemes[self.current]));
        self.current += 1;
    }

    fn addCurrentAs(self: *TokenizerState, comptime token_type: TokenType) error{OutOfMemory}!void {
        try self.tokens.append(self.allocator, Token.of(self.lexemes[self.current]));
        self.tokens.tokens[self.tokens.tokens.len - 1].token_type = token_type;
        self.current += 1;
    }

    fn addSingleLine(self: *TokenizerState) error{OutOfMemory}!void {
        const lexeme = self.lexemes[self.current];

        var count: usize = 1;
        if (self.current + count >= self.lexemes.len or
            self.lexemes[self.current + count].lexeme_type.isNewLine())
            return self.addCurrentAs(.text);

        while (self.lexemes[self.current + count].lexeme_type != lexeme.lexeme_type) {
            count += 1;
            // If we reach the end and no match has been found, treat it like text
            if (self.current + count >= self.lexemes.len or
                self.lexemes[self.current + count].lexeme_type.isNewLine())
                return self.addCurrentAs(.text);
        }

        self.current += 1;
        try self.addWithChildren(lexeme.lexeme_type, count - 1, true, true);
        self.current += 1;
    }

    fn addSingleLineCombine(self: *TokenizerState, token_type: TokenType) error{OutOfMemory}!void {
        const lexeme = self.lexemes[self.current];

        var count: usize = 1;
        if (self.current + count >= self.lexemes.len or
            self.lexemes[self.current + count].lexeme_type.isNewLine())
            return self.addCurrentAs(.text);

        while (self.lexemes[self.current + count].lexeme_type != lexeme.lexeme_type) {
            count += 1;
            // If we reach the end and no match has been found, treat it like text
            if (self.current + count >= self.lexemes.len or
                self.lexemes[self.current + count].lexeme_type.isNewLine())
                return self.addCurrentAs(.text);
        }

        self.current += 1;
        try self.addCombineChildren(token_type, count - 1);
        self.current += 1;
    }

    fn addMetadata(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current < self.lexemes.len);
        const start_lexeme = self.lexemes[self.current];
        assert(start_lexeme.lexeme_type == .horizontal_rule);
        assert(start_lexeme.line == 1);

        if (self.current + 1 >= self.lexemes.len) return self.addCurrent();
        self.current += 1;

        var count: usize = 0;
        while (self.lexemes[self.current + count].lexeme_type != .horizontal_rule) {
            count += 1;
            if (self.current + count >= self.lexemes.len) return self.addCurrent();
        }

        self.current += if (count > 0) 1 else 0;
        try self.addCombineChildren(.metadata, count - 2);
        self.current += 2;
    }

    fn addHeader(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current < self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type.isHeader());

        const header_type = self.lexemes[self.current].lexeme_type;
        self.current += 1;

        var count: usize = 0;
        while (self.current + count < self.lexemes.len and
            !self.lexemes[self.current + count].lexeme_type.isNewLine())
            count += 1;

        return self.addCombineChildren(header_type, count);
    }

    fn addBlockquote(self: *TokenizerState) TokenizeError!void {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .blockquote);

        const line = self.lexemes[self.current].line;

        var lexemes = LexemeList.init(self.allocator);
        defer lexemes.deinit();

        var is_on_newline = true;
        while (self.current < self.lexemes.len) {
            const lexeme = self.lexemes[self.current];

            if (is_on_newline) {
                if (lexeme.lexeme_type == .blockquote) {
                    is_on_newline = false;
                    self.current += 1;
                } else if (!lexeme.lexeme_type.isEscapeable()) {
                    self.current += 1;
                } else break;
            } else {
                try lexemes.append(lexeme);
                is_on_newline = lexeme.lexeme_type.isNewLine();
                self.current += 1;
            }
        }

        if (self.current != self.lexemes.len) {
            // Go to start of next line
            while (!self.lexemes[self.current].lexeme_type.isNewLine()) self.current -= 1;
            self.current += 1;
        }
        // Remove last newline from lexemes
        _ = lexemes.orderedRemove(lexemes.items.len - 1);

        try self.tokens.append(self.allocator, .{
            .token_type = .blockquote,
            .value = .{ .children = try tokenize(lexemes) },
            .line = line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });
    }

    fn addList(self: *TokenizerState) TokenizeError!void {
        assert(self.current <= self.lexemes.len);
        const start_lexeme = self.lexemes[self.current];
        assert(start_lexeme.lexeme_type == .ordered_list or
            start_lexeme.lexeme_type == .unordered_list);

        var children = TokenList{ .tokens = &.{} };
        errdefer children.deinit(self.allocator);

        while (self.current < self.lexemes.len and
            self.lexemes[self.current].lexeme_type == start_lexeme.lexeme_type)
        {
            const line = self.lexemes[self.current].line;
            self.current += 1;

            var lexemes = LexemeList.init(self.allocator);
            defer lexemes.deinit();

            var is_on_newline = false;
            while (self.current < self.lexemes.len) {
                const lexeme = self.lexemes[self.current];

                if (is_on_newline and (lexeme.lexeme_type == start_lexeme.lexeme_type or
                    (self.current + 1 < self.lexemes.len and
                    lexeme.lexeme_type == .newline and
                    self.lexemes[self.current + 1].lexeme_type != .indent))) break;

                if (!(is_on_newline and lexeme.lexeme_type == .indent)) try lexemes.append(lexeme);
                is_on_newline = lexeme.lexeme_type.isNewLine();
                self.current += 1;
            }

            const tokens = try tokenize(lexemes);
            errdefer tokens.deinit(lexemes.allocator);

            try children.append(self.allocator, .{
                .token_type = .list_item,
                .value = .{ .children = tokens },
                .line = line,
                .has_following_space = self.lexemes[self.current - 1].has_following_space,
            });
        }

        try self.tokens.append(self.allocator, .{
            .token_type = start_lexeme.lexeme_type,
            .value = .{ .children = children },
            .line = start_lexeme.line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });
    }
    fn addBlock(self: *TokenizerState) TokenizeError!void {
        assert(self.current <= self.lexemes.len);
        const start_lexeme = self.lexemes[self.current];
        assert(start_lexeme.lexeme_type == .code_block or
            start_lexeme.lexeme_type == .math_block);

        var children = TokenList{ .tokens = &.{} };
        errdefer children.deinit(self.allocator);

        self.current += 1;

        if (self.current < self.lexemes.len and
            self.lexemes[self.current].lexeme_type == .code_lang)
        {
            try children.append(self.allocator, Token.of(self.lexemes[self.current]));
            self.current += 1;
        }

        // Skip first newline
        self.current += 1;
        while (self.current < self.lexemes.len and
            self.lexemes[self.current].lexeme_type != start_lexeme.lexeme_type)
        {
            const lexeme = self.lexemes[self.current];
            try children.append(self.allocator, .{
                .token_type = if (lexeme.lexeme_type.isSpecialCharacter())
                    lexeme.lexeme_type
                else
                    .text,
                .value = .{ .lexeme = lexeme.value },
                .line = lexeme.line,
                .has_following_space = lexeme.has_following_space,
            });

            self.current += 1;
        }

        try children.removeLast(self.allocator);

        try self.tokens.append(self.allocator, .{
            .token_type = start_lexeme.lexeme_type,
            .value = .{ .children = children },
            .line = start_lexeme.line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });

        self.current += 1;
    }

    fn addIndentCodeBlock(self: *TokenizerState) !void {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .indent);
        const line = self.lexemes[self.current].line;

        var children = TokenList{ .tokens = &.{} };
        errdefer children.deinit(self.allocator);

        self.current += 1;

        var is_on_newline = false;
        while (self.current < self.lexemes.len) {
            const lexeme = self.lexemes[self.current];

            if (lexeme.lexeme_type == .newline and
                self.current + 1 < self.lexemes.len and
                self.lexemes[self.current + 1].lexeme_type != .indent) break;

            if (!(self.lexemes[self.current - 1].lexeme_type == .newline and lexeme.lexeme_type == .indent)) try children.append(self.allocator, .{
                .token_type = if (lexeme.lexeme_type.isSpecialCharacter())
                    lexeme.lexeme_type
                else
                    .text,
                .value = .{ .lexeme = lexeme.value },
                .line = lexeme.line,
                .has_following_space = lexeme.has_following_space,
            });
            is_on_newline = lexeme.lexeme_type.isNewLine();
            self.current += 1;
        }

        try self.tokens.append(self.allocator, .{
            .token_type = .code_block,
            .value = .{ .children = children },
            .line = line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });
    }

    fn addLink(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .alt_start);

        const line = self.lexemes[self.current].line;
        const children = self.getLinkChildren() catch |err| switch (err) {
            error.InvalidLink => return self.addCurrentAs(.text),
            else => return error.OutOfMemory,
        };

        try self.tokens.append(self.allocator, .{
            .token_type = .link,
            .value = .{ .children = children },
            .line = line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });
    }

    fn addImage(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .image_start);

        const line = self.lexemes[self.current].line;
        if (self.current + 1 >= self.lexemes.len) return self.addCurrentAs(.text);
        self.current += 1;

        const children = self.getLinkChildren() catch |err| switch (err) {
            error.InvalidLink => {
                self.current -= 1;
                return self.addCurrentAs(.text);
            },
            else => return error.OutOfMemory,
        };

        try self.tokens.append(self.allocator, .{
            .token_type = .image,
            .value = .{ .children = children },
            .line = line,
            .has_following_space = self.lexemes[self.current - 1].has_following_space,
        });
    }

    fn getLinkChildren(self: *TokenizerState) error{ InvalidLink, OutOfMemory }!TokenList {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .alt_start);
        const line = self.lexemes[self.current].line;

        var alt_len: usize = 0;
        while (self.current + 1 + alt_len < self.lexemes.len and
            self.lexemes[self.current + 1 + alt_len].lexeme_type != .alt_end)
        {
            if (self.lexemes[self.current + 1 + alt_len].lexeme_type.isNewLine())
                return error.InvalidLink;

            alt_len += 1;
        }

        if (self.lexemes[self.current + 1 + alt_len].lexeme_type != .alt_end or
            (self.current + alt_len + 2 < self.lexemes.len and
            self.lexemes[self.current + alt_len + 2].lexeme_type != .url_start))
            return error.InvalidLink;

        var url_len: usize = 0;
        while (self.current + alt_len + 3 + url_len < self.lexemes.len and
            self.lexemes[self.current + alt_len + 3 + url_len].lexeme_type != .url_end)
        {
            const lexeme = self.lexemes[self.current + alt_len + 3 + url_len];
            if (lexeme.lexeme_type.isNewLine() or lexeme.has_following_space)
                return error.InvalidLink;

            url_len += 1;
        }

        const end_lexeme = self.lexemes[self.current + alt_len + 3 + url_len];
        if (url_len == 0 or end_lexeme.lexeme_type != .url_end)
            return error.InvalidLink;

        var children = TokenList{ .tokens = &.{} };
        errdefer children.deinit(self.allocator);

        try children.append(self.allocator, .{
            .token_type = .text,
            .value = .{ .lexeme = combineStrings(
                self.lexemes[self.current + 1].value,
                self.lexemes[self.current + 1 + alt_len - 1].value,
            ) },
            .line = line,
            .has_following_space = false,
        });
        try children.append(self.allocator, .{
            .token_type = .text,
            .value = .{ .lexeme = combineStrings(
                self.lexemes[self.current + 1 + alt_len + 2].value,
                self.lexemes[self.current + 1 + alt_len + 2 + url_len - 1].value,
            ) },
            .line = line,
            .has_following_space = false,
        });

        self.current += 1 + alt_len + 2 + url_len + 1;

        return children;
    }

    fn addHtml(self: *TokenizerState) error{OutOfMemory}!void {
        assert(self.current <= self.lexemes.len);
        assert(self.lexemes[self.current].lexeme_type == .html_start);

        var count: usize = 0;
        while (self.current + count <= self.lexemes.len) {
            const lexeme_type = self.lexemes[self.current + count].lexeme_type;
            if (lexeme_type.isNewLine()) return self.addCurrentAs(.text);
            if (lexeme_type == .html_end) break;
            count += 1;
        }

        try self.addCombineChildren(.html, count + 1);
    }
};

pub fn tokenize(lexemes: LexemeList) TokenizeError!TokenList {
    var state = TokenizerState{
        .allocator = lexemes.allocator,
        .lexemes = lexemes.items,
        .tokens = TokenList{},
    };

    while (state.current < state.lexemes.len) {
        try state.addNextToken();
    }

    return state.tokens;
}

fn combineStrings(string_start: []const u8, string_end: []const u8) []const u8 {
    const ptr_start: usize = @intFromPtr(string_start.ptr);
    const ptr_end = @as(usize, @intFromPtr(string_end.ptr)) + string_end.len;

    return string_start.ptr[0 .. ptr_end - ptr_start];
}

test "tokenize" {
    const markdown_const = "## Test Header\nThat was a test header!";
    var buffer: [markdown_const.len]u8 = undefined;
    const markdown: []u8 = &buffer;
    @memcpy(markdown, markdown_const);

    const lexemes = try lexer.process(std.testing.allocator, markdown);
    defer lexemes.deinit();

    const tokens = try tokenize(lexemes);
    defer tokens.deinit(lexemes.allocator);

    try std.testing.expectEqual(7, tokens.tokens.len);
}

test "tokenize Italic Followed By Newline" {
    const lexemes = try lexer.process(std.testing.allocator, "*test*\ntest");
    defer lexemes.deinit();

    const tokens = try tokenize(lexemes);
    defer tokens.deinit(lexemes.allocator);

    try std.testing.expectEqual(2, tokens.tokens.len);
    try std.testing.expectEqual(.italic, tokens.tokens[0].token_type);
    try std.testing.expectEqual(.children, std.meta.activeTag(tokens.tokens[0].value));

    const children = tokens.tokens[0].value.children;
    try std.testing.expectEqual(1, children.tokens.len);
    try std.testing.expectEqual(.text, children.tokens[0].token_type);
    try std.testing.expectEqual(.lexeme, std.meta.activeTag(children.tokens[0].value));
    try std.testing.expectEqualStrings("test", children.tokens[0].value.lexeme);
    try std.testing.expectEqual(1, children.tokens[0].line);

    try std.testing.expectEqual(1, tokens.tokens[0].line);
    try std.testing.expectEqual(.text, tokens.tokens[1].token_type);
    try std.testing.expectEqual(.lexeme, std.meta.activeTag(tokens.tokens[1].value));
    try std.testing.expectEqualStrings("test", tokens.tokens[1].value.lexeme);
    try std.testing.expectEqual(2, tokens.tokens[1].line);
}
