const std = @import("std");
const nbimg = @import("nbimg");

pub fn main(init: std.process.Init) void {
    std.process.exit(nbimg.cli.run(init));
}
