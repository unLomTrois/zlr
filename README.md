# ZLR - LR parser generator written in Zig

The goal is to build LR parsers generator like yacc or bison from scratch.

## Intended Use

ZLR is designed around a clean separation between lexical analysis and parsing. The workflow is:

1. **Define your grammar in Zig** - Grammars are defined as Zig data structures using `StaticGrammar.from()`
2. **Write a custom lexer** - Your lexer emits terminal symbols from the grammar and implements a `nextToken()` method
3. **Build a parser** - Use `Parser.init(grammar)` to create a parser from your grammar definition
4. **Parse with your lexer** - The `parse()` method accepts any struct with `nextToken()` that returns lightweight tokens

Tokens are simple structs containing:
- `type`: The terminal symbol from your grammar (converted to enums in generated code)
- `loc`: Source location with `start` and `end` positions as `usize`

You can use the parser at runtime for development, or **codegen** it into a self-contained, zero-dependency file for production.

```zig
const zlr = @import("zlr");
const Symbol = zlr.Symbol;
const Rule = zlr.Rule;
const StaticGrammar = zlr.StaticGrammar;
const Token = zlr.Token;

// Define grammar in Zig
const id = Symbol.from("id");
const plus = Symbol.from("+");
const lparen = Symbol.from("(");
const rparen = Symbol.from(")");
const cycle = Symbol.from("cycle");
const factor = Symbol.from("factor");

const terminals = &.{id, plus, lparen, rparen};
const non_terminals = &.{cycle, factor};

const my_grammar = StaticGrammar.from(cycle, terminals, non_terminals, &.{
    Rule.from(cycle, &.{id, plus, id}), // cycle -> id + id
    Rule.from(cycle, &.{factor}), // cycle -> factor
    Rule.from(factor, &.{lparen, cycle, rparen}), // factor -> ( cycle )
    Rule.from(factor, &.{id}), // factor -> id
});

// Your custom lexer
const MyLexer = struct {
    pub fn nextToken(self: *MyLexer) Token { /* your tokenization logic */ }
};

// Pick your parser type:
const Parser = @import("zlr/x/parser.zig").Parser; // x = lr0/slr/lr1/lalr

// Build and use parser
const parser = Parser.init(my_grammar);
try parser.validate(); // the grammar may be ambiguous for some parsers, so validate it
try parser.build(); // build state machine, parse tables, etc

const input = "((1 + 2) + 3)";

const parse_result = try parser.parse(input, &my_lexer);

const ast = parse_result.ast;

// OR: Generate self-contained parser with pre-built state machine, tables, etc
try parser.codegen("my_parser.zig");
```

TODO:
- [x] Grammar primitives: symbols, rules, grammar
- [x] LR(0) automata builder - build states from grammar
- [x] Fix transitions
- [x] Validate whether certain grammar is LR(0) grammar
- [ ] AST primitieves: Nodes
- [ ] LR(0) table parser
- [ ] SLR automata parser
- [ ] LR(1) automata & parser
- [ ] LALR(1) automata & parser