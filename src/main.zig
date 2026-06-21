const std = @import("std");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) void {
    std.process.exit(cli.run(init));
}
