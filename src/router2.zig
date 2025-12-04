const std = @import("std");
const http = std.http;

const Allocator = std.mem.Allocator;

pub fn handleRequest(child_allocator: Allocator, request: http.Server.Request) error{OutOfMemory}!void {
    const arena = std.heap.ArenaAllocator.init(child_allocator);
    defer arena.deinit();

    var header_iterator = request.iterateHeaders();
    while (header_iterator.next()) |header| {
        std.log.debug("{s} : {s}", .{header.name, header.value});
    }
}
