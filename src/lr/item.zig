const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Rule = grammars.Rule;

const Action = @import("action.zig").Action;

const utils = @import("../utils/iter.zig");

/// Item represents an LR parsing item.
/// It is a production rule with a dot position.
/// The dot position indicates the position of the next symbol to be parsed.
/// The dot position is 0 for the first symbol of the production rule.
pub const Item = struct {
    rule: Rule,
    dot_pos: usize,
    action: Action,

    pub fn from(rule: Rule) Item {
        return Item{
            .rule = rule,
            .dot_pos = 0,
            .action = .shift,
        };
    }

    pub inline fn fromInline(rule: Rule) Item {
        return Item{
            .rule = rule,
            .dot_pos = 0,
            .action = .shift,
        };
    }

    /// The item is complete if the dot is at the end of the rule
    ///
    /// e.g. S -> A B •
    pub fn is_complete(self: Item) bool {
        return self.dot_pos >= self.rule.rhs.len;
    }

    pub fn is_incomplete(self: Item) bool {
        return !self.is_complete();
    }

    pub fn is_accept_item(self: Item) bool {
        std.debug.assert(self.is_complete());
        return self.rule.lhs.eqlTo(Symbol.from("S'"));
    }

    /// The dot symbol is the symbol after the dot.
    ///
    /// e.g. in "S -> A • B", the dot symbol is B
    /// S -> A B • is complete, so dot symbol is null
    pub fn dot_symbol(self: *const Item) ?Symbol {
        if (self.is_complete()) {
            return null;
        }

        return self.rule.rhs[self.dot_pos];
    }

    /// For `• A + B` the top stack symbol is null.
    ///
    /// For `A • + B` the top stack symbol is `A`.
    ///
    /// For `A + • B` the top stack symbol is `+`.
    pub fn pre_dot_symbol(self: *const Item) ?Symbol {
        if (self.dot_pos == 0) {
            return null;
        }

        return self.rule.rhs[self.dot_pos - 1];
    }

    pub fn advance_dot_clone(self: *const Item) Item {
        var item = Item{
            .rule = self.rule,
            .dot_pos = self.dot_pos + 1,
            .action = .shift,
        };

        if (item.is_complete()) {
            item.action = .reduce;
            if (item.is_accept_item()) item.action = .accept;
        }

        return item;
    }

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide item into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S -> A B •
    /// Returns "S -> A B •"
    pub fn format(self: *const Item, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("[{?s}] ", .{std.enums.tagName(Action, self.action)});
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

    /// Iterate over the items which dot symbol is equal to the given filter symbol.
    ///
    /// Useful for GOTO set computation.
    pub const FilterDotSymbolIter = struct {
        iter: *utils.Iter(Item),

        pub inline fn from(iter: *utils.Iter(Item)) FilterDotSymbolIter {
            return FilterDotSymbolIter{ .iter = iter };
        }

        pub fn next(self: *FilterDotSymbolIter, filter_symbol: Symbol) ?Item {
            while (self.iter.next_if(Item.is_incomplete)) |item| {
                if (item.dot_symbol().?.eqlTo(filter_symbol)) return item;
            }
            return null;
        }
    };

    /// Iterate over a slice and filter out items with unique dot symbols.
    ///
    /// Example:
    /// ```
    /// cycle -> • id + id
    /// cycle -> • term
    /// term -> • ( cycle )
    /// term -> • id
    /// ```
    /// UniqueIter will emit: `id`, `term`, `(`
    pub const UniqueIter = struct {
        iter: *utils.Iter(Item),
        array_hash_map: *Symbol.ArrayHashMap(void),

        pub inline fn from(iter: *utils.Iter(Item), array_hash_map: *Symbol.ArrayHashMap(void)) UniqueIter {
            return UniqueIter{
                .iter = iter,
                .array_hash_map = array_hash_map,
            };
        }

        pub fn next(self: *UniqueIter) !?Item {
            while (self.iter.next_if(Item.is_incomplete)) |item| {
                const symbol = item.dot_symbol().?;
                if (self.array_hash_map.contains(symbol)) continue;
                try self.array_hash_map.put(symbol, {});
                return item;
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

    const cases = [_][]const u8{ "[shift] S -> • A B", "[shift] S -> A • B", "[reduce] S -> A B •" };

    const allocator = std.testing.allocator;
    for (cases) |case| {
        const str = try std.fmt.allocPrint(allocator, "{s}", .{item});
        defer allocator.free(str);
        defer item = item.advance_dot_clone();
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

    var symbol_array_hash_map = Symbol.ArrayHashMap(void).init(std.testing.allocator);
    defer symbol_array_hash_map.deinit();

    var iter = utils.Iter(Item).from(items);
    var unique_iter = Item.UniqueIter.from(&iter, &symbol_array_hash_map);

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
