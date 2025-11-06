## Examples

Each example is runnable via `zig test src/sacrilege.zig` or by evaluating the forms in a context. The repository also ships with `.sac` files under `src/examples/`.

### Arithmetic

```lisp
(sum 1 2 3)      ; => 6
(sub 10 3 2)     ; => 5
(mult 2 3 4)     ; => 24
(div 20 3)       ; => 6
```

### Lists

```lisp
(list 1 2 3)                     ; => (1 2 3)
(car (list 10 20 30))            ; => 10
(cdr (list 10 20 30))            ; => (20 30)
(elem 2 (list 10 20 30 40))      ; => 20
(last (list 10 20 30))           ; => 30
(append (list 1 2) 3 4)          ; => (1 2 3 4)
(reverse (list 1 2 3))           ; => (3 2 1)
(list* 1 2 (list 3 4))           ; => (1 2 3 4)
(list-ref (list a b c) 1)        ; => b
(list-tail (list a b c d) 2)     ; => (c d)
```

### Predicates and logic

```lisp
(eq 3 3)            ; => true
(lt 2 5)            ; => true
(gt 9 1)            ; => true
(and true true)     ; => true
(or false true)     ; => true
(not false)         ; => true
```

### Variables and scope

```lisp
(set a 42)
(get a) ; => 42
```

### Functions and lambdas

```lisp
(defun add (x y) (sum x y))
(add 3 4) ; => 7

(set a 10)
(set inc-a (lambda (x) (sum a x)))
(inc-a 5) ; => 15
(set a 100)
(inc-a 5) ; => 15
```

### Higher-order functions

```lisp
(defun apply (f x) (f x))
(apply (lambda (z) (sum z 2)) 5) ; => 7
```

### Composition via closures

```lisp
(set inc (lambda (x) (sum x 1)))
(set double (lambda (x) (mult 2 x)))
(set inc-then-double (lambda (x) (double (inc x))))
(inc-then-double 5) ; => 12
```

### Conditionals (lazy)

```lisp
(if (eq 1 1) (print "equal") (print "not equal"))
```

### Modules and files

```lisp
(include "src/examples/lib/math-lib.sac")
(require "src/examples/lib/nested-lib.sac")
```


