const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const Request = zap.Request;
const Router = @This();

const eql = std.mem.eql;

allocator: Allocator,
/// This should only be used for the paths of the static files.
/// Everything else should be deallocated explicitly
arena: *std.heap.ArenaAllocator,
docs_dir: std.fs.Dir,
docs_dir_path: []const u8,
static_dir: std.fs.Dir,
static_dir_path: []const u8,

pub fn init(allocator: Allocator) !Router {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);

    var docs_dir = try std.fs.cwd().openDir("docs", .{});
    errdefer docs_dir.close();

    var static_dir = try std.fs.cwd().openDir("static", .{
        .iterate = true,
    });
    errdefer static_dir.close();

    const docs_dir_path = try docs_dir.realpathAlloc(allocator, ".");
    errdefer allocator.free(docs_dir_path);

    const static_dir_path = try static_dir.realpathAlloc(allocator, ".");
    errdefer allocator.free(static_dir_path);

    return .{
        .allocator = allocator,
        .arena = arena,
        .docs_dir = docs_dir,
        .docs_dir_path = docs_dir_path,
        .static_dir = static_dir,
        .static_dir_path = static_dir_path,
    };
}

pub fn deinit(self: *Router) void {
    self.docs_dir.close();
    self.static_dir.close();
    self.allocator.free(self.docs_dir_path);
    self.allocator.free(self.static_dir_path);
    self.arena.deinit();
    self.allocator.destroy(self.arena);
}

fn notFound(request: Request) void {
    std.log.debug("404 Not found: {?s}", .{request.path});

    request.setStatus(.not_found);
    request.sendBody("<h1>404 Not Found</h1>\n<p>Could not find what you are looking for!</p>") catch return;
}

pub fn getRouter(self: *Router) !zap.Router {
    var router = zap.Router.init(self.allocator, .{
        .not_found = notFound,
    });

    try router.handle_func("/", self, &serveIndex);
    try router.handle_func("/favicon.ico", self, &serveFavicon);
    try router.handle_func("/docs", self, &serveDocs);
    try router.handle_func("/docs/", self, &serveDocs);
    try router.handle_func("/ls", self, &serveLS);
    try router.handle_func("/cd", self, &serveCD);

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
    request.sendFile("static/base.html") catch return;
}

fn serveFavicon(self: *const Router, request: Request) void {
    _ = self;
    request.sendFile("static/favicon.ico") catch return;
}

fn serveDocs(self: *Router, request: Request) void {
    request.parseBody() catch |err| self.handleError(request, err);
    request.parseQuery();

    const file_path = (request.getParamStr(self.allocator, "path", false) catch |err|
        return self.handleError(request, err)) orelse
        return self.handleError(request, error.BadRequest);
    defer file_path.deinit();

    // Make sure that the file is real and that the path is valid
    const real_path = getRealpath(self.allocator, self.docs_dir, self.docs_dir_path, file_path.str) catch |err|
        return self.handleError(request, err);
    defer self.allocator.free(real_path);

    // Read in file contents, max size 1 MiB
    const file_contents = self.docs_dir.readFileAlloc(
        self.allocator,
        real_path,
        1024 * 1024,
    ) catch |err| return self.handleError(request, err);
    defer self.allocator.free(file_contents);

    // TODO: Convert to HTML

    // Response with result
    request.setStatus(.ok);
    request.setContentType(.HTML) catch |err|
        return self.handleError(request, err);
    request.sendBody(file_contents) catch |err|
        return self.handleError(request, err);
}

/// All routes are known to lead to real files
fn serveStatic(self: *Router, request: Request) void {
    request.sendFile(request.path.?[1..]) catch |err| self.handleError(request, err);
}

fn serveLS(self: *Router, request: Request) void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    request.parseBody() catch {};
    request.parseQuery();

    const LocationType = struct { location: []const u8 };
    const json = std.json.parseFromSlice(LocationType, allocator, request.body.?, .{}) catch |err|
        return self.handleError(request, err);
    defer json.deinit();

    if (json.value.location.len < 1) return self.handleError(request, error.BadRequest);
    const location = json.value.location;
    std.log.debug("Location {s}", .{location});

    // Make sure that the file is real and that the path is valid
    const real_path = getRealpath(allocator, self.docs_dir, self.docs_dir_path, location) catch |err|
        return self.handleError(request, err);
    defer allocator.free(real_path);

    var dir = self.docs_dir.openDir(real_path, .{ .iterate = true }) catch |err|
        return self.handleError(request, err);
    defer dir.close();

    var sub_paths = std.ArrayList([]const u8).init(allocator);
    defer sub_paths.deinit();

    var iterator = dir.iterate();
    while (iterator.next() catch |err| return self.handleError(request, err)) |next| {
        switch (next.kind) {
            .directory => {
                if (eql(u8, next.name, ".git")) continue;
                std.log.debug("Dir  {s}", .{next.name});
                sub_paths.append(next.name) catch |err| return self.handleError(request, err);
            },
            .file => {
                std.log.debug("File {s}", .{next.name});
                if (!eql(u8, next.name[next.name.len - 4 ..], ".md")) continue;

                // Check if there a different name for the file
                const file_name = getFileName(allocator, dir, next.name) catch |err|
                    return self.handleError(request, err);

                sub_paths.append(file_name) catch |err| return self.handleError(request, err);
            },
            else => {},
        }
    }

    var length: usize = 0;
    for (sub_paths.items) |item| {
        length += item.len + 1;
    }

    var offset: usize = 0;
    var response = allocator.alloc(u8, length) catch |err| return self.handleError(request, err);

    for (sub_paths.items) |item| {
        @memcpy(response[offset .. offset + item.len], item);
        offset += item.len;

        response[offset] = '\n';
        offset += 1;
    }

    request.setStatus(.ok);
    request.setContentType(.TEXT) catch |err|
        return self.handleError(request, err);
    request.sendBody(response) catch |err|
        return self.handleError(request, err);
}

fn serveCD(self: *Router, request: Request) void {
    request.parseBody() catch {};
    request.parseQuery();

    const LocationType = struct { location: []const u8 };
    const json = std.json.parseFromSlice(LocationType, self.allocator, request.body.?, .{}) catch |err|
        return self.handleError(request, err);
    defer json.deinit();

    if (json.value.location.len < 1) return self.handleError(request, error.BadRequest);
    const location = json.value.location[1..]; // Skip first byte, which will be a '/'
    std.log.debug("Location {s} {s}", .{ json.value.location, location });

    // Make sure that the file is real and that the path is valid
    const real_path = getRealpath(self.allocator, self.docs_dir, self.docs_dir_path, location) catch |err|
        return self.handleError(request, err);
    defer self.allocator.free(real_path);

    request.setStatus(.ok);
    request.setContentType(.TEXT) catch |err|
        return self.handleError(request, err);
    request.sendBody(real_path[self.docs_dir_path.len..]) catch |err|
        return self.handleError(request, err);
}

fn getRealpath(allocator: Allocator, dir: std.fs.Dir, dir_path: []const u8, path: []const u8) ![]const u8 {
    const real_path = dir.realpathAlloc(allocator, path) catch |err|
        return err;
    errdefer allocator.free(real_path);

    if (real_path.len < dir_path.len)
        return error.BadRequest;
    if (!std.mem.eql(u8, real_path[0..dir_path.len], dir_path))
        return error.BadRequest;

    return real_path;
}

fn getFileName(allocator: Allocator, dir: std.fs.Dir, file: []const u8) ![]const u8 {
    const file_contents = try dir.readFileAlloc(
        allocator,
        file,
        1024 * 1024,
    );
    defer allocator.free(file_contents);

    var offset: usize = 0;
    if (eql(u8, file_contents[0..3], "---"))
        // Add 8 to account for the first and last "---\n"
        offset += 8 + (std.mem.indexOf(u8, file_contents[3..], "---") orelse
            return error.ParseError);

    if (eql(u8, file_contents[offset..][0..2], "# ")) {
        const contents = file_contents[offset + 2 ..];
        const end_of_line = std.mem.indexOfScalar(u8, contents, '\n') orelse contents.len;
        return allocator.dupe(u8, contents[0..end_of_line]);
    } else {
        return allocator.dupe(u8, file);
    }
}

fn handleError(self: *Router, request: Request, err: anyerror) void {
    // Attempt to log stack trace incase it is needed to figure out errors
    std.log.warn("An error occured while trying to process a request: {!}", .{err});
    logStackTrace(self.allocator);
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

fn logStackTrace(allocator: Allocator) void {
    var debug_info = std.debug.DebugInfo{
        .allocator = allocator,
        .address_map = std.AutoHashMap(usize, *std.debug.ModuleDebugInfo).init(allocator),
        .modules = {},
    };
    defer debug_info.deinit();

    const std_err = std.io.getStdErr();
    std.debug.writeCurrentStackTrace(std_err.writer(), &debug_info, std.io.tty.detectConfig(std_err), null) catch return;
}
