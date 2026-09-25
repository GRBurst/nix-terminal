# R13, P6. The closure of the template configuration's activation package
# holds no GUI toolkit and no X11/Wayland clipboard tool. Names are compared
# exactly: the package name (pname) is parsed from each store path's name
# (hash stripped, cut before the first `-<digit>`, as parseDrvName does), so
# `gtk+3-3.24.49-dev` is `gtk+3`, while `gtk4-layer-shell-1.0` is not `gtk4`.
# Such a name that only starts with a forbidden one is printed as info.
# Every offender is printed with a shortest referrer chain from the root.
{
  pkgs,
  lib,
  Ct,
}: let
  root = Ct.home.activationPackage;
  forbidden = ["gtk+3" "gtk4" "qtbase" "xclip" "wl-clipboard" "wl-clipboard-rs" "xsel"];
in
  pkgs.runCommand "closure-hygiene" {
    exportReferencesGraph = ["graph" root];
    nativeBuildInputs = [pkgs.gawk];
  } ''
    # graph: per path, the path, its deriver, the reference count, the references.
    gawk -v root=${root} -v forbidden=${lib.escapeShellArg (toString forbidden)} '
      function pname(p,  b) {
        b = p; sub(/^.*\//, "", b); sub(/^[0-9a-z]{32}-/, "", b)
        if (match(b, /-[0-9]/)) b = substr(b, 1, RSTART - 1)
        return b
      }
      function chain(p,  s) {
        s = pname(p)
        while (p != root) { p = parent[p]; s = pname(p) " -> " s }
        return s
      }
      st == 0 { cur = $0; seen[cur] = 1; st = 1; next }
      st == 1 { st = 2; next }
      st == 2 { n = $0 + 0; st = n ? 3 : 0; next }
      st == 3 { refs[cur] = refs[cur] " " $0; if (--n == 0) st = 0; next }
      END {
        split(forbidden, fl, " "); for (j in fl) isForbidden[fl[j]] = 1
        if (!(root in seen)) { print "closure-hygiene: root " root " not in the graph" > "/dev/stderr"; exit 1 }
        # breadth-first from the root: parent[] gives a shortest chain
        q[1] = root; head = 1; tail = 1; reached[root] = 1
        while (head <= tail) {
          p = q[head++]; m = split(refs[p], r, " ")
          for (i = 1; i <= m; i++) if (!(r[i] in reached)) { reached[r[i]] = 1; parent[r[i]] = p; q[++tail] = r[i] }
        }
        bad = 0; total = 0; sawZsh = 0
        for (p in reached) {
          total++; name = pname(p); if (name == "zsh") sawZsh = 1
          for (j in fl) {
            if (name == fl[j]) { print "closure-hygiene: " fl[j] " in the closure: " chain(p) > "/dev/stderr"; bad = 1 }
            else if (!(name in isForbidden) && index(name, fl[j]) == 1) print "closure-hygiene: info: " name " (near " fl[j] ", allowed): " chain(p) > "/dev/stderr"
          }
        }
        # the parser must see the closure it checks
        if (total < 100 || !sawZsh) { print "closure-hygiene: parsed " total " paths, zsh " (sawZsh ? "seen" : "not seen") "; the graph was not read" > "/dev/stderr"; bad = 1 }
        print "closure-hygiene: " total " paths checked" > "/dev/stderr"
        exit bad
      }
    ' graph
    touch $out
  ''
