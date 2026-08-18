/// Turning OpenClaw's markdown into memory entries.
///
/// A parser, tested as one — no socket. The failure mode here is not a crash
/// but a memory attributed to the wrong heading, or silently dropped, and that
/// is found by feeding it awkward markdown rather than by mocking a gateway.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MEMORY.md', () {
    test('one entry per heading, with the heading as the title', () {
      const file =
          '# Memory\n\n'
          '## Coffee\n'
          'Drinks it black. Never after 3pm.\n\n'
          '## Editor\n'
          'Uses Zed, not VS Code.\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries.map((e) => e.title), ['Memory', 'Coffee', 'Editor']);
      expect(entries[1].text, 'Drinks it black. Never after 3pm.');
      expect(entries.every((e) => e.kind == MemoryKind.fact), isTrue);
    });

    test('prose with no headings is one entry, not nothing', () {
      // A memory file someone wrote by hand is an ordinary thing to have.
      // Dropping it would be the worst kind of bug in a feature about
      // remembering.
      const file = 'Prefers short answers.\nDislikes being called "user".\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries, hasLength(1));
      expect(entries.single.title, isEmpty);
      expect(entries.single.text, contains('Prefers short answers.'));
      expect(
        entries.single.label,
        'Prefers short answers.',
        reason: 'an untitled entry still needs something to show in a row',
      );
    });

    test('an empty file yields nothing rather than one empty entry', () {
      expect(clawMemoriesFromMarkdown(''), isEmpty);
      expect(clawMemoriesFromMarkdown('   \n\n'), isEmpty);
    });

    test('a heading inside a fenced block does not split the entry', () {
      // Splitting here would cut a shell script in half and file the two
      // pieces as unrelated memories.
      const file =
          '## Deploy runbook\n'
          'Run this:\n\n'
          '```bash\n'
          '## not a heading\n'
          'make deploy\n'
          '```\n\n'
          'Then check the logs.\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries, hasLength(1));
      expect(entries.single.title, 'Deploy runbook');
      expect(entries.single.text, contains('make deploy'));
      expect(entries.single.text, contains('Then check the logs.'));
    });

    test('a longer fence is not closed by a shorter one inside it', () {
      const file =
          '## Example\n'
          '````markdown\n'
          '```\n'
          '## still not a heading\n'
          '```\n'
          '````\n';
      expect(clawMemoriesFromMarkdown(file), hasLength(1));
    });

    test('ids are distinct even when two headings are identical', () {
      // Two entries sharing an id is how a later phase deletes the wrong one.
      const file = '## Notes\nfirst\n\n## Notes\nsecond\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries, hasLength(2));
      expect(
        entries.map((e) => e.id).toSet(),
        hasLength(2),
        reason: 'a duplicated id makes a later diff delete the wrong entry',
      );
    });

    test('the origin names the backend and how it addresses the entry', () {
      const file = '## Coffee\nblack\n';
      final entry = clawMemoriesFromMarkdown(file).single;

      expect(entry.origin.backendId, 'openclaw');
      expect(entry.origin.nativeId, 'MEMORY.md#coffee');
      expect(entry.origin.isLedger, isFalse);
    });

    test('a CJK heading keeps its characters in the id', () {
      // Slugging to ASCII would collapse every Chinese heading to the same
      // empty string, and then to the same fallback ordinal.
      const file = '## 咖啡\n黑咖啡\n\n## 编辑器\nZed\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries.map((e) => e.origin.nativeId).toSet(), hasLength(2));
      expect(entries.first.origin.nativeId, contains('咖啡'));
    });

    test('the timestamp is carried onto every entry', () {
      final at = DateTime(2026, 8, 1);
      final entries = clawMemoriesFromMarkdown(
        '## A\nx\n\n## B\ny\n',
        updatedAt: at,
      );
      expect(entries.map((e) => e.updatedAt), everyElement(at));
    });
  });

  group('persona documents', () {
    // Verbatim from the live gateway: this is what a workspace ships with,
    // and it is what would have been shown as "what the agent knows about
    // you" if the template check did not exist.
    const shippedUserDoc =
        '# USER.md - About Your Human\n\n'
        "_Learn about the person you're helping. Update this as you go._\n\n"
        '- **Name:**\n'
        '- **What to call them:**\n'
        '- **Pronouns:** _(optional)_\n'
        '- **Timezone:**\n'
        '- **Notes:**\n\n'
        '## Context\n\n'
        '_(What do they care about? What projects are they working on?)_\n';

    test('an untouched template is not offered as knowledge', () {
      expect(clawDocumentIsTemplate(shippedUserDoc), isTrue);
      expect(clawPersonaEntry('USER.md', shippedUserDoc), isNull);
    });

    test('a template with one line deleted is still a template', () {
      // A checksum of the original would call this "learned". The test is the
      // unfilled fields, because that is what actually means nothing was said.
      final edited = shippedUserDoc.replaceFirst('- **Timezone:**\n', '');
      expect(clawDocumentIsTemplate(edited), isTrue);
    });

    test('a filled-in document is offered, whole', () {
      const filled =
          '# USER.md - About Your Human\n\n'
          '- **Name:** Jaden\n'
          '- **What to call them:** Jaden\n'
          '- **Timezone:** Asia/Shanghai\n\n'
          '## Context\n\n'
          'Builds a Flutter client for two agent gateways.\n';
      final entry = clawPersonaEntry('USER.md', filled);

      expect(entry, isNotNull);
      expect(entry!.kind, MemoryKind.persona);
      expect(entry.title, 'USER.md');
      expect(
        entry.text,
        contains('Builds a Flutter client'),
        reason: 'a persona document is one entry holding the whole file',
      );
      expect(entry.origin.nativeId, 'USER.md');
    });

    test('an empty document is a template, not an entry', () {
      expect(clawPersonaEntry('SOUL.md', ''), isNull);
      expect(clawPersonaEntry('SOUL.md', '\n\n  \n'), isNull);
    });

    test('prose with no fields at all counts as written', () {
      // SOUL.md ships as prose rather than as a form, so the field test alone
      // would call a genuinely edited one a template.
      const prose =
          '# SOUL.md\n\n'
          'You are dry, direct, and allergic to filler.\n'
          'You would rather be wrong out loud than vague.\n';
      expect(clawDocumentIsTemplate(prose), isFalse);
      expect(clawPersonaEntry('SOUL.md', prose), isNotNull);
    });
  });

  group('which files are read', () {
    test('operating instructions are not memory', () {
      // AGENTS.md, TOOLS.md and HEARTBEAT.md are how the agent works, not
      // what it learned. Including them buries the two files that change.
      expect(clawPersonaFiles, ['SOUL.md', 'IDENTITY.md', 'USER.md']);
      expect(clawPersonaFiles, isNot(contains('AGENTS.md')));
      expect(clawPersonaFiles, isNot(contains('TOOLS.md')));
      expect(clawPersonaFiles, isNot(contains('HEARTBEAT.md')));
    });
  });

  group('the block round-trips', () {
    // render and parse are a pair. A render the parser cannot read turns the
    // managed block into one giant untitled entry on the next read — and then
    // writes that blob back on the next push, which is how a dozen memories
    // become one.
    List<MemoryEntry> roundTrip(List<MemoryEntry> entries) =>
        clawMemoriesFromMarkdown(renderClawMemoryBlock(entries));

    MemoryEntry entry(String title, String text, {String? native}) =>
        MemoryEntry(
          id: 'x',
          kind: MemoryKind.fact,
          title: title,
          text: text,
          origin: MemoryOrigin(
            backendId: 'openclaw',
            nativeId: native ?? 'MEMORY.md#slug',
          ),
        );

    test('titles and text survive', () {
      final back = roundTrip([
        entry('Coffee', 'Drinks it black. Never after 3pm.'),
        entry('Editor', 'Uses Zed.'),
      ]);
      expect(back.map((e) => e.title), ['Coffee', 'Editor']);
      expect(back.first.text, 'Drinks it black. Never after 3pm.');
    });

    test('multi-paragraph text stays one entry', () {
      final back = roundTrip([
        entry('Runbook', 'First do this.\n\nThen do that.'),
      ]);
      expect(back, hasLength(1));
      expect(back.single.text, contains('Then do that.'));
    });

    test('a bare heading inside an entry does split it — a known limit', () {
      // Pinned rather than fixed: the format is heading-delimited, so a `##`
      // in the body is indistinguishable from a new memory. Recorded here so
      // the next change to either half of the pair is deliberate.
      final back = roundTrip([
        entry('Notes', 'Intro line.\n\n## Not a new memory\n\nMore text.'),
      ]);
      expect(back, hasLength(2));
    });

    test('fenced code inside an entry is preserved and does not split it', () {
      final back = roundTrip([
        entry('Deploy', 'Run:\n\n```bash\n## not a heading\nmake deploy\n```'),
      ]);
      expect(back, hasLength(1));
      expect(back.single.text, contains('make deploy'));
    });

    test('an untitled entry is given a heading from its native id', () {
      // Without one, a run of untitled entries parses back as a single blob.
      final back = roundTrip([
        entry('', 'first thing', native: 'MEMORY.md#first-thing'),
        entry('', 'second thing', native: 'MEMORY.md#second-thing'),
      ]);
      expect(back, hasLength(2));
      expect(back.first.title, 'first thing');
    });

    test('CJK titles survive and stay distinct', () {
      final back = roundTrip([entry('咖啡', '黑咖啡，下午三点后不喝'), entry('编辑器', 'Zed')]);
      expect(back.map((e) => e.title), ['咖啡', '编辑器']);
      expect(back.map((e) => e.origin.nativeId).toSet(), hasLength(2));
    });

    test('an empty list renders to nothing, not to a stray heading', () {
      expect(renderClawMemoryBlock(const []), isEmpty);
      expect(roundTrip(const []), isEmpty);
    });
  });

  group('the block Caduceus owns', () {
    test('the markers are scaffolding, not entries', () {
      // A whole-file read sees the block markers too. They must not become an
      // untitled entry above the block or a tail on the last one.
      const file =
          '## Hand written\n'
          'Above the block.\n\n'
          '$memoryBlockBegin\n'
          '## Managed\n'
          'Inside the block.\n'
          '$memoryBlockEnd\n\n'
          '## Below\n'
          'Below the block.\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries.map((e) => e.title), ['Hand written', 'Managed', 'Below']);
      expect(entries[1].text, 'Inside the block.');
      expect(
        entries.map((e) => e.text).join('\n'),
        isNot(contains('caduceus')),
      );
    });

    test('entries inside the block are tagged managed, outside are not', () {
      const file =
          '## Hand written\n'
          'A person or the agent wrote this.\n\n'
          '$memoryBlockBegin\n'
          '## Managed one\n'
          'Written by this app.\n\n'
          '## Managed two\n'
          'Also written by this app.\n'
          '$memoryBlockEnd\n\n'
          '## Below\n'
          'Not ours.\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries[0].tags, isNot(contains(clawManagedTag)));
      expect(entries[1].tags, contains(clawManagedTag));
      expect(entries[2].tags, contains(clawManagedTag));
      expect(entries[3].tags, isNot(contains(clawManagedTag)));
    });

    test('a file that is only the block tags everything in it', () {
      const file =
          '$memoryBlockBegin\n'
          '## Only\n'
          'Solely managed.\n'
          '$memoryBlockEnd\n';
      final entries = clawMemoriesFromMarkdown(file);

      expect(entries, hasLength(1));
      expect(entries.single.tags, contains(clawManagedTag));
    });
  });
}
