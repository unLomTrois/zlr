const std = @import("std");

const grammars = @import("../grammars/grammar.zig");

const Symbol = grammars.Symbol;
const Rule = grammars.Rule;

/// Item represents an LR parsing item.
/// It is a production rule with a dot position.
/// The dot position indicates the position of the next symbol to be parsed.
/// The dot position is 0 for the first symbol of the production rule.
pub const Item = struct {
    rule: Rule,
    dot_pos: usize,

    pub fn from(rule: Rule) Item {
        return Item{
            .rule = rule,
            .dot_pos = 0,
        };
    }

    pub inline fn fromInline(rule: Rule) Item {
        return Item{
            .rule = rule,
            .dot_pos = 0,
        };
    }

    /// The item is complete if the dot is at the end of the rule
    ///
    /// e.g. S -> A B •
    pub fn is_complete(self: Item) bool {
        return self.dot_pos >= self.rule.rhs.len;
    }

    /// The dot symbol is the symbol after the dot.
    ///
    /// e.g. in "S -> A • B", the dot symbol is B
    pub fn dot_symbol(self: *const Item) ?Symbol {
        if (self.is_complete()) {
            return null;
        }

        return self.rule.rhs[self.dot_pos];
    }

    pub fn advance_dot_clone(self: *const Item) Item {
        return Item{
            .rule = self.rule,
            .dot_pos = self.dot_pos + 1,
        };
    }

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide item into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S -> A B •
    /// Returns "S -> A B •"
    pub fn format(self: *const Item, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s} ->", .{self.rule.lhs.name});

        for (self.rule.rhs, 0..) |sym, i| {
            if (i == self.dot_pos) {
                try writer.print(" •", .{});
            }
            try writer.print(" {s}", .{sym.name});
        }

        if (self.is_complete()) {
            try writer.print(" •", .{});
        }
    }

    /// Iterate over the *incomplete* items stored in a mutable `ArrayList`.
    /// Because we keep a pointer to the list, items appended during the walk are
    /// picked up automatically – perfect for the work-list pattern.
    pub const IncompleteIter = struct {
        list: *std.ArrayList(Item),
        idx: usize = 0,

        pub inline fn from(list: *std.ArrayList(Item)) IncompleteIter {
            return IncompleteIter{ .list = list, .idx = 0 };
        }

        pub fn next(self: *IncompleteIter) ?Item {
            while (self.idx < self.list.items.len) {
                const item = self.list.items[self.idx];
                self.idx += 1;
                if (!item.is_complete()) return item;
            }
            return null;
        }
    };

    /// Searches items that have the same dot symbol as the given symbol.
    pub const FilterDotSymbolIter = struct {
        items: []const Item,
        symbol: Symbol,
        idx: usize = 0,

        pub inline fn from(items: []const Item, symbol: Symbol) FilterDotSymbolIter {
            return FilterDotSymbolIter{ .items = items, .symbol = symbol, .idx = 0 };
        }

        pub fn next(self: *FilterDotSymbolIter) ?Item {
            while (self.idx < self.items.len) {
                const item = self.items[self.idx];
                self.idx += 1;
                const symbol = item.dot_symbol() orelse continue;
                if (symbol.eqlTo(self.symbol)) return item;
            }
            return null;
        }
    };

    pub const UniqueIter = struct {
        items: []const Item,
        idx: usize = 0,
        array_hash_map: Symbol.ArrayHashMap(void),

        pub fn init(allocator: std.mem.Allocator, items: []const Item) UniqueIter {
            return UniqueIter{
                .items = items,
                .idx = 0,
                .array_hash_map = Symbol.ArrayHashMap(void).init(allocator),
            };
        }

        pub fn deinit(self: *UniqueIter) void {
            self.array_hash_map.deinit();
        }

        pub fn next(self: *UniqueIter) !?Item {
            while (self.idx < self.items.len) {
                const item = self.items[self.idx];
                self.idx += 1;
                const symbol = item.dot_symbol() orelse continue;
                if (!self.array_hash_map.contains(symbol)) {
                    try self.array_hash_map.put(symbol, {});

                    return item;
                }
            }
            return null;
        }
    };

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: Item) u64 {
            const rule_hash = (Rule.HashContext{}).hash(key.rule);
            return rule_hash ^ @as(u64, key.dot_pos);
        }

        pub fn eql(hash_context: HashContext, a: Item, b: Item) bool {
            return hash_context.hash(a) == hash_context.hash(b);
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.HashMap(Item, V, HashContext, std.hash_map.default_max_load_percentage);
    }
};

test "dot_symbol" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    // S -> A B
    const rule = Rule.from(S, &[_]Symbol{ A, B });
    const item = Item.from(rule);

    try std.testing.expectEqual(item.dot_symbol(), A);
    // try std.testing.expectEqual(item.dot_symbol(), B);
    // try std.testing.expectEqual(item.dot_symbol(), null);
}

test "item_format" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    // S -> A B
    const rule = Rule.from(S, &[_]Symbol{ A, B });
    var item = Item.from(rule);

    const cases = [_][]const u8{ "S -> • A B", "S -> A • B", "S -> A B •" };

    const allocator = std.testing.allocator;
    for (cases) |case| {
        const str = try std.fmt.allocPrint(allocator, "{s}", .{item});
        defer allocator.free(str);
        defer item.dot_pos += 1;
        try std.testing.expectEqualStrings(case, str);
    }
}

test "unique_iter" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    // S -> A B
    const rule = Rule.from(S, &[_]Symbol{ A, B });
    const item = Item.from(rule);

    const item2 = item.advance_dot_clone();

    const items = &[_]Item{ item, item2 };

    var unique_iter = Item.UniqueIter.init(std.testing.allocator, items);
    defer unique_iter.deinit();

    try std.testing.expectEqual(item, try unique_iter.next()); // S -> • A B
    try std.testing.expectEqual(item2, try unique_iter.next()); // S -> A • B
    try std.testing.expectEqual(null, try unique_iter.next()); // S -> A B •
}

test "item_hash_map" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    const rule = Rule.from(S, &[_]Symbol{ A, B });
    const item = Item.from(rule);

    var hash_map = Item.HashMap(void).init(std.testing.allocator);
    defer hash_map.deinit();
    try hash_map.put(item, {});
    try std.testing.expectEqual(true, hash_map.contains(item));
}
