# hexseq
This is a zig tool to seq files in a dir with a three digit ascii extension. FFF

# Zig version 0.14.0


# building 
```console
zig build
```

# testing

Some test require temp files to be in place. So before running our test we need to run

```console
$ ./test_setup.sh
```
After running this script then run 

```console
zig build test
```
