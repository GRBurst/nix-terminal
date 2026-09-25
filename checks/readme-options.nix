# The README's option table and the option tree cannot drift: every leaf
# option under `programs.terminalKit` is named in the first cell of a row
# of the `## Options` table, and every name there is a leaf option. Names
# are backticked and relative to `programs.terminalKit`; one row may name
# several options (e.g. the tools).
{
  pkgs,
  lib,
  self,
  options,
}: let
  leaves = prefix: tree:
    lib.concatLists (lib.mapAttrsToList (
        n: v: let
          p = prefix ++ [n];
        in
          if lib.isOption v
          then [(lib.concatStringsSep "." p)]
          else if lib.isAttrs v
          then leaves p v
          else []
      )
      tree);
  want = leaves [] options.programs.terminalKit;

  lines = lib.splitString "\n" (builtins.readFile "${self}/README.md");
  # the lines from `## Options` up to the next level-2 heading
  from = lib.drop (lib.lists.findFirstIndex (l: l == "## Options") (lib.length lines) lines + 1) lines;
  section = lib.take (lib.lists.findFirstIndex (lib.hasPrefix "## ") (lib.length from) from) from;
  rows = lib.filter (lib.hasPrefix "| ") section;
  firstCell = row: lib.elemAt (lib.splitString "|" row) 1;
  # the odd pieces of a split on "`" are the backticked names
  ticked = s: let
    parts = lib.splitString "`" s;
  in
    map (i: lib.elemAt parts i) (lib.filter (i: lib.mod i 2 == 1) (lib.range 0 (lib.length parts - 1)));
  named = lib.concatMap (r: ticked (firstCell r)) rows;

  missing = lib.subtractLists named want;
  unknown = lib.subtractLists want named;
  problems =
    lib.optional (section == []) "README.md has no `## Options` section"
    ++ lib.optional (missing != []) "options missing from the README table: ${toString missing}"
    ++ lib.optional (unknown != []) "README table names that are no leaf option: ${toString unknown}";
in
  pkgs.runCommand "readme-options" {} (
    if problems == []
    then "touch $out"
    else "printf '%s\\n' ${lib.escapeShellArg "readme-options: ${lib.concatStringsSep "; " problems}"} >&2; exit 1"
  )
