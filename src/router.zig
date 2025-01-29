const std = @import("std");
const zap = @import("zap");

const Request = zap.Request;
const Router = @This();

allocator: std.mem.Allocator,
dir_docs: std.fs.Dir,

fn notFound(request: Request) void {
    std.log.debug("404 Not found: {?s}", .{request.path});

    request.sendBody("<h1>404 Not Found</h1>\n<p>Could not find what you are looking for!</p>");
}

pub fn getRouter(self: *const Router) zap.Router {
    var router = zap.Router.init(self.allocator, .{
        .not_found = notFound,
    });

    router.handle_func("/", self, serveIndex);
    router.handle_func("/docs", self, serveDocs);
}

fn serveIndex(self: *const Router, request: Request) void {
    std.log.debug("Serving index", .{});

    request.sendFile("static/base.html");
}

fn serveDocs(self: *const Router, request: Request) void {
    request.parseQuery();

    const file_path = request.getParamStr(self.allocator, "file", false) catch return orelse return;
    defer file_path.deinit();
}
