const std = @import("std");

pub const Symbol = struct {
    name: []const u8,

    /// Inline wrapper for literal symbol creation
    /// deprecated: use fromAlloc instead
    /// prefer fromAlloc for all cases, it's more explicit and safer.
    /// Inlined symbols may not outlive the scope they are created in.
    pub inline fn from(name: []const u8) Symbol {
        return Symbol{ .name = name };
    }

    /// fromAlloc creates a symbol from a passed string, but also allocates the string inside the symbol
    /// It returns an unmanaged symbol, caller is responsible for freeing the string.
    /// Generally, you would use arena allocator for all three: grammar, rule, and symbol allocation.
    /// This is useful for creating symbols that are not known at compile time, but are known at runtime
    /// E.g. when parsing a grammar from a file
    pub fn fromAlloc(alloc: std.mem.Allocator, name: []const u8) !Symbol {
        return Symbol{ .name = try alloc.dupe(u8, name) };
    }

    pub fn deinit(self: *const Symbol, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
    }

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide symbol into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S
    /// Returns "S"
    pub fn format(self: *const Symbol, writer: *std.io.Writer) !void {
        try writer.print("{s}", .{self.name});
    }

    /// eql compares two symbols by their name.
    pub fn eql(a: *const Symbol, b: *const Symbol) bool {
        return std.mem.eql(u8, a.name, b.name);
    }

    pub fn hash(self: *const Symbol) u64 {
        return std.hash.Wyhash.hash(self.name.len, self.name);
    }

    pub fn is_augmented(self: *const Symbol) bool {
        return std.mem.eql(u8, self.name, "S'");
    }

    pub fn is_eof(self: *const Symbol) bool {
        return std.mem.eql(u8, self.name, "$");
    }

    pub const HashMapContext = struct {
        pub fn hash(_: HashMapContext, key: Symbol) u64 {
            return key.hash();
        }

        pub fn eql(_: HashMapContext, a: Symbol, b: Symbol) bool {
            return a.eql(&b);
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.HashMap(Symbol, V, HashMapContext, std.hash_map.default_max_load_percentage);
    }

    pub const ArrayHashContext = struct {
        pub fn hash(_: ArrayHashContext, key: Symbol) u32 {
            return std.hash.cityhash.CityHash32.hash(key.name);
        }

        pub fn eql(_: ArrayHashContext, a: Symbol, b: Symbol, _: usize) bool {
            return a.eql(&b);
        }
    };

    pub fn ArrayHashMap(comptime V: type) type {
        return std.ArrayHashMap(Symbol, V, ArrayHashContext, true);
    }

    pub const Epsilon = Symbol.from("ε");
};

test "symbol_from" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(symbol.name, "S");
}

test "symbol_format" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);

    const str = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{symbol});
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(str, "S");
}

test "symbol_eql" {
    const symbol1 = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol1.deinit(std.testing.allocator);

    const symbol2 = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol2.deinit(std.testing.allocator);

    try std.testing.expect(Symbol.eql(&symbol1, &symbol2)); // equivalent to:
    try std.testing.expect(symbol1.eql(&symbol2));
}

test "symbol_fromAlloc" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(symbol.name, "S");
}

test "symbol hash maps" {
    var h = Symbol.HashMap(void).init(std.testing.allocator);
    defer h.deinit();

    try h.put(Symbol.from("S"), {});
    try h.put(Symbol.from("A"), {});
    try h.put(Symbol.from("B"), {});

    try std.testing.expect(h.contains(Symbol.from("S")));
    try std.testing.expect(h.contains(Symbol.from("A")));
}
