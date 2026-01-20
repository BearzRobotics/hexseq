
# Intro
This program is a simple command-line log roller. It recursively processes every
file in a given directory (including all subdirectories) and renames them by appending a three-digit hexadecimal extension.

This was the first program I wrote in Zig, originally for my uncle to manage his log files. While learning the master branch with the new Zig IO interface, I am porting it to the current project.

Behavior

You point hexseq to the root directory.

Every file in that directory and all nested subdirectories will be affected.

Each file will be renamed by appending .000 (or the next available hex sequence in a full implementation).

Only files are renamed — directories are left untouched.

Example

Before:

logs/
  |- loga.log
  |- logb
  |- xorg/
      |- logc


After running the log roller:

logs/
 |-  loga.log.000
 |- logb.000
 |-  xorg/
     |- logc.000

From zero based index this supports up to 4095 backups of a file

# Documentation

All documentation lives in the `docs/` folder in Markdown format. All pull requests must indicate whether they introduce changes that require documentation.

Use the following tag in your pull request description:

`Documentation Needed: [yes/no]`

If documentation is needed, it must be included in the same pull request.

We recommend using glow as the terminal Markdown viewer for this project. It renders Markdown beautifully in the command line, preserving bold text, tables, code blocks, and syntax highlighting — making it easy to read .mb documentation files for each utility.

See the official repository: https://github.com/charmbracelet/glow

Usage Example

To view the documentation for a single utility:

glow docs/cp.mb

# Building & Installing

Get the Zig compiler either from the [official site](https://ziglang.org/download/) or using a package manager like [zvm](https://github.com/tristanisham/zvm).

**Zig version required:** 0.16.0-dev.2255+d417441f4 or greater

```sh
git clone <repository-url>
cd coreutils-utils
zig build
```

if you want to build the smallest possible build, instead of running zig build the following:

```sh
mkdir -pv zig-out/bin/
zig build-exe src/main.zig -O ReleaseSmall -dead_strip -fstrip -fno-unwind-tables -femit-bin=zig-out/bin/hexseq
```

To install, copy the programs in `zig-out/bin/` to your desired location. Currently, it is **not recommended** to replace the system versions in `/usr/bin`.

# Projects That Inspired This

* [https://github.com/chimera-linux/chimerautils](https://github.com/chimera-linux/chimerautils)
* [https://busybox.net/](https://busybox.net/)
* [https://www.gnu.org/software/coreutils/](https://www.gnu.org/software/coreutils/)
* [https://www.gnu.org/software/findutils/](https://www.gnu.org/software/findutils/)
* [https://www.gnu.org/software/sed/](https://www.gnu.org/software/sed/)
* [https://www.gnu.org/software/grep/](https://www.gnu.org/software/grep/)
* [https://landley.net/toybox/](https://landley.net/toybox/)
