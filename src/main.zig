const std = @import("std");
const stdout = std.io.getStdOut().writer();

var debug = false;
const version = "0.0.1";

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
    // we need an allocator
    //const allocator = std.heap.page_allocator;
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

    try std.io.getStdOut().writeAll("No optons supplied. Please run -h for help\n --logdir is required!\n");
    std.process.exit(@intFromEnum(ExitCode.usage));
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
    std.process.exit(@intFromEnum(ExitCode.ok));
}

// Convert dec to hex.
// When I did this in c I created an array of hex[] = "0123456789ABCDEF"
// and used a lookup call to convert the 10-16 to the letter and had to
// do string maninpulation. -- Zig has first class support for hex. So
// I don't want to convert to string until I build the finial file name.
pub fn dec2hex(input: u16) void {
    // initalize are variables and assgin default values.
    var remainder = 0;
    var buffer = [_]u8{0} ** 3; // is an array that is initialized with 3 zeros
    var index: usize = 3;
    while (input != 0) {
        index -= 1;
        remainder = input % 16;
        buffer[index] = remainder;
        input = input / 16;
    }
}

pub fn hex2dec() void {}

pub fn getFiles() void {}

pub fn writeFiles() void {}

// This test is to ensure that the program works as expected
test "simple test" {}
