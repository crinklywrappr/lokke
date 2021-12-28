
Compilation
-----------

The current approach is to let the Scheme macro-expansion process act
as the primary compiler just as it does for Guile itself.  It's
unclear whether or not this is the approach we'll want to keep.

The Scheme compiler compiles from Scheme to the next level down in the
[compiler tower](https://www.gnu.org/software/guile/manual/html_node/Compiler-Tower.html)
which is tree-il.  We explicitly invoke the Scheme compiler in an
environment (which is a Guile module, which is a Clojure namespace)
that has macros defined that implement much of Clojure when expanded.

After that expansion, we walk the tree-il representation in order to
rewrite normal `(x ...)` calls as `(invoke x ...)`, where `invoke` is
a generic function that has specializations allowing it to handle
Clojure's "invocable" instances, e.g. `(:foo #{bar})` becomes `(invoke
:foo #{bar})`, `([1 2 3] 2)` becomes `(invoke [1 2 3] 2)`, etc.  Once
the final tree-il code is ready, we return it to Guile for compilation
or execution via the lower levels of language tower.

The compilation process uses some symbols starting with `/lokke/` as a
side channel for communication (discussed further below), which should
be fine since symbols staring with "/" are illegal in Clojure itself
(and at least unreadable in Clojure on the JVM).

Clojure's "compound" (namespaced) symbols like `clojure.string/join`
present another wrinkle.  Currently these symbols are left alone at
the Clojure and Scheme levels, and then a final pass over the tree-il
code rewrites any remaining, namespaced, top-level references as
[Guile module references](https://www.gnu.org/software/guile/manual/html_node/Using-Guile-Modules.html),
e.g. `clojure.string/join` effectively becomes `(@ (lokke ns clojure
string) join)`.

Since the core of the compiler is the macroexpander, it must be able
to traverse and expand all of the appropriate literal structures.  For
Scheme that primarily means being able to traverse lists, but Clojure
requires that we also traverse literal hash-maps, hash-sets, and
vectors, i.e. `[(some-macro x)]` must expand `some-macro` at compile
time.

To support that, those literals are always represented to the compiler
as pseudo-function invocations like `(/lokke/reader-hash-map metadata
kvs ...)` and `(/lokke/reader-hash-set metadata x ...)`, which the
macroexpander can traverse.  The reader creates this representation
when invoked via `read-for-compiler`, and the `metadata` will either
be #nil or a `(/lokke/reader-hash-map kvs ...)` derived from any
reader metadata preceding the literal, say via `^{:x 1} [1]`.

These pseudo-functions present a problem for Clojure syntax expanders
(created with the Clojure side `defmacro`) since those expanders
expect to see actual hash-maps and hash-sets.  So before a form is
passed to one of them, all of the pseudo-function calls are
transformed into the Clojure instances they represent, and then, once
the expander has returned its expansion, any instances in the result
are transformed back to the corresponding pseudo-function calls.

That is, `#{foo}` will be an actual `hash-set` instance containing the
symbol `foo` whenever it is encountered by Clojure code during
compilation, for example whenever a Clojure defmacro expander sees it,
but it will be `(/lokke/reader-hash-set #nil foo)` whenever it is
encountered by the Scheme syntax expander.

In part, we've started with this approach because we wanted to try
relying on the normal Scheme macroexpander for compilation (as Guile's
Scheme dialect does), so that, among other things, we can use hygienic
macros (i.e. define-syntax), and their pattern matching when feasible.

This is another choice that may or may not turn out to be desirable in
the long run, and even if we don't decide to purse a completely
independent compiler, perhaps we'll end up wanting to rewrite the
macros to be able to handle/match Clojure data structures directly.
Though that could make them notably more complicated and might
preclude the simpler syntax-rules style macros in some cases (as
compared to syntax-case).

To support this domain shifting approach there are two flavors of the
reader functions, one for the compiler, and then the "normal" flavor.
The former produces input suitable for the compiler, including, for
example, the`(/lokke/reader-vector #nil 1 2 3)` style forms instead of
native Clojure instances.  The latter (the normal reade)r returns
native data structures as you might expect, though of course the
contents will be unevaluated.

The compiler represents lists as scheme lists so that the syntax
expander will handle expansions normally.  The intention is for any
quoted lists to end up compiled to normal Guile const lists (which may
be mmapped and immutable, though possibly only when compiled right
now).

Dynamic variables
-----------------

When a dynamic variable `*out*` is defined via `defdyn`, it is
actually represented by a "hidden" top-level definition `(define
/lokke/dynamic-*out* (make-fluid ...))` in the current Guile module.
Then `foo` itself is made an
[identifier-syntax](https://www.gnu.org/software/guile/manual/html_node/Identifier-Macros.html)
that expands into `(fluid-ref /lokke/dynamic-foo)`.
[Binding conveyance](https://clojure.org/reference/vars#conveyance) is
provided by transferring Guile's
[`current-dynamic-state`](https://www.gnu.org/software/guile/docs/master/guile.html/Fluids-and-Dynamic-States.html).

This raises a question.  How does a form like `binding` locate the
original fluid during expansion when it only sees a variable name like
`*out*` which is bound to the identifier syntax?  Currently, when a
dynamic variable is defined, the fluid is also associated with the
module variable holding the identifier-syntax definition via an
[object-property](https://www.gnu.org/software/guile/manual/html_node/Identifier-Macros.html).
That variable is what is imported into other modules via say
`use-modules`, so `binding` can look up the module variable associated
with `*out*` with
[`module-variable`](https://www.gnu.org/software/guile/manual/html_node/Module-System-Reflection.html),
and then call `(dynamic-fluid var)` on that variable to get the fluid
itself.

Modules and namespaces
----------------------

- Namespaces are Guile modules, but all of the normal infrastructure
  (`ns`, `require`, etc.) expects them to be located underneath
  `(lokke ns)` in the Guile module tree.  So for example `(require
  'clojure.string)` will actually try to find the Guile module `(lokke
  ns clojure string)`.

- Guile's module definitions are normally private unless exported, so
  we arrange for all clojure defs to also export the name in order to
  match Clojure's semantics.

- Currently Clojure namespaces can be written in either Clojure or
  Scheme, though some care must be taken with the latter, and
  namespace lookups will auto-compile (if allowed and if necessary)
  and load the first suitable file found in a directory in the load
  path.  Within each directory in the load path, a compiled ".go" file
  takes precedence when it's newer than a corresponding ".clj" or
  ".scm" file, otherwise a ".clj" file takes precedence over ".scm".

  Currently, if compilation fails, I think Guile itself may fall back
  to an existing (stale) .go file, something we might like to address
  later.

- Guile's module lookups, of course, only search for ".scm" (by
  default, though there is a way to change that).

- Right now, all namespaces starting with `(lokke clojure core)` are
  considered "core" modules, and are treated a bit differently.
  They're considered to be relevant to the bootstrapping process
  (i.e. before clojure.core is ready) and so (for example) their `ns`
  forms do not automatically `refer-clojure` (since no one's likely to
  want an infinite recursion at startup).

Metadata
--------

- Reader metadata is supported for the literals (i.e., [] {} #{}) by
  storing it as the first argument to the literal's pseudo-function
  invocations, e.g. `(/lokke/reader-hash-map metadata ...)`.  The
  `metadata` will either be #nil or a `(/lokke/reader-hash-map ...)`
  derived from any reader metadata preceding the literal, e.g. via
  `^{:x 1} [1]`.

- There is no metadata support for lists because at the moment, they
  may be represented by Scheme lists.  While that makes them very
  efficient and compatible with Scheme, it means that in addition to
  not supporting metadata, they can't be `counted?` or hashed.

  We could consider changing them to a custom persistent type.  Doing
  so may or may not be difficult given the scattered effect of the
  current assumption that lists may just be pairs, and it will require
  some accommodation for passing Clojure lists to Scheme functions,
  even if just via manual conversion.

- We're planning to see if we can avoid supporting metadata for
  some types, symbols being a clear example, or at least making
  support optional, since metadata support would add overhead, and
  introduce  a substantial impedance mismatch with the Scheme side.
  The former because symbols could no longer be simple unique pointers
  (because immutability requires a new object every time the metadata
  changes), and the latter because Clojure and Scheme symbols wouldn't
  have the same representation anymore, affecting all kinds of things,
  likely including the compiler.

Concurrency
-----------

Guile intends to avoid crashes or corruption when executing code in
parallel, but it does not make any guarantees about outcomes without
appropriate synchronization.  From the Guile Reference Manual:

> All libguile functions are (intended to be) robust in the face of
> multiple threads using them concurrently.  This means that there is
> no risk of the internal data structures of libguile becoming
> corrupted in such a way that the process crashes.

> A program might still produce nonsensical results, though.

Lokke currently intends to follow a similar approach.

Value comparisons
-----------------

It looks like it may not be possible to specialize `equal?` (and
perhaps the underlying concern applies to all primitive-generics) for
existing types/arities, i.e. you cannot define a new specialization
for say `(equal? x)` and you cannot define a new specialization for
`(equal?  (x <string>) (y <new-type>))`.

Currently Lokke handles equality by:

  - defining `(equal? x y)` for new types, e.g. hash-map, etc.,
  - defining a `clj=` that falls back to `equal?`,
  - defining `clj=` methods to handle Clojure-specific cases, like `(=
    [1] '(1))`, including fallback definitions for `<sequential>`,
    `<map>`, etc.,
  - defining `clj=` overrides to avoid the fallbacks for comparisons
    of instances of the same concrete type, i.e. `(clj= hash-map-1
    hash-map-2)`,
  - and defining `=` as `clj=` in `(lokke core)` and then exporting it
    (with replacement).

TODO
----

- Avoid auto-compiling top-level commands.  This might mean we need to
  switch back to a shell wrapper (see guile's `guild` handling for
  prior art).

- Make sure the .go files are always installed after their sources.
  See "am/guilec" in the Guile source tree for an example.

- Add `sorted-set-by` and `sorted-map-by` (and then update
  test/clojure-walk)..

- Consider providing `hash` consistency across Clojure and Scheme
  collections, i.e. Scheme vector and Clojure vector, etc., which
  would also require consideration of Guile's tree-depth diminishing,
  partial hashing.

- Propose upstream support for an option to prevent Guile from ever
  falling back to an existing (stale) compiled file when compilation
  fails.  See the Hacking section below for further details.

- File and line numbers are not always handled properly in the reader,
  errors, etc.

- Investigate GOOPS read-only slots -- daviid mentioned that GNOME
  uses them, e.g. <read-only-slot> in gobject/gtype.scm.

- Add doc and attr args to defmacro.

- Review handling of cons pairs.  Right now we use/allow them in
  various places, but for example, doing so doesn't support metadata,
  or hashing (if we need that), and printing cons pairs as clj
  seqs/lists will break for improper lists.  One option might be to
  just shift everything to <pair-seq> or something similar,
  particularly if that won't overly complicate compilation and/or
  macroexpansion (e.g. do we still need the make-pair-seq eval-when
  difference?).

- Consider "read time" instantiation of #"x" literals, given our
  evaluation semantics.

- Implement defmacro `&form` and `&env`?

- Examine [(srfi srfi-45)](https://www.gnu.org/software/guile/manual/html_node/SRFI_002d45.html)
  with respect to lazy seqs.

- Examine [(srfi srfi-171)](https://www.gnu.org/software/guile/manual/html_node/SRFI_002d171.html)
  with respect to transducers.

- Remove vestigial bits from the reader (syntax, synquote, etc.?)

- Create clojure.edn, and then switch lokke.deps, and anything else
  that can, to use it.

- `File` shims plausible, or too much a hack?

- Contemplate eval-when -- do we have it where we need it, does it,
  and/or can it work reasonably from the Clojure side?

- Investigate difference with the JVM for

        `(foo `())

  from the REPL.  If it matters, then along those lines, we may need
  another syntax-quote recursion there (in `quote-empty-lists`), to
  move `()` handling to the tree-il level, or to add a new
  `/lokke/reader-list`, which might end up being desirable for other
  reasons.

- Right now Lokke's `try/catch/finally` very closely follows Guile's
  `catch/throw`, which is Guile's more efficient exception handling
  mechanism, and is based on throwing and catching simple tags
  (symbols) along with arbitrary additional arguments.

  Our `Throwable`, `ExceptionInfo`, etc. are actually just bound to
  uninterned symbols (i.e. guaranteed unique) in `(lokke exception)`,
  and those symbols are what our exception handler (installed via
  guile's `catch`) is looking for.

  In fact, `ex-info` just creates and returns a list containing
  exactly the arguments we need to pass to Guile's `throw`.  So at the
  moment Lokke exceptions aren't objects/records/classes, they're
  `throw` argument lists, and correspondingly, the first element is
  the `catch` tag.  There's a good chance we'll rework everything in
  terms of exception options for Guile 3.0 and newer.

  With respect to Clojure more generally, upstream debate over
  exceptions in the context of cljs suggested that they may really
  want to head toward just being able to throw a data-carrying-object
  and then do something with it -- didn't sound like they were in
  favor of keeping much of the JVM class/hierarchy matching business
  as the non-platform-specific method:
  https://github.com/clojure/clojurescript/wiki/Exception-Handling

  What we have at the moment is more along those lines, in spirit at
  least, and more like Guile's `with-exception-handler`, though we do
  support a small subset of the more common Clojure/JVM behaviors.

  See the [README](README.md) for some additional information.

- I'm still not sure whether the way we're handling the compilation
  environment, via default-environment, bootstrap, (lokke user), etc.,
  is very solid and/or what we really want.  It's notable that the
  Scheme compiler appears to use more anonymous, throwaway
  environments for compilation, but when I tried that there were
  problems (that might or might not have been caused by other bugs).
  For example repeated loads of compiled modules (across heaps) would
  fail on lookups to the anonymous modules -- no fun figuring that
  one out...

- Note that Guile's `--language` argument, i.e. `--language=lokke`
  appears to cause guile to set the reader to lokke universally, which
  breaks `(use-modules ...)`, etc.

- Consider the suitability of a fash delete operation for use in
  hash-map `dissoc` and hash-set `disj` to replace the `not-found`
  hacks.  Right now hash-maps and hash-sets never actually shrink.
  For example, after

        (def x (let [x (hash-set (range 100))
                     x (apply disj x x)]
                     x))

  `x` will still have 100 entries in the underlying fash, all the
  internal `not-found` instance.

- Improve hash-map and hash-set seqs, which may require improvements
  to fash or...

- Stop altering `LTDL_LIBRARY_PATH` to load module libs.  Ludovic
  suggested we might add `GUILE_EXTENSIONS_PATH` to guile (hopefully
  with a parallel `%extensions-path`, which would solve the problem.

- Review our `pr`, `print`, and `str` handling.  We now have a
  `to-string` generic function, mirroring the JVM's `.toString`, for
  `str` to rely on, but our handling of the three operations may not
  be consistent yet.

- Consider adding pr-str methods if the string port overhead becomes
  relevant.

- Settle Scheme side binding vector vs list question and bring code
  into compliance.

  Using `(let [] ...)` from guile is the most similar syntax, but it
  makes the macroexpansion more difficult and/or potentially ambiguous
  (because `[` and `]` are reader equivalent to `(` and `)` in Guile).
  And if we use `(let () ...)`, then it's potentially more confusing
  to a reader that may not realize when we've clobbered Scheme `let`.
  At a minimum `fn`'s syntax may be more ambiguous with lists instead of
  vectors, i.e. `(fn ([x] 0))`.

- Support `TIOCGWINSZ` somehow (likely via C helper) so we can use it
  with fill-string, etc. for documentation output, help, etc.

- Fix up C-side docstrings (e.g. `SCM_DEFINE`).

- Review FIXMEs...
  
- Run some large structure memory tests.

- Fix up source-properties, etc.

- Do we care about `allow-legacy-syntax-objects?`:

> A parameter that indicates whether the expander should support
> legacy syntax objects, as described above.  For ABI stability
> reasons, the default is "#t".  Use "parameterize" to bind it to
> "#f".  *Note Parameters::.

Notes
-----

- A `(@...)` reference inside a function in a module appeared to be
  unconditionally forcing the creation of the referred module, which
  was empty because it was a clojure module (since guile has no idea
  that a .clj file may produce a guile module).  This caused trouble
  because code that checks for the existence of the module
  (i.e. perhaps ns/require), was fooled.  The resulting error was

        no code for module (lokke ns some thing)

  We should perhaps double-check, but in that case, adding/using
  `resolve-ns` instead was the preferable solution.

Hacking
-------

- The scm and clj files are compiled during builds, e.g. via `make`,
  installed via `make install`, and found via `GUILE_LOAD_COMPILED_PATH`
  (cf. `%load-compiled-path`).  Parallel builds are supported so
  something like `make -j5` may speed builds.

- Currently .clj and .scm files will only be compiled if they're
  tracked by git.  i.e. a new file won't be compiled during the build
  until/unless it's been added.

- At the moment `Makefile.am` is autogenerated from `Makefile.am.in`
  to avoid a good bit of tedium, in part with respect to the
  compilation mentioned above.

- For now, all EPL (only) licensed code (e.g. code ported from
  upstream) should go in separate namespaces, e.g. (lokke ns clojure
  walk) or (lokke ns clojure core epl).  Include any changes in the
  [License section of the README](README.md#License).

- When defining syntaxes - note the use of `(expand ...)` functions in
  say (lokke base syntax).  The relevant cases just call a common
  expand(er) to do the work.  That makes sure that the scoping of
  introduced variables will be correct, as compared to what may happen
  if you just redirect one syntax-case to another via recursive
  expansion.

- Guile has no syntax/macro dependency tracking, so changes to a macro
  will not automatically propagate outside the module they're defined
  in.  You can set GUILE_AUTO_COMPILE=fresh to force Guile to
  recompile everything (or you can just find and delete the relevant
  .go files (subtree) in ~/.cache/guile/.

- Current Guile may proceed with no more than a warning while loading
  a module when you might expect it to halt.  It might do that when
  there's an undefined variable or circular dependency (and the
  warning there may only be about a missing definition).  By default
  it will also just fall back to the old compiled code for a module
  (if any) when auto-compilation fails.

- Failing to get the distinctions between `export`, `re-export`,
  `replace`, `re-export-and-replace`, etc. right can produce some
  confusing results with respect to binding definitions/visibility.

- For more diagnostic information (and yes, we definitely need
  something more sophisticated...), there are a few debug settings you
  can set to #t, including:
    - `(language lokke spec)` `debug-lang?`
    - `(lokke base syntax)` `debug-let?` `debug-fn?`
    - `(lokke compile)` `debug-il?`
    - `(lokke reader)` `debug-reader?`

- Functions like `unparse-tree-il` in the `(language tree-il)` module
  may be helpful when debugging issues related to
  [Tree-IL](https://www.gnu.org/software/guile/docs/master/guile.html/Tree_002dIL.html).

- If you want to see where a call is coming from:

        (let ((s (make-stack #t)))
          (display-backtrace s (current-error-port) 0 100))

- "unexpected syntax in form": might mean a `use-modules` is missing
  in the namespace declaring the syntax.

- On the Guile side there are a variety of options for defining
  functions, e.g. those based on `lambda`, `lambda*`, `match-lambda*`,
  or GOOPS methods (at least).

- At the moment in some cases we treat keywords much like symbols.
  cf. the `(lokke symbol)` module.

- An `Unbound variable: x` error during compilation might indicate a
  dependency cycle, i.e. mutually dependent modules.

Sending patches to the list
===========================

As mentioned [elsewhere](README.md#contributing), patches are also
welcome on the [mailing list](README.md#additional-contacts] and must
be ["signed off" by the author](./README.md#contributing) before
official inclusion.

You can create a "signed off" set of patches in ./patches, ready for
submission to the list, like this:

    git format-patch -s -o patches origin/main

which will include all of the patches since origin/main on your
current branch.  Then you can send them to the list like this:

    git send-email --to "~rlb/lokke@lists.sr.ht" --compose patches/*

The use of `--compose` will cause git to ask you to edit a cover letter
that will be sent as the first message.

It's also possible to handle everything in one step:

    git send-email -s --to "~rlb/lokke@lists.sr.ht" --compose origin/main

and you can add `--annotate` if you'd like to review or edit each patch
before it's sent.

For single patches, this might be easier:

    git send-email -s --to "~rlb/lokke@lists.sr.ht" --annotate -n1 HEAD

which will send the top patch on the current branch, and will stop to
allow you to add comments.  You can add comments to the section with
the diffstat (below the "--" without affecting the commit message).

Of course, unless your machine is set up to handle outgoing mail
locally, you may need to configure git to be able to send mail.  See
git-send-email(1) for further details.

<!--
Local Variables:
mode: markdown
End:
-->
