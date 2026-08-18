/// Grouping two agents' skill libraries into one row per skill.
///
/// The skills bridge's whole comparison is a key match, and the memory
/// bridge's rule applies: a duplicate is visible and annoying, a wrong merge
/// silently discards. These pin what joins and what stays apart.
library;

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

SkillEntry _skill(String key, String backend, {String description = ''}) =>
    SkillEntry(
      key: key,
      title: key,
      backendId: backend,
      nativeId: key,
      description: description,
    );

void main() {
  test('the same skill on two agents is one cluster', () {
    final clusters = clusterSkills([
      _skill('tavily', 'openclaw', description: 'search the web'),
      _skill('tavily', 'hermes', description: 'web search via Tavily'),
    ]);

    expect(clusters, hasLength(1));
    expect(clusters.single.isShared, isTrue);
    expect(clusters.single.backends, {'openclaw', 'hermes'});
    // The fullest description is the one worth reading.
    expect(clusters.single.best.description, 'web search via Tavily');
  });

  test('the key is matched after case and whitespace normalisation', () {
    final clusters = clusterSkills([
      _skill('GitHub', 'hermes'),
      _skill(' github ', 'openclaw'),
    ]);

    expect(clusters, hasLength(1));
  });

  test('near-miss names stay apart rather than being fuzzy-joined', () {
    // `web-search` and `exa-search` are different skills. Joining them on
    // similarity would hide the fact that one agent lacks the other's skill.
    final clusters = clusterSkills([
      _skill('web-search', 'hermes'),
      _skill('exa-search', 'openclaw'),
    ]);

    expect(clusters, hasLength(2));
  });

  test('missingFrom names only the backends that are missing it', () {
    final cluster = clusterSkills([
      _skill('github', 'hermes'),
    ]).single;

    expect(cluster.missingFrom({'hermes', 'openclaw'}), {'openclaw'});
    // A user with one server is never told a skill is "missing from" a server
    // they have never set up.
    expect(cluster.missingFrom({'hermes'}), isEmpty);
  });

  test('an empty library yields no clusters', () {
    expect(clusterSkills(const []), isEmpty);
  });
}
