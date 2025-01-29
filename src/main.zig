const builtin = @import("builtin");
const std = @import("std");
const http = std.http;

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub fn main() !void {
    std.log.info("Setting up server...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    std.log.info("Starting server", .{});

    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8080);
    var server = try address.listen(.{
        .force_nonblocking = true,
    });
    defer server.deinit();

    std.log.info("Starting http server", .{});

    const read_buffer: *[2048]u8 = (try allocator.alloc(u8, 2048))[0..2048];

    const running = true;
    while (running) {
        const connection = server.accept() catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        defer connection.stream.close();
        var http_connection = http.Server.init(connection, read_buffer);

        var request = try http_connection.receiveHead();
        try switch (request.head.method) {
            .GET => handleGet(&request, allocator) catch fail(&request, .internal_server_error),
            else => fail(&request, .bad_request),
        };
    }
}

pub fn fail(request: *http.Server.Request, status: http.Status) !void {
    try request.respond(
        \\Well, shit! An error has occured. Please try again!
    , .{
        .status = status,
    });
}

pub fn handleGet(request: *http.Server.Request, allocator: Allocator) !void {
    std.log.info("Receiving request: {s} {s} {s}", .{
        @tagName(request.head.method),
        request.head.target,
        @tagName(request.head.version),
    });
    std.log.info("Content Type: {?s} ", .{
        request.head.content_type,
    });

    var headers = std.ArrayList(http.Header).init(allocator);
    var iterator = request.iterateHeaders();
    while (iterator.next()) |header| {
        try headers.append(header);
        if (header.name.len != 10) continue;

        var name_lower: [10]u8 = undefined;
        @memcpy(&name_lower, header.name);
        for (name_lower, 0..) |c, i| {
            name_lower[i] = std.ascii.toLower(c);
        }

        if (std.mem.eql(u8, &name_lower, "user-agent")) {
            std.log.info("User-Agent: {s}", .{header.value});
        }
    }

    const target = request.head.target;
    const target_type = FileType.extract(target);

    if (target_type == .other) return fail(request, .teapot);
}

const FileType = enum {
    dir,
    html,
    css,
    images,
    md,
    pdf,
    docx,
    other,

    pub fn extract(path: []const u8) FileType {
        // Path has to be <path/<filename>.<extension> to match.
        // We have to make sure that there is a file name, hence
        // the additional 1 on the bounds checking
        if (path.len > 5)
            if (std.mem.eql(u8, path[path.len - 5 ..], ".html"))
                return .html
            else if (std.mem.eql(u8, path[path.len - 5 ..], ".docx"))
                return .docx
            else if (std.mem.eql(u8, path[path.len - 5 ..], ".jpeg"))
                return .images;

        if (path.len > 4)
            if (std.mem.eql(u8, path[path.len - 4 ..], ".css"))
                return .css
            else if (std.mem.eql(u8, path[path.len - 4 ..], ".pdf"))
                return .pdf
            else if (std.mem.eql(u8, path[path.len - 4 ..], ".png"))
                return .images
            else if (std.mem.eql(u8, path[path.len - 4 ..], ".jpg"))
                return .images;

        if (path.len > 3)
            if (std.mem.eql(u8, path[path.len - 3 ..], ".md"))
                return .md;

        if (path.len > 0)
            if (path[path.len - 1] == '/')
                return .dir;

        return .other;
    }
};
