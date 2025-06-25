const std = @import("std");

pub const grammar = @import("grammars/grammar.zig");
pub const lr = @import("lr/automaton.zig");

test "root tests" {
    std.testing.refAllDecls(@This());
}
