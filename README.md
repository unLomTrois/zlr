# ZLR - LR parser generator written in Zig

The goal is to build LR parsers generator like yacc or bison from scratch.

TODO:
- [x] Grammar primitives: symbols, rules, grammar
- [x] LR(0) automata builder - build states from grammar
- [ ] Check whether Golang version makes transitions correctly
- [ ] Fix transitions
- [ ] Validate whether certain grammar is LR(0) grammar
- [ ] AST primitieves: Nodes
- [ ] LR(0) table parser
- [ ] SLR automata parser
- [ ] LR(1) automata & parser
- [ ] LALR(1) automata & parser