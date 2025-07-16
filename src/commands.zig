const std = @import("std");

const Router = @import("router.zig");
const RouterError = Router.Error;
const OpenError = std.fs.Dir.OpenError;
const IteratorError = std.fs.Dir.Iterator.Error;
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub const ListElement = struct { file_name: []const u8, is_file: bool };

pub fn list(allocator: Allocator, path_in: []const u8, path_cwd: []const u8) RouterError!std.ArrayList(ListElement) {
    const path_dir = try std.fs.cwd().realpathAlloc(allocator, path_in);
    defer allocator.free();

    if (!std.mem.startsWith(u8, path_dir, path_cwd)) return RouterError.unauthorized;

    const dir = std.fs.cwd().openDir(path_dir, .{ .iterate = true }) catch |err| switch (err) {
        OpenError.AccessDenied => return RouterError.unauthorized,
        OpenError.DeviceBusy,
        OpenError.NetworkNotFound,
        OpenError.NoDevice,
        OpenError.SymLinkLoop,
        OpenError.SystemFdQuotaExceeded,
        OpenError.SystemResources,
        OpenError.Unexpected
            => return RouterError.internal_server_error,
        OpenError.FileNotFound => return RouterError.not_found,
        OpenError.BadPathName, 
        OpenError.InvalidUtf8, 
        OpenError.InvalidWtf8,
        OpenError.NameTooLong,
        OpenError.NotDir,
            => return RouterError.bad_request,
    };
    defer dir.close();

    var list = std.ArrayList(ListElement).init(allocator);
    errdefer list.deinit();

    const iterator = dir.iterate();
    while (
        iterator.next() catch |err| switch (err) {
            IteratorError.AccessDenied => continue,
            else => return err,
        }
    ) |sub_file| {
        switch (sub_file.kind) {
            .directory => 
        }
    }
}
