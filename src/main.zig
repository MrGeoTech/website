const builtin = @import("builtin");
const std = @import("std");
const router = @import("router2.zig");
//const zap = @import("zap");

//const Router = @import("router.zig");
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

const ConnectionData = struct {
    connection: std.net.Server.Connection,
    http: std.http.Server,
    buffer_reader: []u8,
    buffer_writer: []u8,
};

pub fn main() !void {
    std.log.info("Setting up server...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    std.debug.print("\n{d}\n", .{std.heap.defaultQueryPageSize()});

    std.log.info("Starting server", .{});
    defer std.log.info("Stopping server", .{});

    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8080);
    const server = try address.listen(.{
        .force_nonblocking = true,
    });

    var connections = try std.ArrayList(ConnectionData).initCapacity(allocator, 64);
    defer connections.deinit(allocator);


    while (true) {
        accept_blk: {
            const connection = server.accept() catch |err| switch (err) {
                .WouldBlock => break :accept_blk,
                else => return err,
            };

            const buffer_reader = try allocator.alloc(u8, std.heap.defaultQueryPageSize());
            defer allocator.free(buffer_reader);
            const buffer_writer = try allocator.alloc(u8, std.heap.defaultQueryPageSize());
            defer allocator.free(buffer_writer);
            
            var reader = connection.stream.reader(buffer_reader);
            var writer = connection.stream.writer(buffer_writer);

            const http = std.http.Server.init(reader.interface(), &writer.interface);

            try connections.append(allocator, .{
                .connection = connection,
                .http = http,
                .buffer_reader = buffer_reader,
                .buffer_writer = buffer_writer,
            });
        }

        request_blk: {
            for (connections.items) |connection_data| {
                const request = connection_data.http.receiveHead() catch |err| switch (err) {
                    .WouldBlock => continue,
                    else => return err,
                };
                try router.handleRequest(allocator, request);
            }
        }
    }
}

const lexer = @import("lexer.zig");
const tokenizer = @import("tokenizer.zig");
const compiler = @import("compiler.zig");

test "main" {
    std.testing.refAllDeclsRecursive(lexer);
    std.testing.refAllDeclsRecursive(tokenizer);
}
