// SPDX-License-Identifier: GPL-2.0-only
//
// Copyright (C) 2025 Dakota James Owen Keeler
//
// This file is part of hexseq.
//
// hexseq is free software: you can redistribute it and/or modify
// it under the terms of version 2 of the GNU General Public License
// as published by the Free Software Foundation.
//
// hexseq is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const testing = std.testing;

// mine
const dklib = @import("dklib");

// Constants go here
const version = "0.0.8";
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("Memory leak detected!");
    const allocator = gpa.allocator();

    const cfg = try parse_args();

    var old_logs = try get_logs(allocator, cfg);
    defer {
        for (old_logs.items) |f| {
            allocator.free(f);
        }
        old_logs.deinit();
    }

    var current_logs = try find_current_log(allocator, old_logs);
    defer current_logs.deinit();

    try write_logs(allocator, current_logs, old_logs, cfg);
}

fn parse_args() !Config {
    var args = std.process.args();
    defer args.deinit();

    // lets create our Config Struct
    var cfg = Config{};

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                try help();
            } else if (std.mem.eql(u8, arg, "--debug")) {
                cfg.debug = true;
            } else if (std.mem.eql(u8, arg, "--version")) {
                cfg.version = true;
                std.debug.print("hexsql version: {s}\n", .{version});
                dklib.exit_with(dklib.ExitCode.ok);
            } else if (std.mem.eql(u8, arg, "--logdir")) {
                cfg.log_dir = args.next() orelse {
                    try std.io.getStdErr().writeAll("Failed to pass in <path> for --logdir\n");
                    dklib.exit_with(dklib.ExitCode.usage);
                };
                std.debug.print("Arg Parse cfg.log_dir: {s}", .{cfg.log_dir});
                cfg.log_dir_set = true;
            } else if (std.mem.eql(u8, arg, "--rollover=delete")) {
                cfg.rollover = RolloverEnum.delete;
            } else if (std.mem.eql(u8, arg, "--rollover=move")) {
                cfg.rollover = RolloverEnum.move;
                cfg.rollover_target = args.next() orelse {
                    try std.io.getStdErr().writeAll("Failed to pass in <path> for --rollover=move \n");
                    dklib.exit_with(dklib.ExitCode.usage);
                };
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
        try std.io.getStdErr().writeAll("--logdir is required!\n");
        dklib.exit_with(dklib.ExitCode.usage);
    }

    return cfg;
}

fn help() !void {
    try std.io.getStdOut().writeAll("hexseq - hexadecimal log rotator\n\n");
    try std.io.getStdOut().writeAll("Usage: hexseq [options] --logdir <path>\n\n");
    try std.io.getStdOut().writeAll("-h    --help                       Prints help menu\n");
    try std.io.getStdOut().writeAll("-d    --debug                      Enable printing internal debug statements to std::err\n");
    try std.io.getStdOut().writeAll("-v    --version                    Prints the programs version\n");
    try std.io.getStdOut().writeAll("--logdir <path>                    Takes a path to the root of your log dir\n");
    try std.io.getStdOut().writeAll("--rollover=[delete|move] <path>    When you reach .FFF it deletes all old logs and starts fresh at .000\n");
    try std.io.getStdOut().writeAll("                                   Moves all old logs once you reach .FFF to a dir of your choice\n");
    try std.io.getStdOut().writeAll("-p  --preserve                     Perserve timestamps on files\n");
    dklib.exit_with(dklib.ExitCode.ok);
}

fn dec2hex(input: u16) []const u8 {
    var index: usize = 3;
    var value = input;
    var buffer = [_]u8{ '0', '0', '0' };

    while (index > 0) {
        index -= 1;
        buffer[index] = hex[value % 16];
        value = value / 16;
        if (value == 0) break;
    }

    const rt: []const u8 = &buffer;
    return rt;
}

fn get_logs(allocator: std.mem.Allocator, cfg: Config) !std.ArrayList([]const u8) {
    var logs = std.ArrayList([]const u8).init(allocator);

    std.debug.print("cfg.log_dir: {s}\n", .{cfg.log_dir});
    var dir = try std.fs.openDirAbsolute(cfg.log_dir, .{ .iterate = true });

    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        // only grab files
        if (entry.kind == .file) {
            // base + entry.path (relative path.
            const fPath = try std.fs.path.join(allocator, &.{ cfg.log_dir, entry.path });

            // Allocate a duplicate string since walk() gives temporary memory
            // we need to use dupe to keep the data alive past the defer of std.fs.cwd().openDir
            const path_copy = try allocator.dupe(u8, fPath);

            if (cfg.debug == true) {
                std.debug.print("get_logs() - Old logs: {s}\n", .{path_copy});
            }

            try logs.append(path_copy);

            allocator.free(fPath);
        }
    }

    return logs;
}

fn find_current_log(allocator: std.mem.Allocator, old_logs: std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var current_logs = std.ArrayList([]const u8).init(allocator);
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
                try current_logs.append(f);
            }
        } else {
            // no dot = current log file
            try current_logs.append(f);
        }
    }
    return current_logs;
}

fn rollover(allocator: std.mem.Allocator, cfg: Config) !void {
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

        const rpath = try std.fmt.allocPrint(allocator, "{s}.000", .{basePath});
        defer allocator.free(rpath);

        if (cfg.debug == true) {
            std.debug.print("Rollover dir: {s}\n", .{rpath});
        }

        try std.fs.cwd().rename(basePath, rpath);
    } else if (cfg.rollover == RolloverEnum.delete) {
        try std.io.getStdErr().writeAll("Warning setting this flag will just delete the log dir!\n");
        try std.fs.cwd().deleteTree(basePath);
    }
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

// Totally used ChatGPT for this....
fn split_ns_to_timespec(ns: i128) !std.os.linux.timespec {
    const sec = std.math.cast(isize, @divTrunc(ns, 1_000_000_000)) orelse return error.TimeTooLarge;
    const nsec = std.math.cast(isize, @rem(ns, 1_000_000_000)) orelse return error.TimeTooLarge;
    return .{ .sec = sec, .nsec = nsec };
}

fn write_logs(allocator: std.mem.Allocator, cLogs: std.ArrayList([]const u8), old_logs: std.ArrayList([]const u8), cfg: Config) !void {
    if (cfg.preserve_timestamps == true) {
        for (cLogs.items, 0..) |c, i| {
            const count = count_logs(c, old_logs);
            const nhex = dec2hex(count);

            const new_name = try std.mem.concat(allocator, u8, &.{ c, "."[0..], nhex[0..] });
            defer allocator.free(new_name);

            // get time stamp
            const file = try std.fs.cwd().openFile(c, .{});
            const stat = try file.stat();

            if (cfg.debug == true) {
                std.debug.print("New logs to be writtn[{d}]: {s}\n", .{ i, new_name });
            }

            try std.fs.cwd().rename(c, new_name);

            // restore timestamps
            const times = [_]std.os.linux.timespec{
                try split_ns_to_timespec(stat.atime),
                try split_ns_to_timespec(stat.mtime),
            };

            // Totally ChatGPT. -- Need to make sure I understand why this works
            const c_new_name = try allocator.alloc(u8, new_name.len + 1);
            defer allocator.free(c_new_name);

            std.mem.copyForwards(u8, c_new_name[0..new_name.len], new_name);

            c_new_name[new_name.len] = 0; // null terminator
            const c_path = c_new_name[0..new_name.len :0]; // automatically makes it `[*:0]const u8` if you remembered to zero-terminate
            const rc = std.os.linux.utimensat(std.os.linux.AT.FDCWD, c_path, &times, 0);
            if (rc == -1) return std.os.linux.getErrno(rc);

            if (cfg.rollover == RolloverEnum.delete and cfg.rollover_need == false) {
                try rollover(allocator, cfg);
            } else if (count == 4095 and cfg.rollover_need == false) {
                try rollover(allocator, cfg);
            } else if (count == 4095 and cfg.rollover_need == true) {
                try rollover(allocator, cfg);
            }
        }
    } else {
        for (cLogs.items, 0..) |c, i| {
            const count = count_logs(c, old_logs);
            const nhex = dec2hex(count);

            const new_name = try std.mem.concat(allocator, u8, &.{ c, "."[0..], nhex[0..] });
            defer allocator.free(new_name);

            if (cfg.debug == true) {
                std.debug.print("New logs to be writtn[{d}]: {s}\n", .{ i, new_name });
            }

            try std.fs.cwd().rename(c, new_name);

            if (cfg.rollover == RolloverEnum.delete and cfg.rollover_need == false) {
                try rollover(allocator, cfg);
            } else if (count == 4095 and cfg.rollover_need == false) {
                try rollover(allocator, cfg);
            } else if (count == 4095 and cfg.rollover_need == true) {
                try rollover(allocator, cfg);
            }
        }
    }
}

test "dec2hex gives correct 3-digit uppercase hex values" {
    try testing.expectEqualStrings("000", dec2hex(0));
    try testing.expectEqualStrings("00F", dec2hex(15));
    try testing.expectEqualStrings("010", dec2hex(16));
    try testing.expectEqualStrings("2AF", dec2hex(687));
    try testing.expectEqualStrings("3E7", dec2hex(999));
    try testing.expectEqualStrings("FFF", dec2hex(4095));

    dklib.dktest.passed("dec2hex gives correct 3-digit uppercase hex values");
}

test "get_logs pickup old_logs in test dir" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = tmp.dir;

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    _ = try root.createFile("dmesg", .{});
    _ = try root.createFile("dmesg.000", .{});

    const subdir = try root.makeOpenPath("tlog", .{});
    _ = try subdir.createFile("app.log", .{});
    _ = try subdir.createFile("app.log.001", .{});
    _ = try subdir.createFile("app.log.0F7", .{});

    const subdir2 = try root.makeOpenPath("log", .{});
    _ = try subdir2.createFile("bearz.log", .{});
    _ = try subdir2.createFile("bearz.log.001", .{});
    _ = try subdir2.createFile("bearz.log.002", .{});

    var cfg = Config{};
    cfg.log_dir = tmp_path;

    var old_logs = try get_logs(allocator, cfg);
    defer {
        for (old_logs.items) |f| {
            allocator.free(f);
        }
        old_logs.deinit();
    }

    // debugging print
    for (old_logs.items, 0..) |f, i| {
        std.debug.print("old_logs[{d}]: {s}\n", .{ i, f });
    }

    try testing.expect(old_logs.items.len == 8); // adjust to your count -- // 1 based not 0
    dklib.dktest.passed("get_logs maked a ArrayList of old_logs in test dir");
}

test "find_current_log" {
    const allocator = std.testing.allocator;

    // Create an array list of old_logs to pass into
    // find current log
    var old_logs = std.ArrayList([]const u8).init(allocator);
    defer old_logs.deinit();
    _ = try old_logs.append("/home/test/log/dmesg");
    _ = try old_logs.append("/home/test/log/dmesg.001");
    _ = try old_logs.append("/home/test/log/app.log.001");
    _ = try old_logs.append("/home/test/log/dmesg.002");
    _ = try old_logs.append("/home/test/log/app.log.000");
    _ = try old_logs.append("/home/test/log/dmesg.000");
    _ = try old_logs.append("/home/test/log/app.log.002");
    _ = try old_logs.append("/home/test/log/app.log");

    const cLog = try find_current_log(allocator, old_logs);
    defer cLog.deinit();

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
    const allocator = std.testing.allocator;

    // Create an array list of old_logs to pass into
    // find current log
    var old_logs = std.ArrayList([]const u8).init(allocator);
    defer old_logs.deinit();
    _ = try old_logs.append("/home/test/log/dmesg");
    _ = try old_logs.append("/home/test/log/dmesg.001");
    _ = try old_logs.append("/home/test/log/app.log.001");
    _ = try old_logs.append("/home/test/log/dmesg.002");
    _ = try old_logs.append("/home/test/log/app.log.000");
    _ = try old_logs.append("/home/test/log/dmesg.000");
    _ = try old_logs.append("/home/test/log/app.log.002");
    _ = try old_logs.append("/home/test/log/app.log.003");
    _ = try old_logs.append("/home/test/log/app.log");

    const count = count_logs("/home/test/log/dmesg", old_logs);
    std.debug.print("Number of old dmesg logs: {d}\n", .{count});

    const count2 = count_logs("/home/test/log/app.log", old_logs);
    std.debug.print("Number of old app.log logs: {d}\n", .{count2});

    try std.testing.expectEqual(3, count);
    try std.testing.expectEqual(4, count2);

    dklib.dktest.passed("Count_logs");
}

test "write_logs" {
    // Obvioiusly I'm going to have to create a temp directory and then run
    // through the whole program in this one test.
    const allocator = std.testing.allocator;
    var cfg = Config{};

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    //std.debug.print("The absolute temp dir is: {s}\n", .{tmp_path});

    // create some base files
    _ = try tmp.dir.createFile("dmesg", .{});
    _ = try tmp.dir.createFile("app.log", .{});

    for (0..20) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(allocator, u8, &.{ "dmesg"[0..], "."[0..], nhex[0..] });

        defer allocator.free(new_name);
        _ = try tmp.dir.createFile(new_name, .{});
    }

    for (0..10) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(allocator, u8, &.{ "app.log"[0..], "."[0..], nhex[0..] });

        defer allocator.free(new_name);
        _ = try tmp.dir.createFile(new_name, .{});
    }

    var tmp_logs = std.ArrayList([]const u8).init(allocator);
    defer {
        for (tmp_logs.items) |file| {
            allocator.free(file);
        }
        tmp_logs.deinit();
    }

    cfg.log_dir = tmp_path;
    const old_logs = try get_logs(allocator, cfg);
    defer {
        for (old_logs.items) |o| {
            allocator.free(o);
        }
        old_logs.deinit();
    }

    for (old_logs.items, 0..) |f, i| {
        std.debug.print("File[{d}]: {s}\n", .{ i, f });
    }

    const current_logs = try find_current_log(allocator, old_logs);
    defer current_logs.deinit();

    try write_logs(allocator, current_logs, old_logs, cfg);

    const nold_logs = try get_logs(allocator, cfg);
    defer {
        for (nold_logs.items) |ol| {
            allocator.free(ol);
        }
        nold_logs.deinit();
    }
    for (nold_logs.items, 0..) |f, i| {
        std.debug.print("New old_logs[{d}]: {s}\n", .{ i, f });
    }

    const dPath = try std.fs.path.join(allocator, &.{ tmp_path, "dmesg.014" });
    const aPath = try std.fs.path.join(allocator, &.{ tmp_path, "app.log.00A" });

    try tmp.dir.access(dPath, .{});
    try tmp.dir.access(aPath, .{});

    allocator.free(dPath);
    allocator.free(aPath);
    dklib.dktest.passed("write_logs");
}

test "write_logs -- rollover" {
    // Obvioiusly I'm going to have to create a temp directory and then run
    // through the whole program in this one test.

    var cfg = Config{};
    cfg.debug = true;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    //std.debug.print("The absolute temp dir is: {s}\n", .{tmp_path});
    cfg.log_dir = tmp_path;

    const root = tmp.dir;

    const subdir = try root.makeOpenPath("log", .{});

    // create some base files
    _ = try subdir.createFile("dmesg", .{});

    for (0..4095) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(allocator, u8, &.{ "dmesg"[0..], "."[0..], nhex[0..] });

        defer allocator.free(new_name);
        _ = try subdir.createFile(new_name, .{});
    }

    var files = try get_logs(allocator, cfg);
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    const current_logs = try find_current_log(allocator, files);
    defer current_logs.deinit();

    try write_logs(allocator, current_logs, files, cfg);

    dklib.dktest.passed("write_logs -- rollover");
}

test "write_logs Manual -- rollover Delete" {
    // Obvioiusly I'm going to have to create a temp directory and then run
    // through the whole program in this one test.
    var cfg = Config{};

    cfg.debug = true;
    cfg.rollover_need = true;
    cfg.rollover = RolloverEnum.delete;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    //std.debug.print("The absolute temp dir is: {s}\n", .{tmp_path});
    cfg.log_dir = tmp_path;

    const root = tmp.dir;

    const subdir = try root.makeOpenPath("log", .{});

    // create some base files
    _ = try subdir.createFile("dmesg", .{});

    for (0..40) |i| {
        const nhex = dec2hex(@as(u16, @intCast(i)));
        const new_name = try std.mem.concat(allocator, u8, &.{ "dmesg"[0..], "."[0..], nhex[0..] });

        defer allocator.free(new_name);
        _ = try subdir.createFile(new_name, .{});
    }

    var files = try get_logs(allocator, cfg);
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    const current_logs = try find_current_log(allocator, files);
    defer current_logs.deinit();

    try write_logs(allocator, current_logs, files, cfg);

    dklib.dktest.passed("write_logs custom -- rollover Delete");
}

test "write_logs preserves timestamp" {
    // Obvioiusly I'm going to have to create a temp directory and then run
    // through the whole program in this one test.
    var cfg = Config{};

    cfg.debug = true;
    cfg.rollover_need = true;
    cfg.rollover = RolloverEnum.delete;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    //std.debug.print("The absolute temp dir is: {s}\n", .{tmp_path});
    cfg.log_dir = tmp_path;

    const root = tmp.dir;

    // create some base files
    _ = try root.createFile("dmesg", .{});

    // Set a known timestamp (e.g., 123456789 sec, 0 nsec)
    const times = [_]std.os.linux.timespec{
        .{ .sec = 123456789, .nsec = 0 },
        .{ .sec = 123456789, .nsec = 0 },
    };

    var dir = try std.fs.openDirAbsolute(cfg.log_dir, .{ .iterate = true });
    defer dir.close();
    const rc = std.os.linux.utimensat(dir.fd, "dmesg", &times, 0);
    if (rc < 0) return std.os.linux.errno(rc).raise();

    var files = try get_logs(allocator, cfg);
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    const current_logs = try find_current_log(allocator, files);
    defer current_logs.deinit();

    try write_logs(allocator, current_logs, files, cfg);

    // Check timestamp after rename
    var statbuf: std.os.linux.Stat = undefined;
    const rc2 = std.os.linux.fstatat(dir.fd, "dmesg.000", &statbuf, 0);
    if (rc2 < 0) return std.os.linux.errno(rc).raise();

    // Check atime and mtime (should be in nanoseconds)
    try std.testing.expectEqual(@as(isize, 123456789), statbuf.atim.sec);
    try std.testing.expectEqual(@as(isize, 0), statbuf.atim.nsec);
    try std.testing.expectEqual(@as(isize, 123456789), statbuf.mtim.sec);
    try std.testing.expectEqual(@as(isize, 0), statbuf.mtim.nsec);

    dklib.dktest.passed("write_logs -- preserves time stamps");
}
