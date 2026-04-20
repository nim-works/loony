switch("threads", "on")
switch("threadAnalysis", "off")
switch("define", "nimAllocStats")

# make system.delete strict for index out of bounds accesses.
switch("define", "nimStrictDelete")

switch("deepcopy", "on")

# Dot-like operators (operators starting with `.`, but not with `..`)
# now have the same precedence as `.`, so that `a.?b.c` is now parsed as
# `(a.?b).c` instead of `a.?(b.c)`.
switch("define", "nimPreviewDotLikeOps")

# Enable much faster "floating point to string" operations that also
# produce easier-to-read floating point numbers.
switch("define", "nimPreviewFloatRoundtrip")

#switch("define", "nimArcDebug")
#switch("define", "traceCollector")
#switch("define", "nimArcIds")

# default to enable debugging for now
switch("define", "loonyDebug")
# Now that I've added a counter for node allocations should this be disabled
# by default?
