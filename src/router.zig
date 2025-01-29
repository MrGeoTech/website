const std = @import("std");
const zap = @import("zap");

const Request = zap.Request;
const Router = @This();

allocator: std.mem.Allocator,
docs_dir: std.fs.Dir,
docs_dir_path: []const u8,

pub fn init(allocator: std.mem.Allocator) !Router {
    const docs_dir = try std.fs.cwd().openDir("static/docs", .{});
    return .{
        .allocator = allocator,
        .docs_dir = docs_dir,
        .docs_dir_path = try docs_dir.realpathAlloc(allocator, "."),
    };
}

pub fn deinit(self: *Router) void {
    self.docs_dir.close();
    self.allocator.free(self.docs_dir_path);
}

fn notFound(request: Request) void {
    std.log.debug("404 Not found: {?s}", .{request.path});

    request.sendBody("<h1>404 Not Found</h1>\n<p>Could not find what you are looking for!</p>") catch return;
}

pub fn getRouter(self: *Router) !zap.Router {
    var router = zap.Router.init(self.allocator, .{
        .not_found = notFound,
    });

    try router.handle_func("/", self, &serveIndex);
    try router.handle_func("/docs", self, &serveDocs);
    try router.handle_func("/docs/", self, &serveDocs);

    return router;
}

fn serveIndex(self: *const Router, request: Request) void {
    _ = self;
    std.log.debug("Serving index", .{});

    request.sendFile("static/base.html") catch return;
}

fn serveDocs(self: *const Router, request: Request) void {
    request.parseQuery();

    const file_path = request.getParamStr(self.allocator, "path", false) catch
        return notFound(request) orelse
        return notFound(request);
    defer file_path.deinit();

    // Make sure that the file is real and that the path is valid
    const real_path = self.docs_dir.realpathAlloc(self.allocator, file_path.str) catch
        return notFound(request);
    defer self.allocator.free(real_path);

    if (real_path.len <= self.docs_dir_path.len) return;
    if (std.mem.eql(u8, real_path[0..self.docs_dir_path.len], self.docs_dir_path)) return;

    // Read in file contents, max size 1 MiB
    const file_contents = self.docs_dir.readFileAlloc(self.allocator, real_path, 1024 * 1024) catch return;
    defer self.allocator.free(file_contents);

    // TODO: Convert to HTML

    request.setStatus(.ok);
    request.setContentType(.HTML) catch return;
    request.sendBody(file_contents) catch return;
}

fn handleError(self: *const Router, request: Request, err: anyerror) void {
    _ = self;
    switch (err) {
        else => {
            var buffer: [1028]u8 = undefined;
            const body = std.fmt.bufPrint(
                &buffer,
                "<h1>500 Internal Server Error</h1>\n<p>Check error logs for error: {s}</p>",
                .{@errorName(err)},
            ) catch unreachable;

            request.setStatus(.internal_server_error);
            request.sendBody(body) catch return;
        },
    }
}
