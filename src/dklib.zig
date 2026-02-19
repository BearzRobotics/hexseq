// SPDX-License-Identifier: GPL-2.0-only
//
// Copyright (C) 2025 Dakota James Owen Keeler
//
// This file is part of dklib.
//
// dklib is free software: you can redistribute it and/or modify
// it under the terms of version 2 of the GNU General Public License
// as published by the Free Software Foundation.
//
// dklib is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const testing = std.testing;

// allow for future growth
pub fn getVersion() [10]u8 {
    const version = "0.0.1";
    return version;
}

pub const dktest = struct {
    // Green
    pub fn passed(msg: []const u8) void {
        std.debug.print("\x1b[32mPASSED:\x1b[0m {s}\n", .{msg});
    }

    // Red
    pub fn failed(msg: []const u8) void {
        std.debug.print("\x1b[31mFAILED:\x1b[0m {s}\n", .{msg});
    }

    // Gray
    pub fn note(msg: []const u8) void {
        std.debug.print("\x1b[90mNOTE:\x1b[0m {s}\n", .{msg});
    }

    //yellow
    pub fn warn(msg: []const u8) void {
        std.debug.print("\x1b[33mWARN:\x1b[0m {s}\n", .{msg});
    }

    // Bold section header
    pub fn section(msg: []const u8) void {
        std.debug.print("\x1b[1m== {s} ==\x1b[0m\n", .{msg});
    }
};

/// Follow the linux sysexit.h where applicable
/// https://man7.org/linux/man-pages/man3/sysexits.h.3head.html
pub const ExitCode = enum(u8) {
    // Standard errors
    ok = 0, // success
    usage = 64, // bad command line usage
    data_err = 65, // data format error
    no_input = 66, // missing input (file, argument)
    no_perm = 77, // permission denied
    config_err = 78, // bad or missing config file
    unavailable = 69, // resource unavailable (lock, device busy)
    temp_fail = 75, // temporary failure, retry possible
    software = 70, // internal software error

    // Custom / Application-specific
    rollover_failed = 80, // log rollover failed
    scan_failed = 81, // directory scanning failed
    fs_write_err = 82, // failed to write file

    // Game / Media / Graphics / Engine-specific
    asset_load_fail = 90, // couldn't load asset (model, texture, etc.)
    scene_parse_error = 91, // scene definition file parse error
    render_fail = 92, // graphics renderer failure
    audio_fail = 93, // audio system failure
    input_fail = 94, // input system failure
    network_fail = 95, // networking failure

    // Fallback
    fatal = 255, // generic fatal error

    pub fn describe(self: ExitCode) []const u8 {
        return switch (self) {
            // Standard
            .ok => "Success",
            .usage => "Bad command line usage",
            .data_err => "Input data format error",
            .no_input => "Missing required input file or argument",
            .no_perm => "Permission denied",
            .config_err => "Configuration error",
            .unavailable => "Resource unavailable",
            .temp_fail => "Temporary failure, retry possible",
            .software => "Internal software error",

            // Custom
            .rollover_failed => "Log rollover failed",
            .scan_failed => "Directory scanning failed",
            .fs_write_err => "Filesystem write error",

            // Game / Engine Specific
            .asset_load_fail => "Failed to load asset",
            .scene_parse_error => "Scene parse error",
            .render_fail => "Renderer initialization failure",
            .audio_fail => "Audio system failure",
            .input_fail => "Input system failure",
            .network_fail => "Network system failure",

            // Fallback
            .fatal => "Fatal error",
        };
    }
};

pub fn exit_with(code: ExitCode) noreturn {
    // Optional: Green for OK, Red for error
    if (code == .ok) {
        //std.debug.print("\x1b[32mPASSED\x1b[0m: {s}\n", .{code.describe()});
    } else {
        std.debug.print("\x1b[31mFAILED\x1b[0m: Code:{d} {s}\n", .{ @intFromEnum(code), code.describe() });
    }
    std.process.exit(@intFromEnum(code));
}
