# GoPacker

Go packer is a Perl (v5.10 or newer) script that enables you to pack static
data required by your server in a constant data structure linked in with your
code. The result is one binary that contains all external file dependencies,
and all static data gets served from memory.

# Usage

A server example is presented in [``gopacker-example.go``](gopacker-example.go).
Files from ``static/`` are first packed with [``gopack.pl``](gopack.pl), which
creates ``gopack.go`` that is going to be linked in with your code on
``go build``.  [``Makefile``](Makefile) list all build steps: run ``make all``.

You have to declare ``static_data map[string]([]byte)`` in your "main" package,
and initialize it with ``GetFileMap()``. Files from ``static/`` are stored in
``static_data`` map (e.g. content of ``static/index.html`` is in
``static_data["/static/index.html"]``).

# License

[MIT license](LICENSE.txt).
