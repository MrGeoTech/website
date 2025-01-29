const builtin = @import("builtin");
const std = @import("std");
const zap = @import("zap");

const Router = @import("router.zig");
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub fn main() !void {
    std.log.info("Setting up server...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var router = try Router.init(allocator);
    defer router.deinit();

    var router_zap = try router.getRouter();
    defer router_zap.deinit();

    std.log.info("Starting server", .{});

    var listener = zap.HttpListener.init(.{
        .port = if (builtin.mode == .Debug) 8080 else 82,
        .on_request = router_zap.on_request_handler(),
        .log = true,
        .max_clients = 10_000,
    });
    try listener.listen();

    zap.start(.{
        .threads = 1,
        .workers = 1,
    });
}
