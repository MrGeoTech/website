const std = @import("std");
const zap = @import("zap");

const Request = zap.Request;
const Router = @This();

arena: std.heap.ArenaAllocator,
docs_dir: std.fs.Dir,
docs_dir_path: []const u8,
static_dir: std.fs.Dir,
static_dir_path: []const u8,

pub fn init(allocator: std.mem.Allocator) !Router {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const docs_dir = try std.fs.cwd().openDir("docs", .{});
    const static_dir = try std.fs.cwd().openDir("static", .{
        .iterate = true,
    });
    return .{
        .arena = arena,
        .docs_dir = docs_dir,
        .docs_dir_path = try docs_dir.realpathAlloc(arena.allocator(), "."),
        .static_dir = static_dir,
        .static_dir_path = try static_dir.realpathAlloc(arena.allocator(), "."),
    };
}

pub fn deinit(self: *Router) void {
    self.docs_dir.close();
    self.static_dir.close();
    self.arena.deinit();
}

fn notFound(request: Request) void {
    std.log.debug("404 Not found: {?s}", .{request.path});

    request.sendBody("<h1>404 Not Found</h1>\n<p>Could not find what you are looking for!</p>") catch return;
}

pub fn getRouter(self: *Router) !zap.Router {
    var router = zap.Router.init(self.arena.allocator(), .{
        .not_found = notFound,
    });

    try router.handle_func("/", self, &serveIndex);
    try router.handle_func("/docs", self, &serveDocs);
    try router.handle_func("/docs/", self, &serveDocs);

    var current_path_array: [1024]u8 = undefined;
    const current_path: []u8 = current_path_array[0..0];
    try self.addStaticDir(&router, self.static_dir, current_path, current_path_array.len);

    return router;
}

fn addStaticDir(self: *Router, router: *zap.Router, directory: std.fs.Dir, path: []u8, comptime max_len: comptime_int) !void {
    var current_path = path;
    var iterator = directory.iterate();
    while (try iterator.next()) |next| {
        const old_len = current_path.len;
        const new_len = old_len + 1 + next.name.len;
        std.debug.assert(new_len <= max_len);

        defer current_path = current_path[0..old_len];
        current_path = current_path.ptr[0..new_len];
        current_path[old_len] = '/';
        @memcpy(current_path[old_len + 1 ..], next.name);

        std.log.debug("{s}", .{current_path});

        switch (next.kind) {
            .file => {
                const static_len = current_path.len + 7;
                std.debug.assert(static_len <= max_len);

                var static_path: [max_len]u8 = undefined;
                @memcpy(static_path[0..7], "/static");
                @memcpy(static_path[7..static_len], current_path);

                std.log.debug("{s}", .{static_path[0..static_len]});

                try router.handle_func(
                    try self.arena.allocator().dupe(u8, static_path[0..static_len]),
                    self,
                    &serveStatic,
                );
            },
            .directory => {
                var dir = try directory.openDir(current_path[1..], .{ .iterate = true });
                defer dir.close();
                try self.addStaticDir(router, dir, current_path, max_len);
            },
            else => {},
        }
    }
}

fn serveIndex(self: *const Router, request: Request) void {
    _ = self;
    std.log.debug("Serving index", .{});

    request.sendFile("static/base.html") catch return;
}

fn serveDocs(self: *Router, request: Request) void {
    const allocator = self.arena.allocator();

    request.parseBody() catch |err| self.handleError(request, err);
    request.parseQuery();

    const file_path = (request.getParamStr(allocator, "path", false) catch |err|
        return self.handleError(request, err)) orelse
        return self.handleError(request, error.BadRequest);
    defer file_path.deinit();

    // Make sure that the file is real and that the path is valid
    const real_path = self.docs_dir.realpathAlloc(allocator, file_path.str) catch |err|
        return self.handleError(request, err);
    defer allocator.free(real_path);

    if (real_path.len <= self.docs_dir_path.len)
        return self.handleError(request, error.BadRequest);
    if (std.mem.eql(u8, real_path[0..self.docs_dir_path.len], self.docs_dir_path))
        return self.handleError(request, error.BadRequest);

    // Read in file contents, max size 1 MiB
    const file_contents = self.docs_dir.readFileAlloc(
        allocator,
        real_path,
        1024 * 1024,
    ) catch |err| return self.handleError(request, err);
    defer allocator.free(file_contents);

    // TODO: Convert to HTML

    // Response with result
    request.setStatus(.ok);
    request.setContentType(.HTML) catch |err|
        return self.handleError(request, err);
    request.sendBody(file_contents) catch |err|
        return self.handleError(request, err);
}

/// All routes are known to lead to real files
fn serveStatic(self: *const Router, request: Request) void {
    request.sendFile(request.path.?[1..]) catch |err| self.handleError(request, err);
}

fn handleError(self: *const Router, request: Request, err: anyerror) void {
    _ = self;
    // Attempt to log stack trace incase it is needed to figure out errors
    std.log.warn("An error occured while trying to process a request: {!}", .{err});
    // Reponse with an error code and explination
    switch (err) {
        error.BadRequest => {
            const reponse =
                \\<h1>400 Bad Request</h1>
                \\<p>Invalid request! Make sure all parameters are set properly and try again.</p>
            ;
            request.setStatus(.not_found);
            request.sendBody(reponse) catch return;
        },
        error.FileNotFound => {
            const reponse =
                \\<h1>404 Not Found</h1>
                \\<p>Could not find file at given location.</p>
            ;
            request.setStatus(.not_found);
            request.sendBody(reponse) catch return;
        },
        error.AccessDenied => {
            const reponse =
                \\<h1>403 Forbidden</h1>
                \\<p>The request file location is unaccessable with your current permissions.
                \\Make sure you have the proper permissions</p>
            ;
            request.setStatus(.forbidden);
            request.sendBody(reponse) catch return;
        },
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
