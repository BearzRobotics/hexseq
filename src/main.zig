const std = @import("std");
const testing = std.testing;
const stdout = std.io.getStdOut().writer();

var debug = false;
const version = "0.0.1";
const hex = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

/// Follow the linux sysexit.h where applicable
/// https://man7.org/linux/man-pages/man3/sysexits.h.3head.html
const ExitCode = enum(u8) {
    ok = 0, // EX_OK — success
    usage = 64, // EX_USAGE — bad command line
    data_err = 65, // EX_DATAERR — input data error
    no_input = 66, // EX_NOINPUT — missing log file/dir
    no_perm = 77, // EX_NOPERM — permission denied
    config_err = 78, // EX_CONFIG — bad or missing config file
    unavailable = 69, // EX_UNAVAILABLE — e.g., cannot lock file or resource
    temp_fail = 75, // EX_TEMPFAIL — retryable error (e.g., filesystem busy)
    software = 70, // EX_SOFTWARE — internal logic error (panic)

    // Optional custom ones (safe range: 80–99)
    rollover_failed = 80, // custom: couldn't move or delete .000–.FFF
    scan_failed = 81, // custom: directory walk failed
    fs_write_err = 82, // custom: couldn't write index or update state
};

pub fn main() !void {
    // we need an allocator for our dynamic array of files.
    // From reading on different sites and docs this allocator can be swapped out.
    // so If I decied to change from gpa to something else, I merely need to update
    // what the allocator variable is pointing to.
    // https://zig.guide/standard-library/allocators/
    // https://ziglang.org/documentation/0.14.0/std/#std.process.ArgIteratorGeneral
    //const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // we setup gpa to panic on memery leaks.
    //defer if (gpa.deinit() != .ok) @panic("memory leak detected");
    // We need to make are gpa usable when passing an allocator to we create a const and pass reference to our gpa
    //const allocator = &gpa.allocator;

    var args = std.process.args();
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
        } else if (std.mem.eql(u8, arg, "--logdir")) {
            try stdout.print("hexseq version: {s}\n", .{version});
        } else if (std.mem.eql(u8, arg, "--rollover=delete")) {
            try stdout.print("hexseq version: {s}\n", .{version});
        } else if (std.mem.eql(u8, arg, "--rollover=move")) {
            try stdout.print("hexseq version: {s}\n", .{version});
            std.process.exit(@intFromEnum(ExitCode.ok));
        }
    }

    // we we get the recursive function working delete this code and it's function
    //try listDir("/home/dakota");

    try std.io.getStdOut().writeAll("No optons supplied. Please run -h for help\n --logdir is required!\n");
    std.process.exit(@intFromEnum(ExitCode.usage));
}

// https://www.reddit.com/r/Zig/comments/17zy769/just_an_example_of_listing_directory_contents/
// https://gist.github.com/neeraj9/77b29dadaf5a4be5b81775532e3f23b6
// https://ziglang.org/documentation/0.14.0/std/#std.fs.Dir.openDir
//pub fn listDir(path: []const u8) !void {
//    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
//    defer dir.close();
//    var dirIterator = dir.iterate();
//    while (try dirIterator.next()) |dirContent| {
//        std.debug.print("{s}\n", .{dirContent.name});
//    }
//}

pub fn help() !void {
    try std.io.getStdOut().writeAll("hexseq - hexadecimal log rotator\n\n");
    try std.io.getStdOut().writeAll("Usage: hexseq [options]\n\n");
    try std.io.getStdOut().writeAll("-h    --help              Prints help menu\n");
    try std.io.getStdOut().writeAll("-d    --debug             Enable printing internal debug statements to std::err\n");
    try std.io.getStdOut().writeAll("-v    --version           Prints the programs version\n");
    try std.io.getStdOut().writeAll("--logdir <path>           Takes a path to the root of your log dir\n");
    try std.io.getStdOut().writeAll("--rollover=delete         When you reach .FFF it deletes all old logs and starts fresh at .000\n");
    try std.io.getStdOut().writeAll("--rollover=move <path>    Moves all old logs once you reach .FFF to a dir of your choice\n");
    std.process.exit(@intFromEnum(ExitCode.ok));
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
pub fn hex2dec(input: [3]u8) u16 {
    var output = 0;

    // we know 16^2 is the higest number we'll be dealing with
    // were going to built this backwards
    // (0 x 16^2) + (1 * 16^1) + (2 * 16^0)
    // in is a [3]u8 -- digit is it's value. i always start @ 0 and counts up.
    for (input, 0..) |digit, i| {
        const power = 2 - @as(u32, i);
        output += @as(u16, digit) * std.math.pow(u16, 16, power);
    }
    return output;
}

pub fn getFiles() void {}

pub fn writeFiles() void {}

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

}
