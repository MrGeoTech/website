const builtin = @import("builtin");
const std = @import("std");
const zap = @import("zap");
const lexer = @import("lexer.zig");
const tokenizer = @import("tokenizer.zig");
const compiler = @import("compiler.zig");

const ns_per_us = std.time.ns_per_us;

//const Router = @import("router.zig");
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub fn main() !void {
    std.log.info("Setting up server...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var docs_dir = try std.fs.cwd().openDir("docs", .{});
    defer docs_dir.close();

    const markdown = try docs_dir.readFileAlloc(
        allocator,
        "test.md",
        //"School/ECE 111: Intro to ECE/EX02.md",
        1024 * 1024,
    );
    defer allocator.free(markdown);

    //const markdown = "## Test Header\nThat was a **test header**.\n**test\n\ntest  \ntesting";

    var timer = try std.time.Timer.start();
    const lexemes = try lexer.process(allocator, markdown);
    defer lexemes.deinit();
    const lexer_time = timer.read() / ns_per_us;

    const writer = std.io.getStdOut().writer();
    for (lexemes.items) |lexeme| {
        try lexeme.write(writer);
        try writer.writeByte('\n');
    }

    timer.reset();
    const tokens = try tokenizer.tokenize(lexemes);
    defer tokens.deinit(lexemes.allocator);
    const tokenize_time = timer.read() / ns_per_us;

    for (tokens.tokens) |token| {
        try token.write(writer);
        try writer.writeByte('\n');
    }

    timer.reset();
    const result = try compiler.compile(allocator, tokens);
    defer allocator.free(result);
    const compile_time = timer.read() / ns_per_us;

    std.log.info("{s}", .{result});

    std.log.info("Lexer Time: {d} us", .{lexer_time});
    std.log.info("Tokenize Time: {d} us", .{tokenize_time});
    std.log.info("Compile Time: {d} us", .{compile_time});

    //var router = try Router.init(allocator);
    //defer router.deinit();

    //var router_zap = try router.getRouter();
    //defer router_zap.deinit();

    //std.log.info("Starting server", .{});
    //defer std.log.info("Stopping server", .{});

    // TODO: Uncomment
    //var listener = zap.HttpListener.init(.{
    //    .port = if (builtin.mode == .Debug) 8080 else 82,
    //    .on_request = router_zap.on_request_handler(),
    //    .log = true,
    //    .max_clients = 10_000,
    //});
    //try listener.listen();

    //zap.start(.{
    //    .threads = 1,
    //    .workers = 1,
    //});
}

test "main" {
    std.testing.refAllDeclsRecursive(lexer);
    std.testing.refAllDeclsRecursive(tokenizer);
}
