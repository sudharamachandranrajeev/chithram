import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

// Synthetic: same shape as the real thing, invented ids and signatures.
const _spec =
    r'https://i.ytimg.com/sb/AAAAAAAAAAA/storyboard3_L$L/$N.jpg?sqp=SYN'
    r'|48#27#100#10#10#0#default#rs$SIG0'
    r'|80#45#41#10#10#5000#M$M#rs$SIG1'
    r'|160#90#41#5#5#5000#M$M#rs$SIG2'
    r'|320#180#41#3#3#5000#M$M#rs$SIG3';

void main() {
  group('storyboard', () {
    test('parses levels and builds sheet urls', () {
      final levels = parseStoryboardSpec(
        _spec,
        duration: const Duration(seconds: 200),
      );
      expect(levels.map((l) => l.width), [48, 80, 160, 320]);
      expect(
        levels[0].interval,
        const Duration(seconds: 2),
        reason: 'zero interval = duration / count',
      );
      expect(levels[2].sheets, 2);
      expect(
        levels[2].sheetUrl(1).toString(),
        r'https://i.ytimg.com/sb/AAAAAAAAAAA/storyboard3_L2/M1.jpg?sqp=SYN&sigh=rs$SIG2',
      );
      expect(
        levels[0].sheetUrl(0).toString(),
        contains('storyboard3_L0/default.jpg'),
      );
    });

    test('frameAt: sheet, column and row; clamps past the end', () {
      final l = parseStoryboardSpec(_spec)[2]; // 5x5, every 5 s
      var f = l.frameAt(const Duration(seconds: 0));
      expect((f.sheet, f.col, f.row), (0, 0, 0));
      f = l.frameAt(const Duration(seconds: 37)); // frame 7
      expect((f.sheet, f.col, f.row), (0, 2, 1));
      f = l.frameAt(const Duration(seconds: 125)); // frame 25 -> sheet 1
      expect((f.sheet, f.col, f.row), (1, 0, 0));
      f = l.frameAt(const Duration(hours: 5));
      expect(f.sheet, 1);
      expect((f.col, f.row), (0, 3), reason: 'frame 40 = 15th on sheet 1');
    });

    test('pick: smallest level at least as wide as the target', () {
      final levels = parseStoryboardSpec(_spec);
      expect(pickStoryboardLevel(levels, targetWidth: 150)!.width, 160);
      expect(pickStoryboardLevel(levels, targetWidth: 1000)!.width, 320);
      expect(
        pickStoryboardLevel(levels, targetWidth: 10)!.width,
        80,
        reason: 'level 0 has no interval',
      );
    });

    test('malformed or missing specs give no levels', () {
      expect(parseStoryboardSpec(null), isEmpty);
      expect(parseStoryboardSpec(''), isEmpty);
      expect(parseStoryboardSpec('onlybase'), isEmpty);
      expect(parseStoryboardSpec(r'b|1#2#x#4#5#6#n#s'), isEmpty);
    });

    test('player response: spec is read from storyboards', () {
      expect(
        storyboardSpecOf({
          'storyboards': {
            'playerStoryboardSpecRenderer': {'spec': _spec},
          },
        }),
        _spec,
      );
      expect(storyboardSpecOf({}), isNull);
    });
  });

  group('chapters', () {
    Map<String, Object?> chapterMarkers(List<(int, String)> items) => {
      'playerOverlays': {
        'playerOverlayRenderer': {
          'decoratedPlayerBarRenderer': {
            'decoratedPlayerBarRenderer': {
              'playerBar': {
                'multiMarkersPlayerBarRenderer': {
                  'markersMap': [
                    {
                      'key': 'DESCRIPTION_CHAPTERS',
                      'value': {
                        'chapters': [
                          for (final (ms, t) in items)
                            {
                              'chapterRenderer': {
                                'title': {'simpleText': t},
                                'timeRangeStartMillis': ms,
                              },
                            },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        },
      },
    };

    test('from the player bar markers', () {
      final c = parseChapters(
        chapterMarkers([(0, 'Intro'), (65000, 'Main'), (300000, 'End')]),
      );
      expect(c.map((e) => e.title), ['Intro', 'Main', 'End']);
      expect(c[1].start, const Duration(seconds: 65));
    });

    test('from the chapters panel when the bar has none', () {
      final panel = {
        'engagementPanels': [
          {
            'items': [
              for (final (s, t) in [(0, 'A'), (90, 'B')])
                {
                  'macroMarkersListItemRenderer': {
                    'title': {'simpleText': t},
                    'timeDescription': {'simpleText': '0:00'},
                    'onTap': {
                      'watchEndpoint': {'startTimeSeconds': s},
                    },
                  },
                },
            ],
          },
        ],
      };
      expect(parseChapters(panel).map((e) => e.start.inSeconds), [0, 90]);
    });

    test('chapters past the end are dropped; one chapter is none', () {
      final markers = chapterMarkers([
        (0, 'A'),
        (60000, 'B'),
        (999000, 'Late'),
      ]);
      expect(
        parseChapters(markers, duration: const Duration(minutes: 5)).length,
        2,
      );
      expect(parseChapters(chapterMarkers([(0, 'Only')])), isEmpty);
    });

    test('from the description: YouTube rules', () {
      const text =
          'Great video\n0:00 Intro\n1:30 - The setup\n(12:05) Wrap up\nlinks: https://x.y';
      final c = chaptersFromDescription(text);
      expect(c.map((e) => (e.start.inSeconds, e.title)), [
        (0, 'Intro'),
        (90, 'The setup'),
        (725, 'Wrap up'),
      ]);
      expect(
        chaptersFromDescription('Intro 0:00\nPart 2 - 2:00\nEnd 1:02:03')
            .length,
        3,
      );
      expect(
        chaptersFromDescription('1:00 Late start\n2:00 b\n3:00 c'),
        isEmpty,
        reason: 'must start at 0:00',
      );
      expect(
        chaptersFromDescription('0:00 a\n0:05 b\n1:00 c'),
        isEmpty,
        reason: 'under ten seconds',
      );
      expect(
        chaptersFromDescription('0:00 a\n1:00 b'),
        isEmpty,
        reason: 'fewer than three',
      );
    });

    test('falls back to the description when the response has no markers', () {
      final next = {
        'x': {
          'videoSecondaryInfoRenderer': {
            'attributedDescription': {
              'content': '0:00 One\n0:30 Two\n1:00 Three',
            },
          },
        },
      };
      final info = parseWatchInfo(next, 'AAAAAAAAAAA');
      expect(info.chapters.map((c) => c.title), ['One', 'Two', 'Three']);
    });
  });

  group('heatmap', () {
    test('heat markers on the player bar', () {
      final next = {
        'heatmap': {
          'heatmapRenderer': {
            'heatMarkers': [
              for (var i = 0; i < 3; i++)
                {
                  'heatMarkerRenderer': {
                    'timeRangeStartMillis': i * 10000,
                    'markerDurationMillis': 10000,
                    'heatMarkerIntensityScoreNormalized': i == 1 ? 1.0 : 0.25,
                  },
                },
            ],
          },
        },
      };
      final h = parseHeatmap(next);
      expect(h.length, 3);
      expect(h[1].intensity, 1.0);
      expect(h[2].start, const Duration(seconds: 20));
    });

    test('markers in frameworkUpdates (numbers as strings)', () {
      final next = {
        'frameworkUpdates': {
          'entityBatchUpdate': {
            'mutations': [
              {
                'payload': {
                  'macroMarkersListEntity': {
                    'markersList': {
                      'markerType': 'MARKER_TYPE_HEATMAP',
                      'markers': [
                        {
                          'startMillis': '0',
                          'durationMillis': '5000',
                          'intensityScoreNormalized': 0.5,
                        },
                        {
                          'startMillis': '5000',
                          'durationMillis': '5000',
                          'intensityScoreNormalized': 2,
                        },
                      ],
                    },
                  },
                },
              },
              {
                'payload': {
                  'macroMarkersListEntity': {
                    'markersList': {
                      'markerType': 'MARKER_TYPE_TIMESTAMPS',
                      'markers': [
                        {
                          'startMillis': '1',
                          'durationMillis': '1',
                          'intensityScoreNormalized': 1,
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      };
      final h = parseHeatmap(next);
      expect(h.length, 2);
      expect(h[1].intensity, 1.0, reason: 'clamped');
    });

    test('none when absent', () => expect(parseHeatmap({'a': 1}), isEmpty));
  });
}
