const std = @import("std");
const Symbol = @import("symbol.zig").Symbol;
const utils = @import("../utils/iter.zig");

/// Rule stands for a `production rule` in a context-free grammar
///
/// e.g. S -> A a
pub const Rule = struct {
    lhs: Symbol,
    rhs: []const Symbol,

    /// Inline wrapper for rule creation
    pub inline fn from(lhs: Symbol, rhs: []const Symbol) Rule {
        return Rule{
            .lhs = lhs,
            .rhs = rhs,
        };
    }

    /// from const (static) slice to owned slice
    pub fn fromSlice(alloc: std.mem.Allocator, rules: []const Rule) ![]Rule {
        return try alloc.dupe(Rule, rules);
    }

    pub fn last_symbol(self: *const Rule) ?Symbol {
        if (self.rhs.len == 0) {
            return null;
        }
        return self.rhs[self.rhs.len - 1];
    }

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide rule into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S -> A A
    /// Returns "S -> A A"
    pub fn format(self: *const Rule, writer: *std.io.Writer) !void {
        try writer.print("{f} -> ", .{self.lhs});
        for (self.rhs, 0..) |symbol, i| {
            try writer.print("{f}", .{symbol});
            if (i < self.rhs.len - 1) {
                try writer.print(" ", .{});
            }
        }
    }

    pub fn hash(self: *const Rule) u64 {
        var result: u64 = 0;
        result ^= self.lhs.hash();
        for (self.rhs) |symbol| {
            result ^= symbol.hash();
        }
        return result;
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: Rule) u64 {
            return key.hash();
        }

        pub fn eql(hash_context: HashContext, a: Rule, b: Rule) bool {
            return hash_context.hash(a) == hash_context.hash(b);
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.HashMap(Rule, V, HashContext, std.hash_map.default_max_load_percentage);
    }
};

test "rule" {
    const rule = Rule.from(Symbol.from("S"), &.{ Symbol.from("A"), Symbol.from("A") });
    const str = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{rule});
    defer std.testing.allocator.free(str);
    try std.testing.expectEqualStrings("S -> A A", str);
}

test "rule_hash_map" {
    const rule = Rule.from(Symbol.from("S"), &.{ Symbol.from("A"), Symbol.from("A") });
    var hash_map = Rule.HashMap(void).init(std.testing.allocator);
    defer hash_map.deinit();
    try hash_map.put(rule, {});
    try std.testing.expectEqual(true, hash_map.contains(rule));
}
