const builtin = @import("builtin");
const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub fn main() !void {
    std.log.info("Setting up server...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    std.log.info("Starting server", .{});

    var listener = zap.HttpListener.init(.{
        .port = if (builtin.mode == .Debug) 8080 else 82,
        .on_request = dispatch_routes,
        .log = true,
    });

    std.log.info("Starting http server", .{});

}

var routes: std.StringHashMap(zap.HttpRequestFn) = undefined;

pub fn setup_routes(allocator: Allocator) !void {
    routes = std.StringHashMap(zap.HttpRequestFn).init(allocator);
    try routes.put("", );
}

pub fn dispatch_routes(request: zap.Request) void {}

pub fn serve_index(request: zap.Request) void {
    request.sendFile("static/base.html");
}
