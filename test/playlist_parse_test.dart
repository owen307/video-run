import 'dart:convert';

import 'package:alpaca_video/protocol/playlist_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a ProPresenter 7.9 playlist list and playlist detail', () {
    // GET /v1/playlists is a JSON array. A group nests further playlists under
    // `playlists`. Names and indexes live on the `id` object, not beside it.
    final listed = parsePlaylistDocument(jsonDecode(_playlistList));
    expect(listed.map((playlist) => playlist.name), [
      'Service 2022-01-16',
      'Service 2022-01-16 Evening',
    ]);
    expect(listed.map((playlist) => playlist.id), [
      '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D',
      '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5F',
    ]);
    expect(listed.every((playlist) => playlist.items.isEmpty), isTrue);

    final wrapped = parsePlaylistDocument(jsonDecode('{"playlists": $_playlistList}'));
    expect(wrapped.map((playlist) => playlist.id), listed.map((playlist) => playlist.id));

    final summary = parsePlaylistDocument(
      jsonDecode(
        '{"id":{"index":0,"name":"Service 2022-01-16","uuid":"942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D"},"type":"playlist"}',
      ),
    );
    expect(summary.single.id, '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D');
    expect(summary.single.name, 'Service 2022-01-16');

    // GET /v1/playlist/{id}. Item name and index are fields of `id`.
    final detail = parsePlaylistDocument(jsonDecode(_playlistDetail));
    expect(detail.single.id, '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5A');
    expect(detail.single.name, 'Sunday Service');
    expect(detail.single.items.map((item) => item.name), [
      'Songs',
      'Amazing Grace',
      'Graves Into Gardens',
      'Sermon',
      'Sermon Notes 2022-01-16',
    ]);
    expect(detail.single.items.map((item) => item.index), [0, 1, 2, 3, 4]);
    expect(detail.single.items[1].id, '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5B');
    expect(detail.single.items[0].id, 'Songs');
    expect(detail.single.items[1].presentationUuid, '942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D');
    expect(detail.single.items[0].presentationUuid, isNull);
    expect(detail.single.items[1].itemType, 'presentation');
  });

  test('legacy playlistRequestAll trees still parse', () {
    final legacy = parsePlaylistDocument({
      'action': 'playlistRequestAll',
      'playlistAll': [
        {
          'playlistLocation': '1',
          'playlistType': 'playlistTypeGroup',
          'playlistName': '2017',
          'playlist': [
            {
              'playlistLocation': '1.0',
              'playlistType': 'playlistTypePlaylist',
              'playlistName': 'Vision Dinner',
              'playlist': [
                {
                  'playlistItemName': 'Welcome',
                  'playlistItemLocation': '1.0:0',
                  'playlistItemType': 'playlistItemTypePresentation',
                },
              ],
            },
          ],
        },
      ],
    });
    expect(legacy.single.id, '1.0');
    expect(legacy.single.name, 'Vision Dinner');
    expect(legacy.single.items.single.name, 'Welcome');
    expect(legacy.single.items.single.index, 0);
    expect(legacy.single.items.single.triggerPath, '1.0:0');
  });

  test('walks a group that nests playlists under children', () {
    final listed = parsePlaylistDocument(
      jsonDecode(
        '[{"id":{"uuid":"folder","name":"Library","index":0},"type":"group","children":[{"id":{"uuid":"sunday","name":"Sunday gathering","index":0},"type":"playlist"}]}]',
      ),
    );
    expect(listed.single.id, 'sunday');
    expect(listed.single.name, 'Sunday gathering');
  });
}

/// Sample `GET /v1/playlists` body from the ProPresenter 7.9+ HTTP API.
const _playlistList = '''
[
  {
    "id": {
      "index": 0,
      "name": "Service 2022-01-16",
      "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D"
    },
    "type": "playlist"
  },
  {
    "id": {
      "index": 1,
      "name": "Evening Services",
      "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5E"
    },
    "type": "group",
    "playlists": [
      {
        "id": {
          "index": 0,
          "name": "Service 2022-01-16 Evening",
          "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5F"
        },
        "type": "playlist"
      }
    ]
  }
]
''';

/// Sample `GET /v1/playlist/{id}` body from the ProPresenter 7.9+ HTTP API.
const _playlistDetail = '''
{
  "id": {
    "index": 0,
    "name": "Sunday Service",
    "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5A"
  },
  "items": [
    {
      "id": { "index": 0, "name": "Songs", "uuid": "" },
      "type": "header",
      "is_hidden": true,
      "is_pco": false
    },
    {
      "id": {
        "index": 1,
        "name": "Amazing Grace",
        "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5B"
      },
      "type": "presentation",
      "is_hidden": false,
      "is_pco": false,
      "presentation_info": {
        "presentation_uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D",
        "arrangement_name": "My Chains"
      }
    },
    {
      "id": {
        "index": 2,
        "name": "Graves Into Gardens",
        "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5C"
      },
      "type": "presentation",
      "is_hidden": false,
      "is_pco": false
    },
    {
      "id": { "index": 3, "name": "Sermon", "uuid": "" },
      "type": "header",
      "is_hidden": false,
      "is_pco": false
    },
    {
      "id": {
        "index": 4,
        "name": "Sermon Notes 2022-01-16",
        "uuid": "942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D"
      },
      "type": "presentation",
      "is_hidden": false,
      "is_pco": false
    }
  ]
}
''';
