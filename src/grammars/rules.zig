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

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide rule into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S -> A A
    /// Returns "S -> A A"
    pub fn format(self: *const Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s} -> ", .{self.lhs});
        for (self.rhs, 0..) |symbol, i| {
            try writer.print("{s}", .{symbol});
            if (i < self.rhs.len - 1) {
                try writer.print(" ", .{});
            }
        }
    }

    /// Iterate over all rules whose `lhs` matches a given symbol.
    pub const FilterLhsIter = struct {
        iter: *utils.Iter(Rule),

        pub inline fn from(iter: *utils.Iter(Rule)) FilterLhsIter {
            return FilterLhsIter{ .iter = iter };
        }

        pub fn next(self: *FilterLhsIter, filter_symbol: Symbol) ?Rule {
            while (self.iter.next()) |rule| {
                if (rule.lhs.eqlTo(filter_symbol)) return rule;
            }
            return null;
        }
    };

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: Rule) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(key.lhs.name);
            for (key.rhs) |symbol| {
                hasher.update(symbol.name);
            }
            return hasher.final();
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
    const str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{rule});
    defer std.testing.allocator.free(str);
    try std.testing.expectEqualStrings("S -> A A", str);
}

test "lhs_iter" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const a = Symbol.from("a");

    const rules = &.{
        Rule.from(S, &.{ A, a }),
        Rule.from(A, &.{a}),
    };

    var iter = utils.Iter(Rule).from(rules);
    var filter_iter = Rule.FilterLhsIter.from(&iter);
    try std.testing.expectEqual(rules[0], filter_iter.next(S));
    try std.testing.expectEqual(null, filter_iter.next(S));
}

test "rule_hash_map" {
    const rule = Rule.from(Symbol.from("S"), &.{ Symbol.from("A"), Symbol.from("A") });
    var hash_map = Rule.HashMap(void).init(std.testing.allocator);
    defer hash_map.deinit();
    try hash_map.put(rule, {});
    try std.testing.expectEqual(true, hash_map.contains(rule));
}
