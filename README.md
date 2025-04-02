# hexseq
This is a zig tool to seq files in a dir with a three digit ascii extension. FFF

By default hexseq will rollover the log dir once any one file reaches .FFF. If no
directory is given with the --rollover=move <path>, the default is to rename the dir 
given with the same hex extension.

e.g. If I pass in /var/log and a file reaches .FFF it will rollover the log directory 
into /var/log.000 ... log.FFF (If you make it that far IDK)

# Zig version 0.14.0

# Running 
Example of how to run the program

```console
hexseq -d --logdir /var/dlogs/
```

Capture the output
```console
hexseq -d --logdir /var/dlogs/ 2&> hexseq.log
```

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

# Should be done
[] Make it so the program can dected how many log dirs there are for rollover. By default it's hardcoded
   to just add .000 instead of looking. -- Can be over come by passing --rollover=move <path>