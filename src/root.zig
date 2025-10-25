//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const grammars = @import("grammars/grammar.zig");
pub const lr0 = @import("lr0/automaton.zig");

const ParsingTable = @import("lr/parsing_table.zig").ParsingTable;

test "root tests" {
    std.testing.refAllDecls(@This());
}

test "This test prints a parsing table for a simple grammar" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.SimpleGrammar(allocator);
    std.debug.print("Grammar:\n{f}\n", .{grammar});

    var automaton = lr0.Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();
    std.debug.print("Automaton:\n {f}\n", .{automaton});

    var table = try ParsingTable.from_lr0(allocator, &automaton);
    defer table.deinit(allocator);
    std.debug.print("Parsing Table:\n{f}", .{table});
}

// test "zlr library api" {
//     const l1 = @import("lr1/parser.zig");
//     const yaml = @import("grammars/yaml.zig");
//     const yaml_parser = l1.Parser.init(yaml.grammar);
//     try yaml_parser.build();
//     const yaml_example = @embedFile("example.yaml");
//     const parse_result = try yaml_parser.parse(yaml_example);
//     const ast = parse_result.ast;
//     std.debug.print("AST: {}\n", .{ast});
// }

// test "zlr codegen api" {
//     const l1 = @import("lr1/parser.zig");
//     const yaml = @import("grammars/yaml.zig");
//     const yaml_parser = l1.Parser.init(yaml.grammar);
//     try yaml_parser.build();
//     // emit the parser to a file with prebuilt state machine, tables, ast mapping, etc
//     // can be used in CLI, to generate a prebuilt parser for a given grammar
//     // self contained, no dependencies on the original grammar
//     // in the generated parser, named symbols are replaced with enums, so you could use them in lexer, etc, error handling, etc
//     try yaml_parser.codegen("yaml_parser.zig");
//     // after that, in another file or project, you can use the prebuilt parser:
//     const prebuilt_parser = @import("yaml_parser.zig");
//     // can even make it dynamic library when building your project in build.zig
//     const yaml_example = @embedFile("example.yaml");
//     const parse_result = try prebuilt_parser.parse(yaml_example);
//     const ast = parse_result.ast;
//     // same result as above test, but without the need to build the parser again each time you run your program.
//     std.debug.print("AST: {}\n", .{ast});
// }
