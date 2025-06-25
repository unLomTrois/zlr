//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const grammar = @import("grammars/grammar.zig");
pub const lr = @import("lr/automaton.zig");

comptime {
    _ = @import("root_tests.zig");
}
