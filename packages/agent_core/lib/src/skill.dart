/// The skill library — what an agent can do, as the bridge reads it.
///
/// A skill is a SKILL.md file on both platforms (Hermes stores them as
/// `learning.frames` nodes; OpenClaw as files in `workspace/skills/`), which
/// is what makes a shared model possible at all. See `SKILLS_BRIDGE.md`.
library;

import 'package:meta/meta.dart';

/// One skill, as one agent sees it.
///
/// The bridge's row. [key] is the cross-backend identity (the skill name /
/// skillKey) — two agents' copies of one skill share it and cluster together;
/// [nativeId] is the per-backend address (a Hermes learning node id, or an
/// OpenClaw slug / directory). [content] is the SKILL.md when the backend can
/// serve it: Hermes always, OpenClaw only for registry-published skills, and
/// then the registry copy rather than the installed file.
@immutable
class SkillEntry {
  const SkillEntry({
    required this.key,
    required this.title,
    required this.backendId,
    required this.nativeId,
    this.description = '',
    this.eligible = true,
    this.detail = '',
    this.content,
    this.filePath,
  });

  /// The cross-backend key: skill name / skillKey, matched after
  /// case-and-whitespace normalisation.
  final String key;

  /// What to show. The backend's display name when it has one, else the key.
  final String title;

  /// Which agent this copy belongs to — `AgentBackend.id` (`'hermes'` /
  /// `'openclaw'`).
  final String backendId;

  /// One backend's address for it: a learning node id, or a slug / directory.
  final String nativeId;

  /// One line about what it does.
  final String description;

  /// Whether this agent can actually use it. Hermes: always true (a learned
  /// skill is by definition loadable); OpenClaw: the gateway's `eligible`
  /// verdict, which folds in every reason it might not run.
  final bool eligible;

  /// Why it is off, in the backend's own words ("missing bin: gh", "needs
  /// EXA_API_KEY", "disabled in config"). Empty when eligible.
  final String detail;

  /// The SKILL.md, when readable from this client. Null when it is not.
  final String? content;

  /// Where the installed file lives. OpenClaw only.
  final String? filePath;

  SkillEntry copyWith({String? content}) => SkillEntry(
        key: key,
        title: title,
        backendId: backendId,
        nativeId: nativeId,
        description: description,
        eligible: eligible,
        detail: detail,
        content: content ?? this.content,
        filePath: filePath,
      );

  @override
  String toString() => 'SkillEntry($key, $backendId, eligible: $eligible)';
}

/// One skill, and every agent's copy of it.
///
/// The unit the skills panel is built from: a row that says *this skill
/// exists* and *these agents have it*. "What does Hermes have that OpenClaw
/// does not" is then [missingFrom], not a separate query.
@immutable
class SkillCluster {
  const SkillCluster({required this.key, required this.entries});

  /// The normalised key the copies share.
  final String key;

  /// Every agent's copy, in the order the agents were read.
  final List<SkillEntry> entries;

  Set<String> get backends => {for (final e in entries) e.backendId};

  /// The copy to show: the one with the fullest description wins.
  SkillEntry get best => entries
      .reduce((a, b) => b.description.length > a.description.length ? b : a);

  /// Which of [connected] have no copy of this skill.
  ///
  /// Takes the connected set rather than assuming two backends: a user with
  /// one server connected must not be told every skill is "missing from" a
  /// server that is not there.
  Set<String> missingFrom(Set<String> connected) =>
      connected.difference(backends);

  bool get isShared => backends.length > 1;

  @override
  String toString() => 'SkillCluster($key, ${backends.join("+")})';
}

/// Groups [entries] into one cluster per skill.
///
/// The key is the skill name / skillKey, normalised only for case and
/// whitespace. The memory bridge's rule applies: a duplicate is visible and
/// annoying, a wrong merge silently discards. Skills are read-only and lower
/// stakes, but near-misses (`web-search` vs `exa-search`) must still stay
/// apart rather than being joined by a fuzzy guess.
List<SkillCluster> clusterSkills(List<SkillEntry> entries) {
  final grouped = <String, List<SkillEntry>>{};
  for (final entry in entries) {
    final key = entry.key.trim().toLowerCase();
    grouped.putIfAbsent(key, () => []).add(entry);
  }
  return [
    for (final group in grouped.entries)
      SkillCluster(key: group.key, entries: group.value),
  ];
}
