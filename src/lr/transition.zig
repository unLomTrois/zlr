const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

pub const Transition = struct {
    from: usize,
    to: usize,
    symbol: Symbol,

    pub fn format(self: *const Transition, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("goto({any}, '{any}')", .{ self.to, self.symbol });
    }
};
