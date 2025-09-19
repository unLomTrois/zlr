const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

pub const Transition = struct {
    from: usize,
    to: usize,
    symbol: Symbol,

    pub fn format(self: *const Transition, writer: *std.io.Writer) !void {
        try writer.print("goto({d}, '{f}')", .{ self.to, self.symbol });
    }
};
