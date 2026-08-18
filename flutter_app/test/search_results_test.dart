/// A search that found nothing to show is not a search.
///
/// web_search answers with `result.data.web[]`. ToolCall read only
/// `result.output`, which that payload does not have, so the client showed
/// that a search had happened and nothing whatsoever about what it found.
/// Payload shape captured from the reference server.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// The console consumes domain events. These fixtures stay written in Hermes'
/// vocabulary and go through the app's own adapter, which is the path a real
/// frame takes.
AgentEvent _agent(GatewayEvent event) =>
    agentEventFromHermes(event.sessionId ?? '', event)!;

void main() {
  test('search hits survive the tool result', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('搜索万宁有哪些美食');
    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.start',
          sessionId: 's1',
          payload: const {
            'tool_id': 'call_d916',
            'name': 'web_search',
            'context': 'Searching the web for 万宁 美食 特色小吃 必吃',
          },
        ),
      ),
    );
    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.complete',
          sessionId: 's1',
          payload: const {
            'tool_id': 'call_d916',
            'name': 'web_search',
            'args': {'query': '万宁 美食 特色小吃 必吃', 'limit': 8},
            'duration_s': 4.012,
            'result': {
              'success': true,
              'data': {
                'web': [
                  {
                    'url': 'https://zhuanlan.zhihu.com/p/700230948',
                    'title': '海南旅游攻略：想去万宁的存下吧',
                    'description': '小海杂鱼汤，又叫小海鲜鱼汤…',
                  },
                  {
                    'url':
                        'http://news.hainan.net/meishi/2026/01/15/'
                        '4801128.shtml',
                    'title': '过年冲万宁！这篇美食清单承包你的舌尖年味',
                    'description': '推荐店铺：山海和蟹…',
                  },
                ],
              },
            },
          },
        ),
      ),
    );

    final call = console.tools['call_d916']!;
    expect(
      call.webResults,
      hasLength(2),
      reason: 'the hits are in result.data.web, not result.output',
    );
    expect(call.webResults.first.title, contains('海南旅游攻略'));
    expect(call.webResults.first.url, startsWith('https://zhuanlan.zhihu.com'));
    expect(call.webResults.first.snippet, isNotEmpty);

    // And the row can say what was searched for, not only that something was.
    expect(call.query, '万宁 美食 特色小吃 必吃');

    console.dispose();
  });

  test('a tool with plain output is unaffected', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.complete',
          sessionId: 's1',
          payload: const {
            'tool_id': 't1',
            'name': 'terminal',
            'duration_s': 0.1,
            'result': {'output': 'a\nb', 'exit_code': 0},
          },
        ),
      ),
    );
    final call = console.tools['t1']!;
    expect(call.output, 'a\nb');
    expect(call.webResults, isEmpty);
    expect(call.query, isNull);
    console.dispose();
  });

  test('a malformed result does not throw', () {
    // The shape is the server's, not ours, and a client that crashes on an
    // unexpected one is worse than one that shows nothing.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    for (final result in <Object?>[
      null,
      'a string',
      {'data': 'not a map'},
      {
        'data': {'web': 'not a list'},
      },
      {
        'data': {
          'web': [1, 2, 3],
        },
      },
    ]) {
      console.handle(
        _agent(
          GatewayEvent(
            type: 'tool.complete',
            sessionId: 's1',
            payload: {
              'tool_id': 'x',
              'name': 'web_search',
              'duration_s': 0.1,
              'result': result,
            },
          ),
        ),
      );
      expect(console.tools['x']!.webResults, isEmpty);
    }
    console.dispose();
  });
}
