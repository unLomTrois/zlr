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

    pub noinline fn fromNoInline(name: []const u8) Symbol {
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

    /// Copies and takes ownership of a slice, caller is responsible for freeing the slice.
    /// Elements of the slice are supposed to be inited by fromInline.
    pub fn fromSlice(alloc: std.mem.Allocator, symbols: []const Symbol) error{OutOfMemory}![]Symbol {
        return try alloc.dupe(Symbol, symbols);
    }

    /// Formats the struct as a string into a writer.
    /// E.g. std.fmt.allocPrint, std.io.getStdOut().writer(), etc.
    /// Not intended to be used directly. Instead provide symbol into args of std.fmt.allocPrint, etc.
    ///
    /// e.g. S
    /// Returns "S"
    pub fn format(self: *const Symbol, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{self.name});
    }

    /// eql compares two symbols by their name.
    pub fn eql(a: Symbol, b: Symbol) bool {
        return std.mem.eql(u8, a.name, b.name);
    }

    pub fn eqlTo(self: *const Symbol, other: Symbol) bool {
        return self.eql(other);
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: Symbol) u64 {
            return std.hash.Wyhash.hash(0, key.name);
        }

        pub fn eql(_: HashContext, a: Symbol, b: Symbol) bool {
            return a.eql(b);
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.HashMap(Symbol, V, HashContext, std.hash_map.default_max_load_percentage);
    }

    const ArrayHashContext = struct {
        pub fn hash(_: ArrayHashContext, key: Symbol) u32 {
            return std.hash.cityhash.CityHash32.hash(key.name);
        }

        pub fn eql(_: ArrayHashContext, a: Symbol, b: Symbol, _: usize) bool {
            return a.eql(b);
        }
    };

    pub fn ArrayHashMap(comptime V: type) type {
        return std.ArrayHashMap(Symbol, V, ArrayHashContext, true);
    }
};

test "symbol_from" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(symbol.name, "S");
}

test "symbol_format" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);

    const str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{symbol});
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(str, "S");
}

test "symbol_eql" {
    const symbol1 = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol1.deinit(std.testing.allocator);

    const symbol2 = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol2.deinit(std.testing.allocator);

    try std.testing.expect(Symbol.eql(symbol1, symbol2)); // equivalent to:
    try std.testing.expect(symbol1.eqlTo(symbol2));
}

test "symbol_fromAlloc" {
    const symbol = try Symbol.fromAlloc(std.testing.allocator, "S");
    defer symbol.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(symbol.name, "S");
}

/// Caller is responsible for freeing the symbol.
fn outOfScopeSymbol(alloc: std.mem.Allocator) !Symbol {
    const S = try Symbol.fromAlloc(alloc, "S");

    return S;
}

test "out of scope symbol" {
    const symbol = try outOfScopeSymbol(std.testing.allocator);
    defer symbol.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("S", symbol.name);
}

fn outOfScopeSlice(alloc: std.mem.Allocator) ![]const Symbol {
    const S = try Symbol.fromAlloc(alloc, "S");
    const A = try Symbol.fromAlloc(alloc, "A");
    const B = try Symbol.fromAlloc(alloc, "B");

    return try alloc.dupe(Symbol, &.{ S, A, B });
}

test "out of scope slice" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const syms = try outOfScopeSlice(alloc);

    try std.testing.expectEqualStrings("S", syms[0].name);
    try std.testing.expectEqualStrings("A", syms[1].name);
    try std.testing.expectEqualStrings("B", syms[2].name);
}

// TODO: move following tests to rules.zig
const RuleLike = struct {
    lhs: Symbol,
    rhs: []const Symbol,

    fn from(lhs: Symbol, rhs: []const Symbol) RuleLike {
        return RuleLike{ .lhs = lhs, .rhs = rhs };
    }

    fn fromAlloc(alloc: std.mem.Allocator, lhs: Symbol, rhs: []const Symbol) !RuleLike {
        return RuleLike{ .lhs = lhs, .rhs = try alloc.dupe(Symbol, rhs) };
    }
};

fn outOfScopeRule(alloc: std.mem.Allocator) !RuleLike {
    const S = try Symbol.fromAlloc(alloc, "S");
    const A = try Symbol.fromAlloc(alloc, "A");
    const B = try Symbol.fromAlloc(alloc, "B");

    return try RuleLike.fromAlloc(alloc, S, &.{ A, B });
}

test "not failing out of scope rule" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const symbol_wrapper = try outOfScopeRule(alloc);

    try std.testing.expectEqualStrings("S", symbol_wrapper.lhs.name);
    try std.testing.expectEqualStrings("A", symbol_wrapper.rhs[0].name);
    try std.testing.expectEqualStrings("B", symbol_wrapper.rhs[1].name); // NOT SEGFAULT
}

// This is usable if both symbols and the array are allocated in the same arena.
const UnmanagedSymbolArrayList = struct {
    symbols: std.ArrayList(Symbol),

    fn from(alloc: std.mem.Allocator, symbols: []Symbol) UnmanagedSymbolArrayList {
        return UnmanagedSymbolArrayList{
            .symbols = std.ArrayList(Symbol).fromOwnedSlice(alloc, symbols),
        };
    }
};

test "symbol slice" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const S = try Symbol.fromAlloc(alloc, "S");
    const A = try Symbol.fromAlloc(alloc, "A");
    const B = try Symbol.fromAlloc(alloc, "B");

    const symbols = try Symbol.fromSlice(alloc, &.{ S, A, B });

    var symbol_array_list = UnmanagedSymbolArrayList.from(alloc, symbols);

    const S_prime = try Symbol.fromAlloc(alloc, "S'");
    try symbol_array_list.symbols.append(S_prime);

    try std.testing.expectEqualStrings("S", symbol_array_list.symbols.items[0].name);
    try std.testing.expectEqualStrings("A", symbol_array_list.symbols.items[1].name);
    try std.testing.expectEqualStrings("B", symbol_array_list.symbols.items[2].name);
    try std.testing.expectEqualStrings("S'", symbol_array_list.symbols.items[3].name);
}

// Managed symbol array list has deinit for both symbols and the owned slice.
const ManagedSymbolArrayList = struct {
    allocator: std.mem.Allocator,
    symbols: std.ArrayList(Symbol),

    fn from(alloc: std.mem.Allocator, symbols: []Symbol) ManagedSymbolArrayList {
        return ManagedSymbolArrayList{
            .allocator = alloc,
            .symbols = std.ArrayList(Symbol).fromOwnedSlice(alloc, symbols),
        };
    }

    fn deinit(self: *ManagedSymbolArrayList) void {
        for (self.symbols.items) |symbol| { // Must to deinit each allocated symbol
            symbol.deinit(self.allocator);
        }
        self.symbols.deinit(); // Frees allocated slice
    }
};

test "managed symbol array list" {
    const alloc = std.testing.allocator;

    // freed by symbol_array_list.deinit()
    const S = try Symbol.fromAlloc(alloc, "S");
    const A = try Symbol.fromAlloc(alloc, "A");
    const B = try Symbol.fromAlloc(alloc, "B");

    // freed by symbol_array_list.deinit()
    const symbols = try Symbol.fromSlice(alloc, &.{ S, A, B });

    var symbol_array_list = ManagedSymbolArrayList.from(alloc, symbols);

    defer symbol_array_list.deinit();

    const S_prime = try Symbol.fromAlloc(alloc, "S'");
    try symbol_array_list.symbols.append(S_prime);

    try std.testing.expectEqualStrings("S", symbol_array_list.symbols.items[0].name);
    try std.testing.expectEqualStrings("A", symbol_array_list.symbols.items[1].name);
    try std.testing.expectEqualStrings("B", symbol_array_list.symbols.items[2].name);
    try std.testing.expectEqualStrings("S'", symbol_array_list.symbols.items[3].name);
}

// Less managed symbol array list implies Symbols are inlined,
// And only deinit allocated slices. Elements of the slices are not freed.
const LessManagedSymbolArrayList = struct {
    allocator: std.mem.Allocator,
    symbols: std.ArrayList(Symbol),

    fn from(alloc: std.mem.Allocator, symbols: []Symbol) LessManagedSymbolArrayList {
        return LessManagedSymbolArrayList{
            .allocator = alloc,
            .symbols = std.ArrayList(Symbol).fromOwnedSlice(alloc, symbols),
        };
    }

    fn deinit(self: *LessManagedSymbolArrayList) void {
        self.symbols.deinit();
    }
};

test "less managed symbol array list" {
    const alloc = std.testing.allocator;

    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    const symbols = try Symbol.fromSlice(alloc, &.{ S, A, B });

    var symbol_array_list = LessManagedSymbolArrayList.from(alloc, symbols);
    defer symbol_array_list.deinit();

    try std.testing.expectEqualStrings("S", symbol_array_list.symbols.items[0].name);
    try std.testing.expectEqualStrings("A", symbol_array_list.symbols.items[1].name);
    try std.testing.expectEqualStrings("B", symbol_array_list.symbols.items[2].name);
}

// Will it work with out of scope symbols?

fn outOfScopeSymbolArrayList(alloc: std.mem.Allocator) ![]Symbol {
    const S = Symbol.fromNoInline("Saaaa"); // prove of concept
    const A = Symbol.fromNoInline("Aaaaa");
    const B = Symbol.fromNoInline("Baaaa");

    return try Symbol.fromSlice(alloc, &.{ S, A, B });
}

test "out of scope symbol array list" {
    const alloc = std.testing.allocator;

    const symbols = try outOfScopeSymbolArrayList(alloc);

    var symbol_array_list = LessManagedSymbolArrayList.from(alloc, symbols);
    defer symbol_array_list.deinit(); // No leak!

    // LessManagedSymbolArrayList can take allocated symbols, but they deinit themselves.
    // It does not tries to deinit elements of the slice unlike ManagedSymbolArrayList.
    const S_prime = try Symbol.fromAlloc(alloc, "S'aaaa");
    defer S_prime.deinit(alloc);
    try symbol_array_list.symbols.append(S_prime);

    try std.testing.expectEqualStrings("Saaaa", symbol_array_list.symbols.items[0].name);
    try std.testing.expectEqualStrings("Aaaaa", symbol_array_list.symbols.items[1].name);
    try std.testing.expectEqualStrings("Baaaa", symbol_array_list.symbols.items[2].name);
    try std.testing.expectEqualStrings("S'aaaa", symbol_array_list.symbols.items[3].name);
}

test "arena variant of less managed symbol array list" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const S = Symbol.fromNoInline("S");
    const A = Symbol.fromNoInline("A");
    const B = Symbol.fromNoInline("B");

    const symbols = try Symbol.fromSlice(alloc, &.{ S, A, B });

    var symbol_array_list = LessManagedSymbolArrayList.from(alloc, symbols);
    // defer symbol_array_list.deinit(); // No needed, because of arena

    const S_prime = try Symbol.fromAlloc(alloc, "S'");
    // defer S_prime.deinit(alloc); // No needed, because of arena
    try symbol_array_list.symbols.append(S_prime);

    try std.testing.expectEqualStrings("S", symbol_array_list.symbols.items[0].name);
    try std.testing.expectEqualStrings("A", symbol_array_list.symbols.items[1].name);
    try std.testing.expectEqualStrings("B", symbol_array_list.symbols.items[2].name);
    try std.testing.expectEqualStrings("S'", symbol_array_list.symbols.items[3].name);
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
