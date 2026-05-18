# Zig Programming Notes from Blog Posts

This guide summarizes Zig-related Djot posts under `content/posts` and selected TigerBeetle blog
posts from `https://tigerbeetle.com/blog/atom.xml`. The aim is not to preserve the shape of the
original essays, but to extract practical Zig programming wisdom in a form that can be read without
opening the posts.

## Per-Post Takeaways

### 2023-02-10 - How a Zig IDE Could Work

Source: [https://matklad.github.io/2023/02/10/how-a-zig-ide-could-work.html](https://matklad.github.io/2023/02/10/how-a-zig-ide-could-work.html)

Zig's compilation model is friendly to syntactic tooling but hard for semantic tooling. Each file
can be parsed independently into an AST, and Zig deliberately avoids syntactic macros, glob imports,
and many context-sensitive syntax traps. That makes file-local features, outlines, fuzzy symbol
search, and syntax-aware tools much easier than in languages whose syntax can be rewritten by
macros. The hard part starts at semantic analysis: Zig lowers AST to ZIR, then lazily partially
evaluates ZIR from entry points, specializing `comptime` parameters and monomorphizing only what is
actually used.

The practical lesson for Zig tools is to separate fast, local, always-available facts from slower,
precise, whole-program facts. A tool that tries to "compile everything" for every editor query will
be too slow, and it still cannot answer questions about unused generic functions. A better approach
is to give immediate answers from AST/ZIR and abstract interpretation, then refine in the background
using the real set of monomorphizations discovered by compilation.

This also matters when designing Zig libraries: explicit signatures and simple syntax make your code
easier for tooling to understand. Hiding behavior behind elaborate `comptime` control flow makes the
compiler powerful, but it pushes IDEs toward approximation. Prefer APIs whose important structure
is visible from declarations and ordinary field/method syntax.

### 2023-03-26 - Zig And Rust

Source: [https://matklad.github.io/2023/03/26/zig-and-rust.html](https://matklad.github.io/2023/03/26/zig-and-rust.html)

Zig works best when the whole program is designed around explicit control of resources rather than
when it is treated as "Rust with `defer` instead of RAII". Rust excels at modular, machine-checked
contracts between components. Zig gives fewer safety rails, but a much smaller language and sharper
control over allocation, IO, time, and layout. That tradeoff pays off most in systems where you can
control the entire design and reduce resource management to a small number of obvious places.

The core pattern is to architect code so that little can fail in the hot path. TigerBeetle is the
running example: allocate all memory at startup, define upper bounds for every resource, externalize
all IO and time, avoid ambient dependencies, and use deterministic simulation to test environmental
interleavings. In Zig, passing allocators explicitly makes this style natural. If an event loop does
not receive an allocator, it cannot allocate by accident.

The caveat is that Zig code becomes dangerous when the design still requires complicated local
ownership transfers. Replacing every destructor with a nearby `defer` invites forgotten cleanup and
exception-safety bugs. Use Zig when you can simplify the resource story globally: preallocate,
batch, keep data in explicit pools, and make dependencies visible in function signatures.

### 2023-04-23 - Data Oriented Parallel Value Interner

Source: [https://matklad.github.io/2023/04/23/data-oriented-parallel-value-interner.html](https://matklad.github.io/2023/04/23/data-oriented-parallel-value-interner.html)

For compiler-like data, indexes and struct-of-arrays storage can beat pointer-heavy object graphs.
The post sketches a parallel interner for Zig compiler values: a `Value` becomes a `u32` index, tags
and common payload live in parallel segmented arrays, and large variant-specific payloads live in
separate arrays. This layout shrinks memory, improves locality, and makes interned trees cheap to
hash because child values are already interned indexes.

The important data-structure pattern is `SegmentList`: store elements in power-of-two echelons so
new insertions do not move old elements. A `u32` index can address at most 2^32 entries, so the
table needs only a fixed array of echelon pointers. Echelons can be allocated lazily with a single
compare-and-swap. Once an index has been returned to a caller, possession of that index is treated
as proof that the element has been initialized and published.

For concurrency, avoid one global lock when possible. Shard the hash set by hash bits so unrelated
values can be interned in parallel, and batch atomic counter increments by giving each thread a
local range of indexes. The subtle correctness rule is publication order: do not expose an index in
the hash set before the value's storage is fully initialized, or a racing lookup can observe a
partially initialized value.

### 2023-05-06 - Zig Language Server And Cancellation

Source: [https://matklad.github.io/2023/05/06/zig-language-server-and-cancellation.html](https://matklad.github.io/2023/05/06/zig-language-server-and-cancellation.html)

A Zig language server should start with a robust evolving data model, not with a pile of features.
The core problem is cancellation: while the server is computing expensive semantic results, the user
keeps editing. If reads block writes, the editor feels stale. If edits mutate state while old work
is reading it, the server gets data races or logically inconsistent analysis. Full immutability
solves this but can waste memory and CPU.

The proposed model separates state into `pending`, `working`, and `ready`. `pending` is the latest
per-file AST state and is updated immediately. `working` is a background semantic analysis snapshot.
`ready` is the last fully analyzed snapshot, safe to query from any thread. Fast editor features can
answer from `pending`; semantic features can combine fresh syntax from `pending` with older
semantic facts from `ready`; precise refactorings can block until `working` catches up.

The broader Zig lesson is to design around snapshots and explicit consistency levels. Zig's lazy
"start from the entry point" compilation model makes perfect strong consistency expensive for IDEs,
but Zig's simple syntax makes partial answers useful. For tools and long-running services, it is
often better to keep a clear stale-but-safe snapshot than to let partially updated state leak
through the system.

### 2023-06-02 - The Worst Zig Version Manager

Source: [https://matklad.github.io/2023/06/02/the-worst-zig-version-manager.html](https://matklad.github.io/2023/06/02/the-worst-zig-version-manager.html)

The best Zig version manager for a project may be no global version manager at all. Vendor a small
bootstrap script, download the exact compiler into `./zig`, ignore that directory in git, and run
all commands as `./zig/zig build ...`. This makes the repository self-contained after one bootstrap
step and removes dependence on the user's `PATH`, shell profile, package manager, or globally
installed Zig version.

The pattern is especially valuable while Zig is evolving quickly. A system package can lag or carry
the wrong version, and a full version manager adds its own installation and activation problems. A
checked-in `zig-version.txt` plus a small `getzig` script keeps the version choice close to the
project and makes CI, contributors, and local workflows agree by construction.

The production version of this idea should verify download integrity, auto-detect host platform and
architecture, tolerate `curl` or `wget`, and be small enough to vendor. The general style lesson is
Zig-like: reduce ambient assumptions. Once the repository can get its own `zig` binary, use Zig
itself to drive the rest of the automation.

### 2023-08-09 - Types and the Zig Programming Language

Source: [https://matklad.github.io/2023/08/09/types-and-zig.html](https://matklad.github.io/2023/08/09/types-and-zig.html)

Zig's type system is nominal even though type expressions are anonymous. Two separately written
`struct { f: i32 }` types are distinct, and assigning a struct expression to a `const S = struct
{...};` name is what gives later code a handle to that exact type. Anonymous struct literals are the
notable structural escape hatch: a literal like `.{ .foo = 1 }` can be coerced to a compatible
destination type when the result type is known.

Zig deliberately avoids unification-heavy inference. Generic parameters are usually explicit, as in
`reverse(i32, xs)`, but the burden stays manageable because methods close over the type parameters
of their receiver. Once you have `var xs: ArrayList(u32)`, calls such as `xs.append(...)` do not
repeat `u32`: the receiver type already carries it.

Function signatures are mandatory and mostly complete. That is good for humans, compilers, and
language servers because callers can often be checked without inspecting callee bodies. The main
exception is inferred error sets via `!T`, where the exact set of possible errors can leak from the
function body. When API boundaries matter, prefer explicit error sets so the signature really is the
interface.

### 2024-03-21 - Zig defer Patterns

Source: [https://matklad.github.io/2024/03/21/defer-patterns.html](https://matklad.github.io/2024/03/21/defer-patterns.html)

`defer` is powerful, but it should not be treated as a wholesale replacement for RAII. Humans forget
defers, especially around optional ownership transfer. The better Zig lesson is that painful
per-object cleanup nudges you toward fewer resources: batch allocation, shared buffers, arenas, and
explicit resource lifetimes that are larger than individual domain objects.

`defer` and `errdefer` also encode useful non-resource patterns. `defer assert(postcondition)` makes
postconditions mechanically local to the code that establishes them. `errdefer comptime unreachable`
marks the point after which a fallible function must be infallible; if a later `try` could return an
error, compilation fails. That is the idiom used after a reservation phase has completed.

For reporting, `errdefer |err| log.err(...)` can attach local context at the point where the context
is known, while still using normal `try` propagation. For tiny state updates, `defer self.count +=
1` can express post-increment behavior, returning the old slot while reliably advancing the counter
on scope exit. Use these patterns when they make control flow more obvious, not as cleanup folklore.

### 2025-03-19 - Comptime Zig ORM

Source: [https://matklad.github.io/2025/03/19/comptime-zig-orm.html](https://matklad.github.io/2025/03/19/comptime-zig-orm.html)

The post builds a toy compile-time-schema relational database to teach Zig's `comptime` reflection.
The schema is a value passed to a type constructor: `DBType(.{ .tables = ..., .indexes = ... })`
returns a concrete database type with typed table fields and indexes. This shows Zig's central
metaprogramming style: do not generate source text; compute types and values from ordinary Zig
values known at compile time.

Several idioms recur. Use `enum(u64) { _ }` as a typed ID/newtype over an integer so `Account.ID`
and `Transfer.ID` cannot be mixed by accident. Pass allocators only to operations that can allocate,
which makes fallibility visible at the call site. Use `ArrayListUnmanaged` with explicit
`ensureUnusedCapacity` and `appendAssumeCapacity` so reservation and mutation are separate phases.
Pass output buffers into queries rather than allocating result containers.

The implementation demonstrates reflection primitives: `std.meta.FieldEnum(T)` gives a typed enum
of field names, `@tagName` turns a field enum into a string, `@field(value, name)` reads a field by
compile-time name, `@FieldType` gets a field type, and `@Type` can construct a struct type. The
payoff is generated tables and indexes whose final code is direct field access and direct
comparisons after `inline for` unrolling.

The caveat is just as important as the technique: comptime reflection can become mind-bending. Use
it for clear library boundaries where the generated type buys real safety or performance. Do not
reach for it just to avoid writing straightforward code.

### 2025-04-19 - Things Zig comptime Won't Do

Source: [https://matklad.github.io/2025/04/19/things-zig-comptime-wont-do.html](https://matklad.github.io/2025/04/19/things-zig-comptime-wont-do.html)

Zig `comptime` is powerful because it is ordinary Zig evaluation with compile-time-known values, not
because it is an unrestricted macro system. It does not leak host-machine details during cross
compilation: compile-time code observes the target's pointer size and endianness. It does not
provide `eval`, token rewriting, custom syntax hooks, or arbitrary source generation. You specialize
ordinary functions with `comptime` parameters instead.

The key distinction is between evaluating at compile time and specializing runtime code. A
`comptime for` runs the whole loop at compile time. An `inline for` unrolls the loop when the
iteration space is known, while the body can still operate on runtime values. That is how a generic
printer can reflect on fields at compile time and still print a runtime struct value.

Zig also does not keep type values at runtime. If runtime type information is needed, you must
explicitly reify it into your own data structure, such as a tagged union describing fields and
offsets. It cannot add new methods to user types the way Rust derives can; libraries provide
top-level functions such as `to_json(T, value, writer)` and can ask types to opt in with explicit
declarations. Finally, comptime has no IO. If build-time IO is needed, put it in `build.zig` and
generate/import normal Zig code.

### 2025-04-21 - A Fun Zig Program

Source: [https://matklad.github.io/2025/04/21/fun-zig-program.html](https://matklad.github.io/2025/04/21/fun-zig-program.html)

Zig type positions can contain arbitrary compile-time expressions, and those expressions can depend
on earlier `comptime` parameters. A function can have a return type like `if (x) u32 else bool`
when `x` is a compile-time boolean. Calling it with `f(true)` and `f(false)` produces different
specialized signatures.

The teaching point is Zig's order of analysis. For a generic function call, the compiler first
computes the signature from the compile-time arguments without using the function body. Then it
checks that the call site matches the computed signature and that the body is valid for that
signature. This reinforces the broader rule: Zig generics are explicit specialization, not hidden
return-type inference.

In API design, this power is best used sparingly. Dependent return types can make tiny generic
utilities elegant, but they also make the function's interface a program. Keep such expressions
small and obvious, and remember that the signature is the contract callers and tools must
understand.

### 2025-08-08 - Partially Matching Zig Enums

Source: [https://matklad.github.io/2025/08/08/partially-matching-zig-enums.html](https://matklad.github.io/2025/08/08/partially-matching-zig-enums.html)

When several variants of a `union(enum)` need shared handling and then variant-specific handling,
many languages force either duplication, refactoring the enum, or an inner `unreachable`. Zig can
make the inner exhaustiveness check compile-time-checked by combining `inline` switch prongs with
`comptime unreachable`.

The pattern is:

```zig
switch (u) {
    inline .a, .b => |_, tag| {
        handle_ab();
        switch (tag) {
            .a => handle_a(),
            .b => handle_b(),
            else => comptime unreachable,
        }
    },
    .c => handle_c(),
}
```

`inline .a, .b` specializes the branch for each listed tag, so `tag` is known at compile time inside
each copy. If the inner switch accidentally allows a case that is not covered, `comptime
unreachable` fails compilation instead of leaving a runtime panic. Use this when a flat tagged union
is right for most code but one local handler wants a grouped subset.

### 2025-08-09 - Zig's Lovely Syntax

Source: [https://matklad.github.io/2025/08/09/zigs-lovely-syntax.html](https://matklad.github.io/2025/08/09/zigs-lovely-syntax.html)

Zig's syntax is optimized for a small language with simple name resolution, greppability, and
result-location semantics. Integer literals are `comptime_int` until coerced by assignment or
`@as`. Multiline strings use per-line `\\` tokens, so newlines remain whitespace and lexing can be
line-oriented. Field initialization uses `.field = value`, matching assignment syntax and making
field writes easy to search.

Types are consistently prefix (`?[3]u32`, `*const T`), functions put `fn` next to the name, return
types are mandatory, and short-circuiting boolean control flow is spelled with `and` and `or`
instead of sigils. Zig requires explicit `return`, gives block expressions `void` by default, and
uses labeled `break :label value` when a block must yield a value. This removes much of the
semicolon and expression/statement ambiguity common in neighboring languages.

The most important semantic-syntax idea is that values, types, and patterns share one expression
surface. Generic types look like function calls (`ArrayList(u32)`), type ascription is `@as(T,
value)`, and declaration literals like `.{ .x = 1 }` rely on the expected result type. This lets
Zig have lightweight named/default-argument-like option structs without a separate named-argument
feature.

Style consequences: avoid shadowing, import explicitly, prefer field/method names that are easy to
grep, use `for (0..bound)` instead of `while`-with-increment when possible, and consider safety
counters for loops that "should" terminate. Zig code is pleasant when it keeps the language's
mechanical, searchable nature intact.

### 2025-08-16 - Reserve First

Source: [https://matklad.github.io/2025/08/16/reserve-first.html](https://matklad.github.io/2025/08/16/reserve-first.html)

Fallible allocation in the middle of mutation creates exception-safety bugs. If an operation first
modifies a hash table and then tries to grow a byte buffer, an allocation failure can leave an
uninitialized table entry behind. If a function swaps in new storage and then appends to another
data structure, a later error path can accidentally free the old storage after restoring a pointer
to it. These bugs are easy to write even with careful `errdefer`.

The Zig pattern is reserve first, then mutate without errors. Call every `ensureUnusedCapacity` or
allocation before changing the object, and then mark the transition:

```zig
try table.ensureUnusedCapacity(gpa, 1);
try bytes.ensureUnusedCapacity(gpa, bytes_needed);
errdefer comptime unreachable;

const slot = table.getOrPutAssumeCapacity(key);
bytes.appendSliceAssumeCapacity(data);
```

After the reservation phase, use `AssumeCapacity` operations and make the mutation phase infallible.
This gives strong exception safety for allocation failure: either reservation fails and the object is
unchanged, or mutation runs to completion. For libraries, leave allocation policy to the caller or
test allocation failures aggressively. For applications, seriously consider whether aborting on OOM
is simpler and more honest than pretending every mid-mutation OOM path is correct.

### 2025-11-06 - Error Codes for Control Flow

Source: [https://matklad.github.io/2025/11/06/error-codes-for-control-flow.html](https://matklad.github.io/2025/11/06/error-codes-for-control-flow.html)

Separate error handling from error reporting. Handling means branching on a finite set of recovery
cases; reporting means presenting useful information to a user or operator. Zig's built-in errors
serve the first job: they are strongly typed symbolic error codes in error unions such as
`ReadError!usize`. They are not rich diagnostic objects.

Zig fixes classic C error-code problems with type checking. Error values are out-of-band in error
unions, must be explicitly unpacked with `try` or `catch`, and cannot be silently discarded. The
syntax for ignoring an ordinary value and ignoring an error is intentionally different, so changing
an API from infallible to fallible does not silently lose the new error.

Error sets also document and enforce which errors can flow through an API. A function can return
`error{ReadFailed, EndOfStream}!void`, handle one error locally, and propagate the rest. For
human-facing context, use a separate diagnostics sink or local logging; do not overload the error
code itself with presentation data. Pass `null` diagnostics when the caller wants only control flow,
and pass a sink when the caller wants a report.

### 2025-12-09 - Do Not Optimize Away

Source: [https://matklad.github.io/2025/12/09/do-not-optimize-away.html](https://matklad.github.io/2025/12/09/do-not-optimize-away.html)

Microbenchmarks lie when the compiler proves the work unnecessary or constant-folds the benchmark
inputs. Timing `_ = computation()` can measure nothing if the result is unused. Timing
`computation(1_000_000, 1_000)` can measure a specialized constant expression rather than the code
path users exercise.

Instead of relying first on black-box intrinsics, make benchmark inputs runtime-overridable and make
outputs observable. A practical scaffold is: read parameters from environment variables with
compile-time defaults, print the chosen parameters, accumulate a cheap hash or checksum of results,
and print that hash with the elapsed time. Because the input might come from runtime environment,
the compiler cannot assume one constant. Because the result contributes to printed output, the
computation cannot be deleted wholesale.

The checksum has a second benefit: it catches human "optimizations" that break correctness. If a
change makes the benchmark faster but changes the hash unexpectedly, you probably optimized away
required work. Treat benchmarks as tests with timings attached, not as isolated timing loops.

### 2025-12-23 - Newtype Index Pattern In Zig

Source: [https://matklad.github.io/2025/12/23/zig-newtype-index-pattern.html](https://matklad.github.io/2025/12/23/zig-newtype-index-pattern.html)

In performance-sensitive Zig, prefer typed indexes over pointers for many internal graph and tree
structures. A 32-bit index is smaller than a 64-bit pointer, improves cache density, makes
serialization and relocation natural, and avoids recursive pointer chains that invite stack
overflow. Indexes also model cycles and parent/child relationships without nullable pointer knots.

The Zig idiom for a typed index is a non-exhaustive enum with an integer backing type:

```zig
const Node = enum(u32) {
    root = 0,
    invalid = std.math.maxInt(u32),
    _,
};
```

This is "`u32`, but a distinct type." Convert explicitly with `@intFromEnum` and `@enumFromInt`.
The boundary is not fully encapsulated because anyone can call `@enumFromInt`, so this pattern is
about clear types and convention, not language-enforced privacy.

Model the collection first, such as `Tree`, and nest the index and payload types inside it:
`Tree.Node` and `Tree.Node.Data`. Store all payloads in arrays, use `.invalid` or `?Node` deliberately
for missing relationships, and add `comptime assert(@sizeOf(Data) == N)` when size matters. The API
usually reads cleanly as `tree.parent(node)` and `tree.children(node)`, with the tree owning storage
and the node acting as a typed coordinate.

### 2026-02-11 - Programming Aphorisms

Source: [https://matklad.github.io/2026/02/11/programming-aphorisms.html](https://matklad.github.io/2026/02/11/programming-aphorisms.html)

When Zig removes ambient IO capabilities, functions that used to read global environment variables
need explicit inputs. The good design is not to thread an optional environment map through every
business function. Raise the abstraction level: define an options struct that contains the direct
behavioral choice, then provide a constructor that derives those options from the environment at the
edge.

For example, prefer `readHistory(io, gpa, HistoryOptions{ .file = ... })` plus
`HistoryOptions.from_environment(env)` over `readHistory(io, gpa, maybe_env, maybe_path)`. This
keeps the core function configurable without knowing how configuration is discovered. The shortcut
constructor intentionally crosses layers for convenience, but the core API remains direct and
testable.

The signature style is the important Zig aphorism. Positional arguments are dependencies or
resources with canonical names and distinct types, such as `io`, `gpa`, and file handles. Behavioral
knobs are named fields in an `Options` struct. Use `gpa` when the allocator is general purpose,
`arena` when allocations share a lifetime, and `scratch` when memory must not escape.

### 2026-04-20 - 256 Lines or Less: Test Case Minimization

Source: [https://matklad.github.io/2026/04/20/test-case-minimization.html](https://matklad.github.io/2026/04/20/test-case-minimization.html)

A small finite random number generator can power both randomized testing and test-case
minimization. Instead of an infinite PRNG, keep a slice of entropy bytes. Every generator consumes
from the slice and returns `error.OutOfEntropy` when it runs out. Running out of entropy is not a
test failure; it simply means the generated scenario ended.

The Zig patterns are compact: a file can be the struct (`const FRNG = @This()`), fixed-size arrays
can be derived from slices when a `comptime` size is known, `anytype` plus `std.meta.FieldEnum` can
turn a weights struct into a typed action enum, and `inline for` can iterate fields at compile
time. Returning indexes instead of pointers from random choice helpers keeps APIs const-polymorphic
and works for parallel arrays.

The minimization trick is that entropy length measures scenario complexity. If a 16 KiB entropy
slice finds a bug, try smaller slices. A separate driver process can generate deterministic entropy
from `(size, seed)`, feed it to the system under test on stdin, and treat crashes or nonzero exits
as failures. Search for the smallest failing size and report `(size, seed)` as a reproducible
counterexample. This is especially useful in Zig because assertions abort rather than unwind, so the
searcher should live outside the crashing process.

### 2026-05-03 - Minimal Viable Zig Error Contexts

Source: [https://matklad.github.io/2026/05/03/zig-error-context.html](https://matklad.github.io/2026/05/03/zig-error-context.html)

Zig's error traces are useful for programmers, but often miss the domain value that makes a failure
actionable, such as which file path failed to open. A full diagnostics sink is the robust production
solution, but it can be too heavy for scripts and small tools. The minimal middle ground is to add
context with `errdefer` at the scope where the context is known.

The lightweight pattern is:

```zig
fn process_file(io: Io, path: []const u8) !void {
    errdefer log.err("path={s}", .{path});
    const file = try cwd.openFile(io, path, .{});
    defer file.close(io);
}
```

This keeps the happy path readable, avoids custom prose for every `try`, and lets multiple stack
frames add telescoping `key=value` context. A caller might add `operation=sync`, the callee might
add `path=data.txt`, and the final trace still contains the original error code.

The caveat is serious: `errdefer` logs even if an error is later handled. That is wrong for errors
such as cancellation that are expected control flow. Use this pattern for script-like boundaries or
errors that will escape to reporting; use diagnostics sinks or explicit catch blocks when errors may
be recovered from.

### 2026-05-08 - Steering Zig Fmt

Source: [https://matklad.github.io/2026/05/08/steering-zig-fmt.html](https://matklad.github.io/2026/05/08/steering-zig-fmt.html)

`zig fmt` is intentionally steerable. It does not merely guess a layout; it uses small syntactic
signals already in the file. The most common signal is the trailing comma. Without a trailing comma,
a call can collapse to one line. With a trailing comma, it expands to one argument per line.

Use that as a normal editing workflow: decide the shape, add or remove commas, run the formatter.
Good formatting is not just line wrapping; it is also blank lines between logical blocks and
well-chosen intermediate variables. The formatter should finish the mechanical layout after the
programmer chooses the semantic shape.

Arrays have an extra steering mechanism: the first line break can choose columnar grouping. For
command arguments or table-like data, combine array concatenation with formatter alignment:

```zig
try run(&(.{ "aws", "s3", "sync", path, url } ++ .{
    "--include",            "*.html",
    "--metadata-directive", "REPLACE",
    "--cache-control",      "max-age=0",
}));
```

The takeaway is to make layout decisions explicit in syntax rather than fight the formatter.

## TigerBeetle Blog Takeaways

The TigerBeetle Atom feed was checked on 2026-05-10. The feed contained 30 posts through
`2026-04-24-toolchain-horizons`; the notes below cover the posts whose lessons transfer directly
to Zig programming, TigerStyle systems programming, testing, or correctness engineering. News,
fundraising, lecture announcements, Rust-specific dependency/toolchain work, general process notes,
and domain-history posts were intentionally skipped.

### 2026-04-14 - Automation That Screams Joy

Source: [https://tigerbeetle.com/blog/2026-04-14-automation-screams-joy](https://tigerbeetle.com/blog/2026-04-14-automation-screams-joy)

Automation should live with the system it automates, use the same language when practical, and be
bootstrapped by the same repository-local toolchain. Treat deployment, maintenance, and operational
scripts as production code: they should be reviewed with the main codebase, typechecked by the main
compiler, and able to reuse project libraries instead of reimplementing parsers, retry logic, or
configuration handling in shell.

The concrete Zig pattern is to make the repository self-sufficient. A host script can do only the
minimum needed to clone or update the repo, fetch the pinned Zig binary, and run a Zig-built command:
`./zig/zig build -Drelease scripts -- cfo --timeout=30m`. After that, orchestration can be normal
Zig code under `src/scripts`, built by `build.zig`, using the same formatter, tests, and review
rules as the rest of the project.

This is not only aesthetic. Shell glue accumulates hidden ambient state: installed packages,
working-directory assumptions, orphaned child processes, and untyped stringly APIs. Zig automation
can give operations explicit inputs, structured errors, timeouts, process cleanup, and testable
subroutines. Keep the bootstrap layer tiny; put the real policy in Zig.

### 2026-03-19 - A Trillion Transactions

Source: [https://tigerbeetle.com/blog/2026-03-19-a-trillion-transactions](https://tigerbeetle.com/blog/2026-03-19-a-trillion-transactions)

Scale is a correctness and recovery problem, not only a throughput number. A system that handles a
large steady-state workload but takes too long to recover from restart, compaction, rebalancing, or
replica catch-up is not actually scaled for production. When designing Zig services, include
recovery paths, bounded queues, replay costs, snapshot costs, and worst-case state size in the
original design instead of treating them as after-the-fact operations work.

The TigerStyle lesson is to make every component bounded so the whole system can survive unbounded
time and workload. Fixed-capacity data structures, explicit admission control, batching limits,
bounded repair work, and deterministic replay all turn "maybe it grows" into an engineering number.
In Zig, those numbers should appear as constants, field sizes, array capacities, protocol limits,
and compile-time assertions, not as comments.

For code review, ask the scale question as "what is the maximum here, and how does it recover?"
rather than "is it fast on the happy path?" A queue needs a capacity and overload behavior. A log
needs replay bounds. A cache needs invalidation and memory limits. A background job needs a proof
that it can catch up after downtime.

### 2026-02-16 - Index, Count, Offset, Size

Source: [https://tigerbeetle.com/blog/2026-02-16-index-count-offset-size](https://tigerbeetle.com/blog/2026-02-16-index-count-offset-size)

Use names that encode the unit and the inequality. `count` is the number of logical items.
`index` selects one logical item and must satisfy `index < count`. In bytes, `size` is the number
of bytes and `offset` selects a byte position with `offset < size`. Avoid `length` when the unit is
not obvious, because it can mean items, bytes, characters, words, or time.

This convention prevents a common class of Zig bugs: mixing an item index with a byte offset. A
slice of `T` has a `count`; a pointer cast to bytes has a `size`. Converting from items to bytes is
an explicit multiplication by `@sizeOf(T)`. When both forms appear, make both names visible:
`source_count`, `source_index`, `source_size`, `source_offset`. The suffix carries the unit through
the code, including assert messages and reviews.

The same rule applies to views and derived units. If a buffer is interpreted as words, name the
view `source_words` and use `source_word_index` or `source_word_count`. Paired names should line up:
`source_index` with `target_index`, `source_offset` with `target_offset`. The best naming style is
one that makes illegal arithmetic look suspicious before the compiler gets involved.

### 2025-11-28 - A Tale Of Four Fuzzers

Source: [https://tigerbeetle.com/blog/2025-11-28-tale-of-four-fuzzers](https://tigerbeetle.com/blog/2025-11-28-tale-of-four-fuzzers)

Fuzzability starts at the API boundary. A component whose public API takes a giant service object,
talks to the clock, allocates internally, or reads ambient state is harder to fuzz than one whose
API takes small values and returns explicit results. Design core Zig components so a test can drive
them with integers, enums, slices, `Instant` values, and fixed buffers. Put integration with the
larger runtime one layer outside that core.

A good fuzzer should cover different spaces deliberately. One fuzzer can exhaust or heavily sample
valid encodings. Another should live near invalid encodings and boundaries: truncated buffers,
wrong tags, impossible lengths, duplicate fields, maximum counts, and nearly valid byte strings.
Pure randomness is often too sparse, so bias generation toward edge cases while still keeping random
seeds for surprise.

Make fuzzers self-checking. Count which semantic cases they hit, assert that the important buckets
are nonzero, and keep a deterministic seed in CI so coverage regressions are visible. A fuzzer that
only waits for crashes may quietly stop exercising a branch after a refactor. Treat coverage of the
input space as one of the fuzzer's properties.

### 2025-11-06 - The Write Last, Read First Rule

Source: [https://tigerbeetle.com/blog/2025-11-06-the-write-last-read-first-rule](https://tigerbeetle.com/blog/2025-11-06-the-write-last-read-first-rule)

When a workflow updates multiple systems without a shared transaction, designate the system of
record and order effects around it. Write the system of record last, after all referenced or
derived systems have accepted the change. On reads, consult the system of record first to decide
whether the operation exists at all, then read the supporting systems.

This creates a recoverable boundary. If the process crashes before the final write, the operation is
not visible as committed and can be retried. If it crashes after the final write, recovery sees the
operation in the record and can finish or verify derived effects. Zig code should express this with
small idempotent steps, durable operation identifiers, and explicit status transitions rather than a
large function that performs side effects in arbitrary order.

The rule is especially important for durable execution and job processors. Every step after the
last checkpoint may run more than once, so repeats must be harmless. Use idempotency keys, compare
stored state before writing, and make "already done" a success case. The final record write is the
point where outside observers are allowed to believe the operation exists.

### 2025-10-21 - Tracking Time Without Clock

Source: [https://tigerbeetle.com/blog/2025-10-21-clockless-time](https://tigerbeetle.com/blog/2025-10-21-clockless-time)

Most code does not need a clock object. If a function only needs the current time once, pass
`now: Instant` as an argument. That makes tests deterministic, removes ambient dependencies, and
keeps the function honest about whether it observes time. The caller decides which clock is
appropriate and when the observation happens.

If a component needs to notice that time has advanced, prefer a `tick()` style API before adding a
clock dependency. The outer event loop can call `tick(now)` periodically. The component can compare
`now` to its deadlines and emit work. This keeps scheduling policy outside the component and avoids
mock-clock plumbing in ordinary tests.

Only introduce a clock abstraction when the component genuinely owns time sampling across multiple
moments. Even then, keep the abstraction narrow: return a typed `Instant`, distinguish wall-clock
and monotonic semantics, and make tests able to drive time without sleeping. Direct calls to
`std.time` deep inside business logic are a hidden input and should be treated like hidden IO.

### 2025-06-06 - Fuzzer Blind Spots (Meet Jepsen!)

Source: [https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen](https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen)

Randomized tests can be too well structured. If the generator builds only neat scenarios that match
the implementation's indexing strategy, the test may never ask the awkward question that a real
client or external verifier asks. In the TigerBeetle case, a query bug survived multiple fuzzers
because the generated data made matching records consecutive in indexes; Jepsen used less tidy
workloads and found the gap.

The fix is not to abandon fuzzing. The fix is to pair structured generators with unstructured or
adversarial ones, and to check exact outputs against a reference model. A fuzzer that only asserts
"no crash" or "some invariant still holds" can miss wrong answers. For query-like code, build a
simple model that scans all data and returns the expected result, then compare ordering, filtering,
limits, and boundary behavior exactly.

When reviewing a Zig fuzzer, ask what assumptions the generator bakes in. Does it create keys in
sorted order? Does it avoid overlaps? Does it always close transactions cleanly? Does it mirror the
implementation's data layout? A fuzzer should include cases that are natural for users, not only
cases that are natural for the data structure.

### 2025-05-26 - Asserting Implications

Source: [https://tigerbeetle.com/blog/2025-05-26-asserting-implications](https://tigerbeetle.com/blog/2025-05-26-asserting-implications)

Write implication assertions as control flow:

```zig
if (a) assert(b);
```

This is clearer than compressing the logic into `assert(!a or b)`. The `if` form names the trigger
condition first, gives the consequence its own line, and leaves room to add a better assertion
message, local variable, or debugging code later. It also avoids making every reader mentally
translate boolean algebra back into a precondition.

This style scales to more complicated invariants. If a flag is set, assert the fields that must be
valid under that flag. If a count is nonzero, assert that the pointer or index range is present. If
a state is `.prepared`, assert the prepared-only fields. The important part is to show the shape of
the invariant directly in code.

### 2025-04-23 - Swarm Testing Data Structures

Source: [https://tigerbeetle.com/blog/2025-04-23-swarm-testing-data-structures](https://tigerbeetle.com/blog/2025-04-23-swarm-testing-data-structures)

Zig comptime reflection can make "every public operation is tested" an executable property. Derive
an enum from the public declarations of the type under test, then drive a property test by randomly
selecting one of those operations. If a new public method is added, the switch over actions becomes
non-exhaustive or the weights table becomes incomplete, and the test fails until the new method is
included.

The pattern is especially useful for mutable data structures such as queues, maps, and intrusive
lists. Keep a simple reference model next to the real structure. For each random action, update
both, then compare observable state. Use per-action weights so tests can emphasize operations that
create interesting states without forgetting rare operations. In Zig, `std.meta.DeclEnum(T)` and
`std.enums.EnumFieldStruct(Action, u64, null)` are enough to build this style without a custom test
framework.

The deeper lesson is that reflection should remove maintenance holes, not add cleverness for its
own sake. A hand-maintained random-action enum silently goes stale. A comptime-derived enum ties the
test surface to the API surface, which is exactly the relationship the test is trying to protect.

### 2025-02-27 - Why We Designed TigerBeetle's Docs from Scratch

Source: [https://tigerbeetle.com/blog/2025-02-27-why-we-designed-tigerbeetles-docs-from-scratch](https://tigerbeetle.com/blog/2025-02-27-why-we-designed-tigerbeetles-docs-from-scratch)

Use `build.zig` for project-specific tooling, not only for compiling the main binary. Documentation
generation, asset processing, code generation, schema checks, and release packaging can be modeled
as build steps with explicit inputs and outputs. That gives the project one entry point for local
and CI automation, while keeping the dependency graph visible to Zig's build system.

The docs-site lesson transfers well to any generated artifact. Keep source files in a simple,
durable format such as Markdown or raw text. Use strong external tools when they are the right
parser or renderer, but fetch them as pinned, hashed, lazy dependencies instead of relying on a
developer's global installation. Then have `build.zig` run those tools incrementally so unchanged
inputs do not rebuild the world.

Generated output should be treated as a product of declared inputs, not as a mysterious side effect.
When a build step writes HTML, code, snapshots, or documentation indexes, make the source files,
templates, tool versions, and command-line options explicit. Reproducibility is easier to preserve
when the build script owns the whole pipeline.

### 2025-02-13 - A Descent Into the Vortex

Source: [https://tigerbeetle.com/blog/2025-02-13-a-descent-into-the-vortex](https://tigerbeetle.com/blog/2025-02-13-a-descent-into-the-vortex)

Deterministic simulation testing is powerful, but it should not be the only integration test. A
simulator that mocks IO and runs in one process can reproduce failures perfectly, while still
missing bugs in real process management, client bindings, TCP behavior, kernel interaction, or
operating-system scheduling. Add an outside-in harness that runs production binaries and real
clients, then injects faults around them.

The Vortex pattern is a useful complement: a supervisor starts replicas and clients, a workload
driver issues operations, and a fault layer perturbs the system by pausing, killing, restarting, or
partitioning processes. This is intentionally less deterministic than the simulator, but it tests
different boundaries. It exercises the exact binary, command-line flags, networking setup, and
language bindings a user will run.

For Zig systems, design the executable so it can be driven this way. Configuration should be
explicit, logs should include operation IDs and enough context for diagnosis, and shutdown/restart
paths should be normal code paths rather than special cases. A test harness cannot explore faults
that the program has no way to observe or report.

### 2024-12-19 - Enum of Arrays

Source: [https://tigerbeetle.com/blog/2024-12-19-enum-of-arrays](https://tigerbeetle.com/blog/2024-12-19-enum-of-arrays)

When processing many tagged-union values, consider batching by tag instead of storing one tag per
element. An ordinary array of tagged unions is flexible, but every element carries a tag, payload
layout must accommodate the largest variant, and loops branch per item. An enum-of-arrays layout
stores one tag for a whole batch and a union whose payload is a slice of the corresponding variant
payloads.

This is the tagged-union equivalent of struct-of-arrays thinking. If the operation naturally
processes many `.insert` records, many `.delete` records, or many `.transfer` records at a time,
represent the batch in that shape. The branch moves from "per element" to "per batch", payloads are
dense, padding is reduced, and the compiler has more room to vectorize or specialize the hot loop.

Do not use this everywhere. If operations are genuinely interleaved item by item, an array of enums
may be the honest model. Use enum-of-arrays when the API or protocol already admits batching by
kind, or when a preprocessing step can group work without changing semantics.

### 2024-05-14 - Snapshot Testing For the Masses

Source: [https://tigerbeetle.com/blog/2024-05-14-snapshot-testing-for-the-masses](https://tigerbeetle.com/blog/2024-05-14-snapshot-testing-for-the-masses)

Snapshot tests are most useful when the snapshot is a first-class value, not a magic file path
hidden inside a test framework. In Zig, a snapshot can carry `@src()` plus the expected text. A
helper can compare actual output against the snapshot, print a useful diff, and optionally update
the source literal when the change is accepted.

This makes snapshots composable. A test helper can take `want: Snapshot`, generate output in many
ways, and call `diff`, `diff_fmt`, or `diff_json` depending on the output type. The call site still
shows the expected value next to the test inputs, so review sees the behavior change in the same
patch as the code change.

Use snapshots for outputs that are too structured or verbose for hand-written asserts: rendered
diagnostics, parser trees, CLI output, generated configuration, or protocol traces. Keep them
stable by normalizing nondeterminism such as paths, timestamps, random IDs, or map iteration order.
A snapshot that changes for irrelevant reasons teaches reviewers to ignore it.

### 2023-12-27 - It Takes Two to Contract

Source: [https://tigerbeetle.com/blog/2023-12-27-it-takes-two-to-contract](https://tigerbeetle.com/blog/2023-12-27-it-takes-two-to-contract)

A contract involves both sides of a boundary. Do not put all preconditions in the callee and assume
callers will discover them. Assert the expectation at the call site where the relevant local facts
are visible, and assert it again in the callee where the boundary is enforced. The duplication is
intentional: it catches bugs earlier and documents both halves of the agreement.

In Zig, this means using `assert` for impossible states and `defer assert(...)` for postconditions.
For example, a caller that slices a buffer can assert the range before the call; the callee can
assert the received slice has the length and alignment it requires. When either assertion fires,
the failure points at the side that had enough information to prevent the violation.

The same idea applies beyond functions. Sender and receiver can both assert message sizes, tags,
checksums, and sequence numbers. Writer and reader can both assert on-disk invariants. Producer and
consumer can both assert queue ownership. Paired assertions are an airlock around a boundary: each
side states what it believes, and mismatches fail close to their source.

### 2023-09-19 - 64-Bit Bank Balances 'Ought to be Enough for Anybody'?

Source: [https://tigerbeetle.com/blog/2023-09-19-64-bit-bank-balances-ought-to-be-enough-for-anybody](https://tigerbeetle.com/blog/2023-09-19-64-bit-bank-balances-ought-to-be-enough-for-anybody)

Money should be modeled as integer quantities of the smallest relevant unit, never as floating
point. The unit may be cents, satoshis, basis points, or an asset-specific scale; the important part
is that arithmetic is exact and range-checked. Floating point introduces rounding behavior that is
usually wrong for ledgers and difficult to audit.

TigerBeetle's broader lesson for Zig is to choose numeric widths from domain lifetime and scale,
not from what feels large today. A signed 64-bit balance loses usable range quickly when assets have
many fractional digits, accounts live for years, and systems aggregate across currencies or
customers. `u128` amounts and balances leave more headroom, and modern compilers lower many 128-bit
integer operations to acceptable machine code on 64-bit hardware.

Also avoid signed balances when the domain has separate debit and credit semantics. Store positive
debits and positive credits as separate quantities, then derive the presentation balance at the
edge. This removes a class of sign bugs and makes invariants such as "debits posted equal credits
posted" easier to express.

### 2023-07-26 - Copy Hunting

Source: [https://tigerbeetle.com/blog/2023-07-26-copy-hunting](https://tigerbeetle.com/blog/2023-07-26-copy-hunting)

Hidden copies are often visible in LLVM IR even when they are not obvious in Zig source. Compile a
small reproduction with `zig build-lib -femit-llvm-ir`, then search the `.ll` for large `memcpy`
calls. If a hot loop unexpectedly copies whole structs, the IR will usually show it.

The classic Zig source-level fix is to iterate by pointer when the element is large:

```zig
for (items) |*item| {
    use(item);
}
```

Using `|item|` copies the element into the loop capture; using `|*item|` gives a pointer to the
element in place. The difference matters for large records, arrays inside structs, and hot
comparison loops. Similar issues can appear in generic helpers that accept values by copy when a
pointer or slice would preserve locality.

IR inspection is not premature optimization when it is targeted. Start from a benchmark or profile,
reduce the suspicious operation to a small exported function so the compiler emits it, then inspect
whether the generated code matches the source-level intent. The point is to find the accidental
copy, not to read every line of IR.

### 2023-07-11 - We Put a Distributed Database In the Browser - And Made a Game of It!

Source: [https://tigerbeetle.com/blog/2023-07-11-we-put-a-distributed-database-in-the-browser](https://tigerbeetle.com/blog/2023-07-11-we-put-a-distributed-database-in-the-browser)

Deterministic simulation becomes more valuable when it is portable and replayable. TigerBeetle's
simulator replaces real IO, network, storage, and clocks with controlled components, so a failure
can be reproduced from a seed and a trace. Compiling that simulator to WebAssembly makes the system
inspectable in a browser, but the key lesson is the same for native Zig tests: isolate the core from
ambient OS effects so tests can control the universe.

This requires architecture work. The code under test must receive IO, time, randomness, and storage
through explicit interfaces. It must tolerate time dilation, dropped messages, restarts, disk
faults, and replay. Memory use must be bounded enough that the same core can run under constrained
targets such as WebAssembly.

The payoff is that a complex distributed failure becomes a concrete artifact: seed, version, input
trace, and visualization. That artifact can be minimized, reviewed, and replayed by another
developer. A test that explains the failure is worth more than a log that merely says something
went wrong.

### 2023-07-06 - Simulation Testing For Liveness

Source: [https://tigerbeetle.com/blog/2023-07-06-simulation-testing-for-liveness](https://tigerbeetle.com/blog/2023-07-06-simulation-testing-for-liveness)

Safety and liveness need different simulation modes. A safety simulator can inject faults forever
and assert that bad states never happen. That does not prove the system eventually makes progress,
because the test may keep the system in an unrealistically hostile world where progress is
impossible.

A liveness simulator should first explore a random faulty prefix, then choose a viable core quorum,
heal that core, freeze disruptive failures outside it, and run long enough to require progress. The
assertion is not merely "nothing broke"; it is "the surviving core completed work." This finds bugs
such as permanent asymmetric partitions, resonance between timers, or recovery code that is safe
but never converges.

For Zig services, make progress observable. Expose commit counters, durable operation numbers, or
other monotonic state that a harness can check. Liveness testing cannot work if the only visible
result is absence of a crash.

### 2023-03-28 - Random Fuzzy Thoughts

Source: [https://tigerbeetle.com/blog/2023-03-28-random-fuzzy-thoughts](https://tigerbeetle.com/blog/2023-03-28-random-fuzzy-thoughts)

Treat randomness as finite input, not as an infinite hidden stream. A finite PRNG backed by a byte
slice can return `error.OutOfEntropy` when the test input is exhausted. That bridges
coverage-guided fuzzing and property testing: the fuzzer mutates bytes, while the test consumes
those bytes as structured choices. The input length becomes a useful measure of scenario
complexity, and minimizers can shrink failing cases by shrinking the entropy.

For replay, record enough to reconstruct the run. A seed and commit are often enough for ordinary
random tests, but they are brittle across generator changes. For long-lived interesting cases,
persist the generated scenario or a higher-level trace. For interactive simulations, record
predicate keyframes such as "replica 2 is partitioned" or "client request X is pending" rather than
only raw timestamps.

Random testing works best when it is boring to rerun. Print the seed, size, and any reduced input.
Make command-line flags accept those values. Keep crash reports small enough that a developer can
run one failing scenario locally without waiting for the full fuzzing infrastructure.

### 2023-02-21 - Writing High-Performance Clients for TigerBeetle

Source: [https://tigerbeetle.com/blog/2023-02-21-writing-high-performance-clients-for-tigerbeetle](https://tigerbeetle.com/blog/2023-02-21-writing-high-performance-clients-for-tigerbeetle)

When multiple language clients wrap one protocol, put the performance-critical and correctness-
critical core in one implementation and expose it through narrow FFI boundaries. TigerBeetle uses a
Zig client core behind Java, .NET, Go, and Node.js bindings so protocol logic, batching,
serialization, and threading behavior are not reimplemented differently in each ecosystem.

FFI design should preserve memory shape. Zero-copy or low-copy APIs require contiguous buffers,
stable layouts, and clear ownership. The wrapper language may need to adapt with direct byte
buffers, pinned memory, or explicit conversion at the edge, but the core should not depend on
language-specific object graphs. Keep callbacks clear: if the Zig core invokes a completion on an
internal thread, the wrapper must not block that thread and should hand work off to the language's
normal async mechanism.

The same pattern applies inside one Zig program. Put the hard protocol in a small core with explicit
buffers and callbacks. Let adapters translate to CLI, HTTP, test harnesses, or language bindings.
That keeps the core fast, testable, and reusable.

### 2022-11-23 - A Programmer-Friendly I/O Abstraction Over io_uring and kqueue

Source: [https://tigerbeetle.com/blog/2022-11-23-a-friendly-abstraction-over-iouring-and-kqueue](https://tigerbeetle.com/blog/2022-11-23-a-friendly-abstraction-over-iouring-and-kqueue)

A good IO abstraction should expose completion semantics without leaking every platform detail to
business logic. Build a central dispatcher that accepts operations with a callback and context,
submits them to the platform backend, and later invokes the callback with the result. On Linux the
backend may be `io_uring`; on BSD or macOS it may be `kqueue`; the higher-level code should see
the same shape.

Fixed-capacity submission queues need explicit overflow behavior. If the kernel queue is full, put
pending operations in an application-owned overflow queue instead of allocating ad hoc or failing
randomly. Intrusive lists are a natural Zig fit: the operation object can carry its queue node, so
the dispatcher does not allocate a wrapper per IO request.

Keep progress explicit. A `flush` or event-loop step can submit queued work, poll completions, and
run callbacks. Tests can then drive IO by repeatedly calling the event loop and controlling the
backend. This style fits Zig's preference for visible dependencies: the code that performs IO
receives an IO object, and pure logic does not.

### 2022-10-12 - A Database Without Dynamic Memory Allocation

Source: [https://tigerbeetle.com/blog/2022-10-12-a-database-without-dynamic-memory](https://tigerbeetle.com/blog/2022-10-12-a-database-without-dynamic-memory)

Avoiding dynamic allocation after startup is a design discipline, not a micro-optimization. Decide
the maximum number of connections, replicas, in-flight messages, queries, buffers, and other
resources. Allocate the memory for those capacities at startup. Then run the main service without
calling an allocator in the hot path.

Zig's standard library supports this style if you choose the right APIs. Reserve capacity up front,
then use methods such as `addOneAssumeCapacity` or `putAssumeCapacityNoClobber` in code that should
not fail from allocation. Pair them with assertions and tests so capacity assumptions are checked at
the boundary. If a function does not receive an allocator, reviewers can see that it cannot allocate
through normal Zig collection APIs.

The cost is that overload behavior must be designed. Static allocation does not make resource
exhaustion disappear; it makes it explicit. Decide whether to reject new work, apply backpressure,
drop a cache entry, or close a connection. That decision belongs in product logic and tests, not in
the allocator failing unexpectedly halfway through an update.

### 2021-08-30 - Three Clocks are Better than One

Source: [https://tigerbeetle.com/blog/2021-08-30-three-clocks-are-better-than-one](https://tigerbeetle.com/blog/2021-08-30-three-clocks-are-better-than-one)

Time APIs must distinguish wall-clock time from elapsed time. Wall-clock time answers "what date is
it?" and can jump due to NTP, leap seconds, operator changes, or VM migration. Stopwatch time
answers "how much time elapsed?" and should be monotonic for deadlines and timeouts. Using the wrong
clock turns rare environment events into correctness bugs.

Even monotonic clocks have platform semantics. On Linux, a monotonic clock may stop during system
suspend, while a boot-time clock includes suspended time. A timeout for a network request, lease, or
replica failure detector may need suspend-aware elapsed time; a CPU benchmark probably does not.
Pick the semantic clock first, then map it to the platform API.

Distributed systems need redundancy around time. Do not trust one local clock blindly when the
protocol depends on clock bounds. Use multiple sources where appropriate, detect outliers, and make
clock uncertainty part of the design. In Zig code, reflect that distinction with types such as
`Instant`, `Duration`, and domain-specific clock wrappers instead of passing raw integers.

## Synthesized Best Practices

### Resource and Allocation Design

Pass allocators explicitly and only to operations that can allocate. This makes allocation visible
in function signatures and lets hot paths prove they cannot allocate by not having an allocator.
Prefer `gpa`, `arena`, and `scratch` names to communicate lifetime and ownership expectations.

Separate reservation from mutation. Do all fallible allocation first with `ensureUnusedCapacity`,
then switch to `AssumeCapacity` mutation and use `errdefer comptime unreachable` to ensure no new
error path appears after the reservation phase. For larger systems, consider reserving all resources
at startup and running the main loop without allocation.

Design overload behavior together with capacity. Static allocation and reserve-first APIs are not
complete until the code says what happens when capacity is exhausted: reject new work, apply
backpressure, evict cache entries, or close connections. Allocation failure in the middle of a
multi-index update should not be the policy.

Batch memory work. Use unmanaged collections when the allocator is supplied at call sites, reserve
capacity in chunks, and push loops down into APIs so a batch insert can allocate once and update
data structures coherently. When a service must run for years, include recovery, replay, and
catch-up costs in the capacity model, not only steady-state throughput.

### Types, Indexes, and Data Layout

Use Zig's nominal anonymous types deliberately. Bind important types to names, use nested types to
show ownership (`Tree.Node`, `Node.Data`), and use non-exhaustive integer enums for typed IDs and
indexes.

Prefer indexes to pointers for dense, serializable, cyclic, or long-lived graph-like data. Store
payloads in arrays, use ranges to represent child lists, and make size expectations executable with
`comptime assert(@sizeOf(T) == N)`.

Name units explicitly. Use `index` and `count` for logical items, `offset` and `size` for bytes, and
derived suffixes such as `_word_index` when a buffer is viewed in another unit. Avoid vague names
like `length` when byte-vs-item confusion would be expensive.

For tagged unions, keep the representation flat when that is best globally. When one local handler
needs grouped variants, use `inline` switch prongs plus `comptime unreachable` to get compiler
checked partial matching without refactoring the whole type. When work is naturally batched by tag,
consider an enum-of-arrays layout so the branch happens once per batch and payloads stay dense.

Choose numeric ranges from domain lifetime and scale. For money and ledgers, use integer quantities
of a chosen smallest unit, avoid floats, and consider `u128` for amounts and balances when 64-bit
range would be consumed by fractional scales or long-lived aggregation.

### Comptime and Metaprogramming

Use `comptime` as specialization over ordinary values, not as source-code generation. Prefer
type/value constructors, `inline for`, `@field`, `@TypeOf`, `@typeInfo`, and `std.meta` when they
produce a real simplification at the API boundary.

Keep comptime-heavy interfaces small and explicit. Zig does not have declaration-site checking for
every future instantiation, so complex comptime code can fail late and be hard to understand. Avoid
reflection unless it buys type safety, performance, or a much smaller public API.

Remember the boundaries: no host leakage, no arbitrary eval, no custom syntax, no runtime types
unless you reify them yourself, no generated methods on user types, and no comptime IO. Use
`build.zig` for build-time IO and code generation.

Use comptime reflection to remove real maintenance gaps. A property test that derives its action
enum from a data structure's public declarations can fail when a new public method lacks test
coverage. That is a better use of reflection than making an ordinary API more magical.

### Error Handling and Reporting

Treat Zig errors as typed control-flow codes. Use explicit error sets at API boundaries when the
set matters, handle a subset locally, and propagate the rest with `try`. Do not make the symbolic
error carry user-facing context.

Report context out-of-band. For production parser/compiler-style APIs, pass a diagnostics sink. For
small tools or script-like code, add `errdefer log.err("key={}", .{value})` around a block of related
fallible work. Avoid that logging pattern when the error may be intentionally handled.

Use `errdefer comptime unreachable` as a proof marker after the last possible error, especially in
reserve-first code and multi-index updates.

### Contracts, Time, and External Effects

Assert contracts on both sides of important boundaries. The caller should assert the facts it knows
before the call, and the callee should assert the conditions it requires after crossing the
boundary. Apply the same pattern to sender/receiver, writer/reader, and producer/consumer pairs.

Write implication assertions as control flow: `if (condition) assert(consequence);`. This is more
readable than boolean algebra inside one `assert`, and it leaves space for local variables or
targeted diagnostics.

Make IO, time, randomness, and durable effects explicit. If code only needs the current time once,
pass `now: Instant`; if it needs periodic progress, expose `tick(now)`; if it performs IO, pass an
IO dispatcher. Hidden calls to `std.time`, global randomness, or ambient system state make tests and
simulation harder.

When composing effects without a shared transaction, choose the system of record. Write it last so
partial work is not externally committed, read it first so absent operations stay absent, and make
retry after crash idempotent.

### Style and API Shape

Lean into Zig's searchable syntax. Prefer explicit imports, clear field names, no shadowing, and
field updates spelled in greppable ways. Put behavioral options in an `Options` struct; keep
dependencies/resources positional.

Let result-location semantics work for you. Use `.{}` and `.variant` where the destination type is
obvious, but use `@as` when a reader would not know the type either. Use small option structs for
named/default arguments.

Steer `zig fmt` with trailing commas, blank lines, and array layout instead of hand-aligning code
against the formatter. The formatter is part of the style contract.

Keep automation in the repository. A tiny bootstrap script may fetch the pinned Zig binary, but the
real deployment, documentation, code generation, and release logic should be Zig code built by
`build.zig` where it can be reviewed, tested, and reused.

### Testing, Benchmarking, and Tooling

For randomized tests, make generated input reproducible by seed and small enough to minimize.
Finite entropy turns "random scenario" size into a search parameter, and an external driver can
minimize crash-inducing inputs even when the Zig process aborts.

Do not let fuzzers become too polite. Pair structured generators with adversarial and less-ordered
inputs, and compare exact outputs against a simple reference model when the code answers queries or
transforms data. Assert that the fuzzer still reaches important semantic buckets.

Split simulation goals. Safety mode can keep injecting faults and assert that bad states never
happen; liveness mode should eventually heal a viable core and require observable progress. Add
outside-in tests with real binaries and clients to cover process, network, and FFI boundaries that
deterministic simulators intentionally mock.

Use snapshots for verbose structured output, but keep them close to the test inputs and normalize
nondeterminism. A snapshot should make review easier by showing behavior, not harder by changing for
irrelevant reasons.

For benchmarks, make inputs runtime-overridable and outputs observable. Print parameters and a
result hash so the compiler cannot erase the work and so wrong optimizations are caught.

For performance investigations, reduce the suspicious operation and inspect generated artifacts when
source-level reasoning is not enough. LLVM IR is a practical way to catch accidental large copies,
especially from by-value loop captures or generic helpers.

Keep project tooling local. Bootstrap the right `zig` into `./zig`, run commands through that
binary, and avoid relying on global shell or package-manager state. The fewer ambient assumptions,
the more reproducible the project.

## Quick Checklist

- Pass `gpa`, `arena`, `scratch`, and `io` explicitly; do not hide ambient dependencies.
- Reserve all needed capacity before mutating shared or multi-index data structures.
- After reservation, use `AssumeCapacity` operations and `errdefer comptime unreachable`.
- Decide overload behavior for every fixed capacity.
- Prefer typed `enum(u32) { _ }` indexes over raw `u32` or pointers for dense internal graphs.
- Use `index/count` for items and `offset/size` for bytes.
- Keep allocation out of hot loops by not passing an allocator there.
- Batch by tag with enum-of-arrays when operations are naturally grouped by variant.
- Model money with integer units, not floats; use enough width for lifetime scale.
- Use diagnostics sinks for rich reports and `errdefer key=value` context for small tools.
- Do not put user-facing reporting data into Zig error codes.
- Use `inline for` for compile-time-known structure over runtime values.
- Avoid comptime reflection unless it buys a clear API or performance win.
- Use reflection to keep property-test action sets in sync with public APIs.
- Use explicit error sets at public boundaries when callers need stable control-flow cases.
- Assert cross-boundary contracts at both caller and callee.
- Prefer `if (a) assert(b)` for implication invariants.
- Pass `now: Instant` or expose `tick(now)` instead of hiding clock reads.
- Write the system of record last, read it first, and make retries idempotent.
- Use trailing commas to tell `zig fmt` whether a construct should expand vertically.
- Keep serious automation in Zig under `build.zig`; keep shell bootstraps tiny.
- Make benchmark inputs runtime-overridable and print a result hash.
- For fuzzing/PBT, record enough data to replay: seed, size, commit, or minimized bytes.
- Check exact outputs against a reference model, not only "no crash" invariants.
- Test both safety and liveness; progress must be observable.
- Use outside-in harnesses to test real binaries, clients, process faults, and network faults.
- Use snapshots for verbose output and normalize nondeterministic fields.
- Inspect LLVM IR when a benchmark suggests hidden large copies.
- Vendor the Zig version choice into the repository and invoke `./zig/zig`.
