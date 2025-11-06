## Sacrilege Language Guide

This document describes the core language model, evaluation strategy, functions and lambdas, lists, predicates, and module/file semantics.

### Syntax

- S-expressions: `(operator arg1 arg2 ...)`
- Atoms:
  - Identifiers: `foo`, `sum`, `my-var`
  - Numbers: `0`, `-42`, `1337`
  - Strings: `"hello world"` (supports escapes: `\n`, `\t`, `\\`, `\"`)
- Comments: `;;` to end of line (see examples)

### Evaluation

- Eager by default: operator and all arguments are evaluated before application.
- Exceptions (lazy forms): `if`, `foreach`, `defun`, `lambda`, `set`, `get` handle evaluation explicitly.
- Booleans are identifiers `true` and `false`.

#### Identifiers and variables

- Set variable: `(set name expr)` stores the evaluated value of `expr` under `name`.
- Get variable: `(get name)` retrieves it.

Identifiers in argument position are resolved to their stored values when evaluated. Operator position prefers function lookup by identifier name; if an identifier resolves to a function value (lambda/defun output), it is applied.

### Functions

#### User-defined functions

```
(defun name (p1 p2 ...) body1 body2 ... bodyN)
```

- Parameters must be identifiers.
- Bodies are evaluated in order; the value of the last expression is returned.
- Tail-call optimization (TCO) applies to self-calls in tail position.

#### Anonymous functions (lambdas)

```
(lambda (p1 p2 ...) body1 body2 ... bodyN)
```

- Returns an identifier referencing the anonymous function.
- Captures free identifiers by value at definition time (lexical closures).
- Anonymous functions are registered with a per-context unique name.

#### Higher-order usage

```
(defun apply (f x) (f x))
(apply (lambda (z) (sum z 2)) 5) ; => 7
```

### Control flow

```
(if condition then-expr [else-expr])
```

- `condition` is evaluated; must produce `true` or `false`.
- Only the chosen branch is evaluated (lazy).

### Lists

- Construction: `(list a b c)` or `(cons a (list b c))`
- Accessors: `(car xs)`, `(cdr xs)`, `(elem n xs)` (1-based), `(last xs)`
- Queries: `(empty xs)`, `(empty? xs)`, `(null? xs)`, `(list? x)`, `(pair? x)`
- Derived: `(length xs)`, `(reverse xs)`, `(append xs ...items)`, `(list* a b ... last)`
- Slices: `(list-ref xs i)` (0-based), `(list-tail xs n)`

### Predicates and logic

- Numeric comparisons: `(eq a b)`, `(lt a b)`, `(gt a b)`
- Boolean: `(and a b ...)`, `(or a b ...)`, `(not a)`

### I/O and parsing

- `(print "..." ...)` prints atoms (strings/numbers/identifiers) separated by spaces and newline
- `(readfile "path")` returns file contents as a string
- `(parse "source")` tokenizes and parses a string into a syntax tree

### Modules and files

- `(evalfile "path")`: parse and evaluate all forms in file; returns last value
- `(include "path")`: same semantics as `evalfile`
- `(require "path")`: evaluate a file once (idempotent), ignoring subsequent calls

### Errors

Common runtime errors signaled by the evaluator:
- `WrongArgumentCount`
- `WrongArgumentType`
- `WrongExpressionType`
- `FunctionDoesNotExist`
- `UndefinedIdentifier`
- `AssertionFailed`

### Examples

See `docs/Examples.md` and `src/examples/*.sac` for more.


