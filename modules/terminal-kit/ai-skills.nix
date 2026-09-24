# Third-party agent skills, linked into the shared cross-tool skills tree plus
# the one harness that does not read it (D13: links only -- no harness
# settings, environment variables, packages or aliases).
#
# ~/.agents/skills is the documented user-tier discovery path for opencode, pi,
# codex and agy; for agy the `.agents/skills` alias even takes precedence over
# ~/.gemini/skills. One tree for four harnesses, and it is also where a harness
# pack legitimately drops its own skill, so a private tree per harness would
# diverge from what those tools already do.
#
# claude-code is the sole exception: its personal tier is only
# ~/.claude/skills/<name>/SKILL.md. Anthropic documents that a <skill-name>
# ENTRY there may be a symlink which claude-code follows, de-duplicating by
# target -- so per-skill entries bridge the gap. Deliberately not a symlinked
# ~/.claude/skills DIRECTORY: that would revoke claude-code's own write access
# to the directory it watches.
#
# Linking into both trees rather than adding ~/.claude/skills to the other
# harnesses' search order is deliberate: opencode requires skill names to be
# unique across all locations it scans.
#
# DRY: `skills` is the single representation of the selection; it is rendered
# twice below (symlinks, existence assertions) and read by the checks
# `ai-skills-links` and `ai-skills-inventory`. Adding a skill is one entry and
# nothing else.
{
  config,
  lib,
  terminalKitInputs,
  ...
}: let
  cfg = config.programs.terminalKit;
  inputs = terminalKitInputs;

  # $HOME-relative skills directories every skill is linked into. A private
  # `let` rather than an option: adding a discovery path is a repo change, not a
  # host choice. Two entries serve four harnesses -- see the header.
  skillDirs = [
    ".agents/skills"
    ".claude/skills"
  ];

  # obra/superpowers ships a flat skills/<name>/SKILL.md tree. Linked
  # all-or-nothing: the bodies cross-reference siblings as `superpowers:<name>`
  # and the referenced set is a subset of the 14 below, so any strict subset
  # leaves an agent told to invoke a skill no harness can find.
  #
  # Enumerated literally rather than derived with `builtins.readDir` on
  # purpose: a skill is instruction text injected into every agent session, so
  # an input bump must not silently add one. Upstream drift in either direction
  # fails the check `ai-skills-inventory`, which is where the readDir listing
  # lives -- as an assertion, not as the source.
  superpowersNames = [
    "brainstorming"
    "dispatching-parallel-agents"
    "executing-plans"
    "finishing-a-development-branch"
    "receiving-code-review"
    "requesting-code-review"
    "subagent-driven-development"
    "systematic-debugging"
    "test-driven-development"
    "using-git-worktrees"
    "using-superpowers"
    "verification-before-completion"
    "writing-plans"
    "writing-skills"
  ];

  superpowersSkills =
    lib.genAttrs superpowersNames
    (name: "${inputs.superpowers}/skills/${name}");

  names = lib.attrNames cfg.aiSkills.skills;

  links =
    lib.concatMap (
      name:
        map (dir: {
          name = "${dir}/${name}";
          value.source = cfg.aiSkills.skills.${name};
        })
        skillDirs
    )
    names;
in {
  config = lib.mkIf (cfg.enable && cfg.aiSkills.enable) {
    # An upstream restructure must break evaluation rather than leave a dangling
    # symlink that the harness then silently skips. `builtins.pathExists` on an
    # already-realised store path is not import-from-derivation.
    assertions =
      map (name: {
        assertion = builtins.pathExists "${cfg.aiSkills.skills.${name}}/SKILL.md";
        message = "ai skill '${name}' has no SKILL.md at ${cfg.aiSkills.skills.${name}}; the upstream input was probably restructured.";
      })
      names;

    # Curated baseline. Defined here rather than as the option `default` because
    # for `attrsOf` a default is REPLACED, not merged: putting these in
    # `default` would mean a consumer writing `skills.foo = ...` silently drops
    # them. Defining them in `config` makes consumer definitions merge.
    #
    # Neither repository root is a skill directory -- the SKILL.md files are
    # nested this deep, and linking a root would put nothing at depth 1.
    programs.terminalKit.aiSkills.skills =
      {
        xp-clean-code = "${inputs.xp-clean-code}/plugins/xp-clean-code/skills/xp-clean-code";
        karpathy-guidelines = "${inputs.karpathy-skills}/skills/karpathy-guidelines";
      }
      // superpowersSkills;

    home.file = lib.listToAttrs links;
  };
}
