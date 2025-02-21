const std = @import("std");
const zap = @import("zap");
const md4c = @cImport({
    @cInclude("md4c.h");
});

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
    try router.handle_func("/vi", self, &serveVI);
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

/// All routes are known to lead to real files
fn serveStatic(self: *Router, request: Request) void {
    request.sendFile(request.path.?[1..]) catch |err| self.handleError(request, err);
}

fn serveIndex(self: *const Router, request: Request) void {
    _ = self;
    request.sendFile("static/base.html") catch return;
}

fn serveFavicon(self: *const Router, request: Request) void {
    _ = self;
    request.sendFile("static/favicon.ico") catch return;
}

fn serveVI(self: *Router, request: Request) void {
    request.parseBody() catch |err| return self.handleError(request, err);
    request.parseQuery();

    const LocationType = struct { location: []const u8 };
    const json = std.json.parseFromSlice(LocationType, self.allocator, request.body.?, .{}) catch |err|
        return self.handleError(request, err);
    defer json.deinit();
    const location = json.value.location[if (json.value.location[0] == '/') 1 else 0..];

    const dir_path_end = std.mem.lastIndexOfScalar(u8, location, '/') orelse 0;
    const dir_path = location[0..dir_path_end];
    std.log.debug("Dir: {s}", .{dir_path});

    // Make sure that the file is real and that the path is valid
    const dir_real_path = getRealpath(self.allocator, self.docs_dir, self.docs_dir_path, dir_path) catch |err|
        return self.handleError(request, err);
    defer self.allocator.free(dir_real_path);

    var dir = self.docs_dir.openDir(dir_real_path, .{ .iterate = true }) catch |err|
        return self.handleError(request, err);
    defer dir.close();

    var file_name: []const u8 = "";

    var iterator = dir.iterate();
    while (iterator.next() catch |err| return self.handleError(request, err)) |file| {
        if (file.kind != .file) continue;
        const display_name = getFileName(self.allocator, dir, file.name) catch |err|
            return self.handleError(request, err);
        defer self.allocator.free(display_name);

        std.log.debug("Display name: {s}\nFile name: {s}", .{ display_name, location[dir_path.len + 1 ..] });
        if (eql(u8, display_name, location[dir_path.len + 1 ..])) {
            file_name = self.allocator.dupe(u8, file.name) catch |err|
                return self.handleError(request, err);
            break;
        }
    }
    defer self.allocator.free(file_name);

    const file_real_path = self.allocator.alloc(
        u8,
        dir_real_path.len + 1 + file_name.len,
    ) catch |err|
        return self.handleError(request, err);
    defer self.allocator.free(file_real_path);

    @memcpy(file_real_path[0..dir_real_path.len], dir_real_path);
    file_real_path[dir_real_path.len] = '/';
    @memcpy(file_real_path[dir_real_path.len + 1 ..], file_name);

    std.log.debug("{s}", .{file_real_path});

    // Read in file contents, max size 1 MiB
    const file_contents = self.docs_dir.readFileAlloc(
        self.allocator,
        file_real_path,
        1024 * 1024,
    ) catch |err| return self.handleError(request, err);
    defer self.allocator.free(file_contents);

    const tokens = @import("tokenizer.zig").tokenize(self.allocator, file_contents) catch |err|
        return self.handleError(request, err);
    defer tokens.deinit();

    var writer = std.io.getStdOut().writer();
    for (tokens.items) |token| {
        token.write(writer) catch |err| return self.handleError(request, err);
        writer.writeAll("\n") catch |err| return self.handleError(request, err);
    }

    // Response with result
    request.setStatus(.ok);
    request.setContentType(.HTML) catch |err|
        return self.handleError(request, err);
    request.sendBody(file_contents) catch |err|
        return self.handleError(request, err);
}

fn serveLS(self: *Router, request: Request) void {
    // TODO: Better error handling
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
    const location = if (json.value.location[0] == '/') json.value.location[1..] else json.value.location;

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
                sub_paths.append(next.name) catch |err| return self.handleError(request, err);
            },
            .file => {
                if (!eql(u8, next.name[next.name.len - 3 ..], ".md")) continue;

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
    // TODO: Better error handling
    request.parseBody() catch {};
    request.parseQuery();

    const LocationType = struct { location: []const u8 };
    const json = std.json.parseFromSlice(LocationType, self.allocator, request.body.?, .{}) catch |err|
        return self.handleError(request, err);
    defer json.deinit();

    if (json.value.location.len < 1) return self.handleError(request, error.BadRequest);
    const location = json.value.location;

    // Make sure the directory is valid (exists and is in a valid location)
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
        offset += 7 + (std.mem.indexOf(u8, file_contents[3..], "---") orelse
            return error.ParseError);

    if (eql(u8, file_contents[offset..][0..2], "# ")) {
        const contents = file_contents[offset + 2 ..];
        const end_of_line = std.mem.indexOfScalar(u8, contents, '\n') orelse contents.len;

        const result = try allocator.alloc(u8, end_of_line + 3);
        errdefer allocator.free(result);

        @memcpy(result[0..end_of_line], contents[0..end_of_line]);
        @memcpy(result[end_of_line..], ".md");

        return result;
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
