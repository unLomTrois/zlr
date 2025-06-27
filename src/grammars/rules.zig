const std = @import("std");
const Symbol = @import("symbol.zig").Symbol;

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
    pub const LhsMatchIter = struct {
        rules: []const Rule,
        lhs: Symbol,
        idx: usize = 0,

        pub inline fn from(rules: []const Rule, lhs: Symbol) LhsMatchIter {
            return LhsMatchIter{ .rules = rules, .lhs = lhs, .idx = 0 };
        }

        pub fn next(self: *LhsMatchIter) ?Rule {
            while (self.idx < self.rules.len) {
                const r = self.rules[self.idx];
                self.idx += 1; // advance cursor
                if (r.lhs.eqlTo(self.lhs))
                    return r;
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

    var iter = Rule.LhsMatchIter.from(rules, S);
    try std.testing.expectEqual(rules[0], iter.next());
    try std.testing.expectEqual(null, iter.next());
}

test "rule_hash_map" {
    const rule = Rule.from(Symbol.from("S"), &.{ Symbol.from("A"), Symbol.from("A") });
    var hash_map = Rule.HashMap(void).init(std.testing.allocator);
    defer hash_map.deinit();
    try hash_map.put(rule, {});
    try std.testing.expectEqual(true, hash_map.contains(rule));
}
