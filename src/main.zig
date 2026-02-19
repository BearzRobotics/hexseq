const std = @import("std");
const Io = std.Io;

const dklib = @import("dklib.zig");

// Constants go here
const version = "0.0.9";
const hex = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

const RolloverEnum = enum(u8) {
    none,
    delete,
    move,
};

// Runtime configs should be placed here
const Config = struct {
    debug: bool = false,
    log_dir_set: bool = false,
    log_dir: []const u8 = &.{},
    rollover: RolloverEnum = RolloverEnum.none,
    rollover_path_provided: bool = false,
    rollover_target: []const u8 = &.{},
    rollover_need: bool = false,
    version: bool = false,
    preserve_timestamps: bool = true,
};

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);

    const cfg = try parse_args(args, stdout);

    var old_logs = try get_logs(io, arena, cfg, stdout);
    defer {
        for (old_logs.items) |f| {
            arena.free(f);
        }
        old_logs.deinit(arena);
    }

    var current_logs = try find_current_log(arena, old_logs);
    defer current_logs.deinit(arena);

    try write_logs(arena, io, current_logs, old_logs, cfg);

    try stdout.flush(); // Don't forget to flush!
}

fn parse_args(args: []const [:0]const u8, stdout: *Io.Writer) !Config {
    // lets create our Config Struct
    var cfg = Config{};

    var i: usize = 1; // skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                try help(stdout);
            } else if (std.mem.eql(u8, arg, "--debug")) {
                cfg.debug = true;
            } else if (std.mem.eql(u8, arg, "--version")) {
                cfg.version = true;
                std.debug.print("hexsql version: {s}\n", .{version});
                dklib.exit_with(dklib.ExitCode.ok);
            } else if (std.mem.eql(u8, arg, "--logdir")) {
                i += 1;
                if (i >= args.len) {
                    std.debug.print("Failed to pass in <path> for --logdir\n", .{});
                    dklib.exit_with(dklib.ExitCode.usage);
                }

                cfg.log_dir = args[i];
                cfg.log_dir_set = true;
            } else if (std.mem.eql(u8, arg, "--rollover=delete")) {
                cfg.rollover = RolloverEnum.delete;
            } else if (std.mem.eql(u8, arg, "--rollover=move")) {
                cfg.rollover = RolloverEnum.move;

                i += 1;
                if (i >= args.len) {
                    std.debug.print("Failed to pass in <path> for --rollover=move \n", .{});
                    dklib.exit_with(dklib.ExitCode.usage);
                }

                cfg.rollover_target = args[i];
            } else if (std.mem.eql(u8, arg, "--preserve")) {
                cfg.preserve_timestamps = true;
            }
        } else {
            for (arg[1..]) |opt| {
                if (opt == 'd') {
                    cfg.debug = true;
                } else if (opt == 'v') {
                    cfg.version = true;
                } else if (opt == 'p') {
                    cfg.preserve_timestamps = true;
                }
            }
        }
    }

    if (cfg.version == true) {
        std.debug.print("hexsql version: {s}\n", .{version});
        dklib.exit_with(dklib.ExitCode.ok);
    } else if (cfg.log_dir_set == false) {
        std.debug.print("--logdir is required!\n", .{});
        dklib.exit_with(dklib.ExitCode.usage);
    }

    return cfg;
}

fn help(stdout: *Io.Writer) !void {
    try stdout.print("hexseq - hexadecimal log rotator\n\n", .{});
    try stdout.print("Usage: hexseq [options] --logdir <path>\n\n", .{});
    try stdout.print("-h    --help                       Prints help menu\n", .{});
    try stdout.print("-d    --debug                      Enable printing internal debug statements to std::err\n", .{});
    try stdout.print("-v    --version                    Prints the programs version\n", .{});
    try stdout.print("--logdir <path>                    Takes a path to the root of your log dir\n", .{});
    try stdout.print("--rollover=[delete|move] <path>    When you reach .FFF it deletes all old logs and starts fresh at .000\n", .{});
    try stdout.print("                                   Moves all old logs once you reach .FFF to a dir of your choice\n", .{});
    try stdout.print("-p  --preserve                     Perserve timestamps on files\n", .{});

    try stdout.flush(); // Don't forget to flush!
    dklib.exit_with(dklib.ExitCode.ok);
}

fn dec2hex(input: u16) [3]u8 {
    var index: usize = 3;
    var value = input;
    var buffer = [_]u8{ '0', '0', '0' };

    while (index > 0) {
        index -= 1;
        buffer[index] = hex[value % 16];
        value = value / 16;
        if (value == 0) break;
    }

    return buffer;
}

fn count_logs(current_logs: []const u8, old_logs: std.ArrayList([]const u8)) u16 {
    var oLC: u16 = 0;

    for (old_logs.items) |f| {
        if (std.mem.lastIndexOf(u8, f, ".")) |dot_index| {
            const suffix = f[dot_index + 1 ..];
            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]) and
                std.mem.eql(u8, current_logs, f[0..dot_index]))
            {
                oLC += 1;
            }
        }
    }

    return oLC;
}

fn get_logs(io: Io, ally: std.mem.Allocator, cfg: Config, stdout: *Io.Writer) !std.ArrayList([]const u8) {
    var logs = std.ArrayList([]const u8).empty;

    try stdout.print("cfg.log_dir: {s}\n", .{cfg.log_dir});

    var dir = try Io.Dir.openDirAbsolute(io, cfg.log_dir, .{ .iterate = true });

    defer dir.close(io);

    var walker = try dir.walk(ally);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // only grab files
        if (entry.kind == .file) {
            // base + entry.path (relative path.
            const fPath = try std.fs.path.join(ally, &.{ cfg.log_dir, entry.path });

            // Allocate a duplicate string since walk() gives temporary memory
            // we need to use dupe to keep the data alive past the defer of std.fs.cwd().openDir
            const path_copy = try ally.dupe(u8, fPath);

            if (cfg.debug == true) {
                std.debug.print("get_logs() - Old logs: {s}\n", .{path_copy});
            }

            try logs.append(ally, path_copy);

            ally.free(fPath);
        }
    }

    return logs;
}

fn find_current_log(ally: std.mem.Allocator, old_logs: std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var current_logs = std.ArrayList([]const u8).empty;
    // because we are returning this the defer should be where the function is called.

    for (old_logs.items) |f| {
        // https://ziglang.org/documentation/0.14.0/std/#std.mem.lastIndexOf
        if (std.mem.lastIndexOf(u8, f, ".")) |dot_index| {
            const suffix = f[dot_index + 1 ..];
            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]))
            {
                // This is an old log file
            } else {
                try current_logs.append(ally, f);
            }
        } else {
            // no dot = current log file
            try current_logs.append(ally, f);
        }
    }
    return current_logs;
}

// Totally used ChatGPT for this....
fn split_ns_to_timespec(ts: ?Io.Timestamp) !std.os.linux.timespec {
    const t = ts orelse return error.NoTimestamp;
    const ns: i128 = @intCast(t.toNanoseconds());
    const sec = std.math.cast(isize, @divTrunc(ns, 1_000_000_000)) orelse return error.TimeTooLarge;
    const nsec = std.math.cast(isize, @rem(ns, 1_000_000_000)) orelse return error.TimeTooLarge;
    return .{ .sec = sec, .nsec = nsec };
}

fn write_logs(ally: std.mem.Allocator, io: Io, cLogs: std.ArrayList([]const u8), old_logs: std.ArrayList([]const u8), cfg: Config) !void {
    const cwd = Io.Dir.cwd();
    if (cfg.preserve_timestamps == true) {
        for (cLogs.items, 0..) |c, i| {
            const count = count_logs(c, old_logs);
            const nhex = dec2hex(count);

            const new_name = try std.mem.concat(ally, u8, &.{ c, "."[0..], nhex[0..] });
            defer ally.free(new_name);

            // get time stamp

            const file = try Io.Dir.openFile(cwd, io, c, .{});
            const stat = try file.stat(io);

            if (cfg.debug == true) {
                std.debug.print("New logs to be writtn[{d}]: {s}\n", .{ i, new_name });
            }

            try Io.Dir.rename(cwd, c, cwd, new_name, io);

            // restore timestamps
            const times = [_]std.os.linux.timespec{
                try split_ns_to_timespec(stat.atime),
                try split_ns_to_timespec(stat.mtime),
            };

            // Totally ChatGPT. -- Need to make sure I understand why this works
            const c_new_name = try ally.alloc(u8, new_name.len + 1);
            defer ally.free(c_new_name);

            std.mem.copyForwards(u8, c_new_name[0..new_name.len], new_name);

            c_new_name[new_name.len] = 0; // null terminator
            const c_path = c_new_name[0..new_name.len :0]; // automatically makes it `[*:0]const u8` if you remembered to zero-terminate
            const rc = std.os.linux.utimensat(std.os.linux.AT.FDCWD, c_path, &times, 0);
            if (rc == -1) return std.os.linux.getErrno(rc);

            if (cfg.rollover == RolloverEnum.delete and cfg.rollover_need == false) {
                try rollover(ally, io, cfg);
            } else if (count == 4095 and cfg.rollover_need == true) {
                try rollover(ally, io, cfg);
            }
        }
    } else {
        for (cLogs.items, 0..) |c, i| {
            const count = count_logs(c, old_logs);
            const nhex = dec2hex(count);

            const new_name = try std.mem.concat(ally, u8, &.{ c, "."[0..], nhex[0..] });
            defer ally.free(new_name);

            if (cfg.debug == true) {
                std.debug.print("New logs to be writtn[{d}]: {s}\n", .{ i, new_name });
            }

            try Io.Dir.rename(cwd, c, cwd, new_name, io);

            if (cfg.rollover == RolloverEnum.delete and cfg.rollover_need == false) {
                try rollover(ally, io, cfg);
            } else if (count == 4095 and cfg.rollover_need == false) {
                try rollover(ally, io, cfg);
            } else if (count == 4095 and cfg.rollover_need == true) {
                try rollover(ally, io, cfg);
            }
        }
    }
}

fn rollover(ally: std.mem.Allocator, io: Io, cfg: Config) !void {
    const cwd = Io.Dir.cwd();

    if (cfg.debug == true) {
        std.debug.print("Function rollOver() base: {s}\n", .{cfg.log_dir});
    }
    var basePath = cfg.log_dir; // copy to make it augmentable
    if (cfg.rollover == RolloverEnum.move) {
        if (cfg.rollover_path_provided == true) {
            basePath = cfg.rollover_target;
        } else {
            // if logdir is passed with a trailing / we need to remove it.

            if (cfg.log_dir.len > 0 and cfg.log_dir[cfg.log_dir.len - 1] == '/') {
                basePath = cfg.log_dir[0 .. cfg.log_dir.len - 1];
            }
        }

        const rpath = try std.fmt.allocPrint(ally, "{s}.000", .{basePath});
        defer ally.free(rpath);

        if (cfg.debug == true) {
            std.debug.print("Rollover dir: {s}\n", .{rpath});
        }

        try Io.Dir.rename(cwd, basePath, cwd, rpath, io);
        //try std.fs.cwd().rename(basePath, rpath);
    } else if (cfg.rollover == RolloverEnum.delete) {
        std.debug.print("Warning setting this flag will just delete the log dir!\n", .{});
        try Io.Dir.deleteTree(cwd, io, basePath);
    }
}

const testing = std.testing;

test "dec2hex gives correct 3-digit uppercase hex values" {
    try testing.expectEqualStrings("000", &dec2hex(0));
    try testing.expectEqualStrings("00F", &dec2hex(15));
    try testing.expectEqualStrings("010", &dec2hex(16));
    try testing.expectEqualStrings("2AF", &dec2hex(687));
    try testing.expectEqualStrings("3E7", &dec2hex(999));
    try testing.expectEqualStrings("FFF", &dec2hex(4095));

    dklib.dktest.passed("dec2hex gives correct 3-digit uppercase hex values");
}

test "get_logs pickup old_logs in test dir" {
    const io = std.testing.io;
    const ally = std.testing.allocator;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;
    const tmp_path = try root.realPathFileAlloc(io, ".", ally);
    defer ally.free(tmp_path);

    _ = try root.createFile(io, "dmesg", .{});
    _ = try root.createFile(io, "dmesg.000", .{});

    const subdir = try root.createDirPathOpen(io, "tlog", .{});
    _ = try subdir.createFile(io, "app.log", .{});
    _ = try subdir.createFile(io, "app.log.001", .{});
    _ = try subdir.createFile(io, "app.log.0F7", .{});

    const subdir2 = try root.createDirPathOpen(io, "log", .{});
    _ = try subdir2.createFile(io, "bearz.log", .{});
    _ = try subdir2.createFile(io, "bearz.log.001", .{});
    _ = try subdir2.createFile(io, "bearz.log.002", .{});

    var cfg = Config{};
    cfg.log_dir = tmp_path;

    var old_logs = try get_logs(io, ally, cfg, stdout);
    defer {
        for (old_logs.items) |f| {
            ally.free(f);
        }
        old_logs.deinit(ally);
    }

    for (old_logs.items, 0..) |f, i| {
        std.debug.print("old_logs[{d}]: {s}\n", .{ i, f });
    }

    try testing.expect(old_logs.items.len == 8);
    dklib.dktest.passed("get_logs maked a ArrayList of old_logs in test dir");
}

test "find_current_log" {
    const ally = std.testing.allocator;

    var old_logs = std.ArrayList([]const u8).empty;
    defer old_logs.deinit(ally);
    _ = try old_logs.append(ally, "/home/test/log/dmesg");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.001");
    _ = try old_logs.append(ally, "/home/test/log/app.log.001");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.002");
    _ = try old_logs.append(ally, "/home/test/log/app.log.000");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.000");
    _ = try old_logs.append(ally, "/home/test/log/app.log.002");
    _ = try old_logs.append(ally, "/home/test/log/app.log");

    var cLog = try find_current_log(ally, old_logs);
    defer cLog.deinit(ally);

    var found_dmesg = false;
    var found_applog = false;

    for (cLog.items) |f| {
        std.debug.print("{s}\n", .{f});
        if (std.mem.eql(u8, f, "/home/test/log/dmesg")) {
            found_dmesg = true;
        } else if (std.mem.eql(u8, f, "/home/test/log/app.log")) {
            found_applog = true;
        }
    }

    try std.testing.expect(found_dmesg);
    try std.testing.expect(found_applog);

    dklib.dktest.passed("find_current_logs");
}

test "count_logs" {
    const ally = std.testing.allocator;

    var old_logs = std.ArrayList([]const u8).empty;
    defer old_logs.deinit(ally);
    _ = try old_logs.append(ally, "/home/test/log/dmesg");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.001");
    _ = try old_logs.append(ally, "/home/test/log/app.log.001");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.002");
    _ = try old_logs.append(ally, "/home/test/log/app.log.000");
    _ = try old_logs.append(ally, "/home/test/log/dmesg.000");
    _ = try old_logs.append(ally, "/home/test/log/app.log.002");
    _ = try old_logs.append(ally, "/home/test/log/app.log.003");
    _ = try old_logs.append(ally, "/home/test/log/app.log");

    const count = count_logs("/home/test/log/dmesg", old_logs);
    std.debug.print("Number of old dmesg logs: {d}\n", .{count});

    const count2 = count_logs("/home/test/log/app.log", old_logs);
    std.debug.print("Number of old app.log logs: {d}\n", .{count2});

    try std.testing.expectEqual(3, count);
    try std.testing.expectEqual(4, count2);

    dklib.dktest.passed("Count_logs");
}

test "write_logs" {
    const io = std.testing.io;
    const ally = std.testing.allocator;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var cfg = Config{};

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;
    const tmp_path = try root.realPathFileAlloc(io, ".", ally);
    defer ally.free(tmp_path);

    _ = try root.createFile(io, "dmesg", .{});
    _ = try root.createFile(io, "app.log", .{});

    for (0..20) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(ally, u8, &.{ "dmesg"[0..], "."[0..], nhex[0..] });
        defer ally.free(new_name);
        _ = try root.createFile(io, new_name, .{});
    }

    for (0..10) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(ally, u8, &.{ "app.log"[0..], "."[0..], nhex[0..] });
        defer ally.free(new_name);
        _ = try root.createFile(io, new_name, .{});
    }

    cfg.log_dir = tmp_path;
    var old_logs = try get_logs(io, ally, cfg, stdout);
    defer {
        for (old_logs.items) |o| {
            ally.free(o);
        }
        old_logs.deinit(ally);
    }

    for (old_logs.items, 0..) |f, i| {
        std.debug.print("File[{d}]: {s}\n", .{ i, f });
    }

    var current_logs = try find_current_log(ally, old_logs);
    defer current_logs.deinit(ally);

    try write_logs(ally, io, current_logs, old_logs, cfg);

    var nold_logs = try get_logs(io, ally, cfg, stdout);
    defer {
        for (nold_logs.items) |ol| {
            ally.free(ol);
        }
        nold_logs.deinit(ally);
    }

    for (nold_logs.items, 0..) |f, i| {
        std.debug.print("New old_logs[{d}]: {s}\n", .{ i, f });
    }

    const dPath = try std.fs.path.join(ally, &.{ tmp_path, "dmesg.014" });
    defer ally.free(dPath);
    const aPath = try std.fs.path.join(ally, &.{ tmp_path, "app.log.00A" });
    defer ally.free(aPath);

    _ = try Io.Dir.cwd().statFile(io, dPath, .{});
    _ = try Io.Dir.cwd().statFile(io, aPath, .{});

    dklib.dktest.passed("write_logs");
}

test "write_logs -- rollover" {
    const io = std.testing.io;
    const ally = std.testing.allocator;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var cfg = Config{};
    cfg.debug = true;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;
    const tmp_path = try root.realPathFileAlloc(io, ".", ally);
    defer ally.free(tmp_path);
    cfg.log_dir = tmp_path;

    const subdir = try root.createDirPathOpen(io, "log", .{});
    _ = try subdir.createFile(io, "dmesg", .{});
    subdir.close(io);

    for (0..4095) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(ally, u8, &.{ "dmesg.", &nhex });
        defer ally.free(new_name);
        _ = try subdir.createFile(io, new_name, .{});
    }

    var files = try get_logs(io, ally, cfg, stdout);
    defer {
        for (files.items) |file| {
            ally.free(file);
        }
        files.deinit(ally);
    }

    var current_logs = try find_current_log(ally, files);
    defer current_logs.deinit(ally);

    try write_logs(ally, io, current_logs, files, cfg);

    dklib.dktest.passed("write_logs -- rollover");
}

test "write_logs Manual -- rollover Delete" {
    const io = std.testing.io;
    const ally = std.testing.allocator;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var cfg = Config{};
    cfg.debug = true;
    cfg.rollover_need = true;
    cfg.rollover = RolloverEnum.delete;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;
    const tmp_path = try root.realPathFileAlloc(io, ".", ally);
    defer ally.free(tmp_path);
    cfg.log_dir = tmp_path;

    const subdir = try root.createDirPathOpen(io, "log", .{});
    _ = try subdir.createFile(io, "dmesg", .{});

    for (0..40) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(ally, u8, &.{ "dmesg"[0..], "."[0..], nhex[0..] });
        defer ally.free(new_name);
        _ = try subdir.createFile(io, new_name, .{});
    }

    var files = try get_logs(io, ally, cfg, stdout);
    defer {
        for (files.items) |file| {
            ally.free(file);
        }
        files.deinit(ally);
    }

    var current_logs = try find_current_log(ally, files);
    defer current_logs.deinit(ally);

    try write_logs(ally, io, current_logs, files, cfg);

    dklib.dktest.passed("write_logs custom -- rollover Delete");
}

test "write_logs preserves timestamp" {
    const io = std.testing.io;
    const ally = std.testing.allocator;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var cfg = Config{};
    cfg.debug = true;
    cfg.preserve_timestamps = true;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;
    const tmp_path = try root.realPathFileAlloc(io, ".", ally);
    defer ally.free(tmp_path);
    cfg.log_dir = tmp_path;

    _ = try root.createFile(io, "dmesg", .{});

    // Set a known timestamp
    const times = [_]std.os.linux.timespec{
        .{ .sec = 123456789, .nsec = 0 },
        .{ .sec = 123456789, .nsec = 0 },
    };

    var dir = try Io.Dir.openDirAbsolute(io, cfg.log_dir, .{ .iterate = true });
    defer dir.close(io);

    const rc = std.os.linux.utimensat(dir.handle, "dmesg", &times, 0);
    if (rc != 0) return error.UtimeError;

    var files = try get_logs(io, ally, cfg, stdout);
    defer {
        for (files.items) |file| {
            ally.free(file);
        }
        files.deinit(ally);
    }

    var current_logs = try find_current_log(ally, files);
    defer current_logs.deinit(ally);

    try write_logs(ally, io, current_logs, files, cfg);

    const stat_result = try dir.statFile(io, "dmesg.000", .{});

    // atime is optional
    const atime = stat_result.atime orelse return error.NoAtime;
    try std.testing.expectEqual(@as(i64, 123456789), atime.toSeconds());
    try std.testing.expectEqual(@as(i64, 123456789), stat_result.mtime.toSeconds());

    dklib.dktest.passed("write_logs -- preserves time stamps");
}
