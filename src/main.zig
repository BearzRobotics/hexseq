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
const stdout = std.io.getStdOut().writer();

// mine
const dklib = @import("dklib");

//3rd party

var debug = false;
const version = "0.0.2";
const hex = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

pub fn main() !void {
    // we need an allocator for our dynamic array of files.
    // From reading on different sites and docs this allocator can be swapped out.
    // so If I decied to change from gpa to something else, I merely need to update
    // what the allocator variable is pointing to.
    // https://zig.guide/standard-library/allocators/
    // https://ziglang.org/documentation/0.14.0/std/#std.process.ArgIteratorGeneral
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // we setup gpa to panic on memery leaks.
    defer if (gpa.deinit() != .ok) @panic("memory leak detected");
    // We need to make are gpa usable when passing an allocator to we create a const and pass reference to our gpa
    const allocator = gpa.allocator();

    // ArrayList themselves are not iterable. --
    // Only slices, arrays, tuples, and vectors are iterable directly with for
    var files = std.ArrayList([]const u8).init(allocator);

    // manually duplicating strings into the heap. These won't be automatically freed when files.deinit() is called —
    // I have to free each string myself, like this, but only when .dupe() is used:
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    var args = std.process.args();
    defer args.deinit();

    // make sure the args are present
    if (args.next() == null) {
        try std.io.getStdOut().writeAll("No optons supplied. Please run -h for help\n --logdir is required!\n");
        dklib.exit_with(dklib.ExitCode.usage);
    }

    while (args.next()) |arg| {
        // unlike in other languages where you can compare the arg to a string
        // in zig we are not allowed to do that
        // e.g arg == "-d" does not work.
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            debug = true;
            // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
            std.debug.print("debug value set to: {}\n", .{debug});
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try help();
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            try stdout.print("hexseq version: {s}\n", .{version});
            dklib.exit_with(dklib.ExitCode.ok);
        } else if (std.mem.eql(u8, arg, "--logdir")) {
            const logdir = args.next() orelse {
                try std.io.getStdErr().writeAll("Missing path after --logdir \n");
                dklib.exit_with(dklib.ExitCode.usage);
            };
            try getLogs(allocator, logdir, &files);
            if (debug == true) {
                for (files.items, 0..) |f, i| {
                    std.debug.print("File[{d}]: {s}\n", .{ i, f });
                }
            }

            const currentLogs = try findCurrentLog(allocator, &files);
            // must use try and get rid of the err union, before this works
            // If you free this in the findCurrentLog() you'll get a double free error.
            defer currentLogs.deinit();
            if (debug == true) {
                for (currentLogs.items, 0..) |f, i| {
                    std.debug.print("currentlogs[{d}]: {s}\n", .{ i, f });
                }
            }

            try writeLogs(allocator, currentLogs, files);
        } else if (std.mem.eql(u8, arg, "--rollover=delete")) {
            try stdout.print("hexseq version: {s}\n", .{version});
        } else if (std.mem.eql(u8, arg, "--rollover=move")) {
            try stdout.print("hexseq version: {s}\n", .{version});
            dklib.exit_with(dklib.ExitCode.ok);
        }
    }
}

pub fn help() !void {
    try std.io.getStdOut().writeAll("hexseq - hexadecimal log rotator\n\n");
    try std.io.getStdOut().writeAll("Usage: hexseq [options]\n\n");
    try std.io.getStdOut().writeAll("-h    --help              Prints help menu\n");
    try std.io.getStdOut().writeAll("-d    --debug             Enable printing internal debug statements to std::err\n");
    try std.io.getStdOut().writeAll("-v    --version           Prints the programs version\n");
    try std.io.getStdOut().writeAll("--logdir <path>           Takes a path to the root of your log dir\n");
    try std.io.getStdOut().writeAll("--rollover=delete         When you reach .FFF it deletes all old logs and starts fresh at .000\n");
    try std.io.getStdOut().writeAll("--rollover=move <path>    Moves all old logs once you reach .FFF to a dir of your choice\n");
    dklib.exit_with(dklib.ExitCode.ok);
}

pub fn rollOver() !void {
    std.io.getStdErr().writeAll("roll over functionality not implemented yet!\n");
}

// Convert dec to hex.
// When I did this in c I created an array of hex[] = "0123456789ABCDEF"
// and used a lookup call to convert the 10-16 to the letter and had to
// do string maninpulation. -- Zig has first class support for hex. So
// I don't want to convert to string until I build the finial file name.
pub fn dec2hex(input: u16) [3]u8 {
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

// we need to multiply starting from the least significant digit
// (right) each number by an increasing power of 16. e.g. DA145
// (5 * 16^0) + (4 * 16^1) + (1 * 16^2) + (10 * 16^3) + (13 * 16^4)
pub fn hex2dec(input: []const u8) u16 {
    var output: u16 = 0; // by default a zero is comptime value. -- must have a definate type to be modifyed at runtime
    var buf = [_]u8{ '0', '0', '0' };

    // first we need to convert the hex array to actual digits
    for (input, 0..) |char, j| {
        for (hex, 0..) |h, i| {
            if (char == h) {
                buf[j] = @as(u8, @intCast(i));
            }
        }
    }

    // we know 16^2 is the higest number we'll be dealing with
    // were going to built this backwards
    // (0 x 16^2) + (1 * 16^1) + (2 * 16^0)
    // in is a [3]u8 -- digit is it's value. i always start @ 0 and counts up.
    for (buf, 0..) |digit, i| {
        const power = 2 - @as(u16, @intCast(i));
        output += @as(u16, digit) * std.math.pow(u16, 16, power);
    }
    return output;
}

pub fn getLogs(allocator: std.mem.Allocator, base: []const u8, files: *std.ArrayList([]const u8)) !void {
    var dir = try std.fs.cwd().openDir(base, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        // only grab files
        if (entry.kind == .file) {
            // base + entry.path (relative path.
            const fPath = try std.fs.path.join(allocator, &.{ base, entry.path });

            // Allocate a duplicate string since walk() gives temporary memory
            // we need to use dupe to keep the data alive past the defer of std.fs.cwd().openDir
            const path_copy = try allocator.dupe(u8, fPath);
            try files.append(path_copy);

            allocator.free(fPath);
        }
    }
}

// find current file
pub fn findCurrentLog(allocator: std.mem.Allocator, files: *std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var currentLogs = std.ArrayList([]const u8).init(allocator);
    // because we are returning this the defer should be where the function is called.

    for (files.items) |f| {
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
                try currentLogs.append(f);
            }
        } else {
            // no dot = current log file
            try currentLogs.append(f);
        }
    }
    return currentLogs;
}

pub fn countLogs(currentLogs: []const u8, files: std.ArrayList([]const u8)) u16 {
    var oLC: u16 = 0;

    for (files.items) |f| {
        if (std.mem.lastIndexOf(u8, f, ".")) |dot_index| {
            const suffix = f[dot_index + 1 ..];
            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]) and
                std.mem.eql(u8, currentLogs, f[0..dot_index]))
            {
                oLC += 1;
            }
        }
    }

    return oLC;
}

// The last function called to write all new files
pub fn writeLogs(allocator: std.mem.Allocator, cLogs: std.ArrayList([]const u8), files: std.ArrayList([]const u8)) !void {
    for (cLogs.items) |c| {
        const count = countLogs(c, files);
        const nhex = dec2hex(count);

        // More zig appropriate way to build new strings
        const new_name = try std.mem.concat(allocator, u8, &.{ c, "."[0..], nhex[0..] });
        // free temporary string
        defer allocator.free(new_name);

        if (debug == true) {
            std.debug.print("New files to be writtn: {s}\n", .{new_name});
        }

        try std.fs.cwd().rename(c, new_name);
        // requires c style strings.
        //std.os.linux.rename(c, new_name);

    }
}

// This test pics random decimal values and makes sure that the correct
// hex value is being returned.
test "dec2hex gives correct 3-digit uppercase hex values" {
    try testing.expectEqualStrings("000", &dec2hex(0));
    try testing.expectEqualStrings("00F", &dec2hex(15));
    try testing.expectEqualStrings("010", &dec2hex(16));
    try testing.expectEqualStrings("2AF", &dec2hex(687));
    try testing.expectEqualStrings("3E7", &dec2hex(999));
    try testing.expectEqualStrings("FFF", &dec2hex(4095));

    // This test replaced this block of code.
    // https://ziggit.dev/t/for-loop-counter-other-than-usize/4744/2
    //
    //     +- Range doesn't include end number by defualt. last one processed is 99.
    //     |        +- For loops only interate over usize. -- No other data types
    //     |        |            +- We saying to convert to u16 with a builtin
    //for (0..100) |i| {         |
    //    const hex1 = dec2hex(@as(u16, @intCast(i))); --| Because usize (64 bit int on my system)
    //    try stdout.print("hex value {s}\n", .{&hex1}); | couldn't map to all possible values of a u16
    //}                                                  | we must tell the compiler that it is safe to cast down.

    dklib.dktest.passed("dec2hex gives correct 3-digit uppercase hex values");
}

test "hex2dec right u16 output" {
    try testing.expectEqual(0, hex2dec("000"));
    try testing.expectEqual(15, hex2dec("00F"));
    try testing.expectEqual(16, hex2dec("010"));
    try testing.expectEqual(687, hex2dec("2AF"));
    try testing.expectEqual(999, hex2dec("3E7"));
    try testing.expectEqual(4095, hex2dec("FFF"));
    try testing.expectEqual(1, hex2dec("001"));
    try testing.expectEqual(255, hex2dec("0FF"));
    try testing.expectEqual(409, hex2dec("199"));
    try testing.expectEqual(2748, hex2dec("ABC"));

    // This test replaced this block of code.
    // https://ziggit.dev/t/for-loop-counter-other-than-usize/4744/2
    //
    //     +- Range doesn't include end number by defualt. last one processed is 99.
    //     |        +- For loops only interate over usize. -- No other data types
    //     |        |            +- We saying to convert to u16 with a builtin
    //for (0..100) |i| {         |
    //    const hex1 = dec2hex(@as(u16, @intCast(i))); --| Because usize (64 bit int on my system)
    //    try stdout.print("hex value {s}\n", .{&hex1}); | couldn't map to all possible values of a u16
    //}                                                  | we must tell the compiler that it is safe to cast down.

    dklib.dktest.passed("hex2dec right u16 output");
}

test "getLogs pickup files in test dir" {
    // Get the allocator
    const allocator = std.testing.allocator;

    // create a temp dir for testing
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // If you want to make the temp dir persistance
    //const tmp = std.testing.tmpDir(.{});

    const root = tmp.dir;

    // get the path of our temp dir
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    //std.debug.print("The absolute temp dir is: {s}\n", .{tmp_path});
    defer allocator.free(tmp_path);

    // every expresssion that returns a value must be used. -- I don't care
    // bout the return value here so i'm telling the compiler with _ = to discard it
    _ = try root.createFile("dmesg", .{});
    _ = try root.createFile("dmesg.000", .{});

    // create subdir and files
    const subdir = try root.makeOpenPath("tlog", .{});
    _ = try subdir.createFile("app.log", .{});
    _ = try subdir.createFile("app.log.001", .{});
    _ = try subdir.createFile("app.log.0F7", .{});

    const subdir2 = try root.makeOpenPath("log", .{});
    _ = try subdir2.createFile("bearz.log", .{});
    _ = try subdir2.createFile("bearz.log.001", .{});
    _ = try subdir2.createFile("bearz.log.002", .{});

    // know lets build an array of them.
    var files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    // lets run the files
    try getLogs(allocator, tmp_path, &files);

    // debugging print
    for (files.items, 0..) |f, i| {
        std.debug.print("Files[{d}]: {s}\n", .{ i, f });
    }

    try testing.expect(files.items.len == 8); // adjust to your count -- // 1 based not 0
    dklib.dktest.passed("getLogs pickup files in test dir");
}

test "findCurrentLog" {
    const allocator = std.testing.allocator;

    // Create an array list of files to pass into
    // find current log
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();
    _ = try files.append("/home/test/log/dmesg");
    _ = try files.append("/home/test/log/dmesg.001");
    _ = try files.append("/home/test/log/app.log.001");
    _ = try files.append("/home/test/log/dmesg.002");
    _ = try files.append("/home/test/log/app.log.000");
    _ = try files.append("/home/test/log/dmesg.000");
    _ = try files.append("/home/test/log/app.log.002");
    _ = try files.append("/home/test/log/app.log");

    const cLog = try findCurrentLog(allocator, &files);
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

    dklib.dktest.passed("findCurrentLogs");
}

test "countLogs" {
    const allocator = std.testing.allocator;

    // Create an array list of files to pass into
    // find current log
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();
    _ = try files.append("/home/test/log/dmesg");
    _ = try files.append("/home/test/log/dmesg.001");
    _ = try files.append("/home/test/log/app.log.001");
    _ = try files.append("/home/test/log/dmesg.002");
    _ = try files.append("/home/test/log/app.log.000");
    _ = try files.append("/home/test/log/dmesg.000");
    _ = try files.append("/home/test/log/app.log.002");
    _ = try files.append("/home/test/log/app.log.003");
    _ = try files.append("/home/test/log/app.log");

    const count = countLogs("/home/test/log/dmesg", files);
    std.debug.print("Number of old dmesg logs: {d}\n", .{count});

    const count2 = countLogs("/home/test/log/app.log", files);
    std.debug.print("Number of old app.log logs: {d}\n", .{count2});

    try std.testing.expectEqual(3, count);
    try std.testing.expectEqual(4, count2);

    dklib.dktest.passed("CountLogs");
}

test "writeLogs" {
    // Obvioiusly I'm going to have to create a temp directory and then run
    // through the whole program in this one test.

    const allocator = std.testing.allocator;

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

    var files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit();
    }

    try getLogs(allocator, tmp_path, &files);
    for (files.items, 0..) |f, i| {
        std.debug.print("File[{d}]: {s}\n", .{ i, f });
    }

    const currentLogs = try findCurrentLog(allocator, &files);
    defer currentLogs.deinit();

    try writeLogs(allocator, currentLogs, files);

    var nfiles = std.ArrayList([]const u8).init(allocator);
    defer {
        for (nfiles.items) |file| {
            allocator.free(file);
        }
        nfiles.deinit();
    }

    try getLogs(allocator, tmp_path, &nfiles);
    for (nfiles.items, 0..) |f, i| {
        std.debug.print("New Files[{d}]: {s}\n", .{ i, f });
    }

    const dPath = try std.fs.path.join(allocator, &.{ tmp_path, "dmesg.014" });
    const aPath = try std.fs.path.join(allocator, &.{ tmp_path, "app.log.00A" });

    try tmp.dir.access(dPath, .{});
    try tmp.dir.access(aPath, .{});

    allocator.free(dPath);
    allocator.free(aPath);
    dklib.dktest.passed("writeLogs");
}
