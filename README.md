# hexseq
This is a zig tool to seq files in a dir with a three digit ascii extension. FFF

# Zig version 0.14.0


# building 
```console
zig build
```

# Release build
You have three optoions for release builds
small, fast, and safe

These all produce widly different binary sizes

```console
zig build --release=small
```

--release=small	Optimize for binary size (aggressively 
                removes unused code, more inlining, less debug info)

--release=safe	Optimize for safety (keeps runtime checks
                like integer overflow, bounds checking, etc.)

--release=fast	Optimize for speed (turns off most runtime safety 
                checks, prioritizes raw performance)

# testing

```console
zig build test
```
