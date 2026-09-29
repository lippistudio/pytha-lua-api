"""Minimal Lua 5.3 interpreter based on the Python package "lupa".

Used by run_tests.sh when no lua5.3 binary is installed:
    pip install lupa
    python3 lua53.py script.lua [args ...]
"""
import sys

try:
    from lupa import lua53
except ImportError:
    sys.stderr.write("lupa is not installed: pip install lupa\n")
    sys.exit(2)


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: lua53.py script.lua [args ...]\n")
        return 2
    lua = lua53.LuaRuntime(unpack_returned_tuples=True)
    make_arg = lua.eval("function(...) arg = { ... } end")
    make_arg(*sys.argv[1:])
    lua.execute(
        "local script = table.remove(arg, 1)\n"
        "arg[0] = script\n"
        "local chunk = assert(loadfile(script))\n"
        "chunk(table.unpack(arg))\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
