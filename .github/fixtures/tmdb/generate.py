#!/usr/bin/env python3
"""Generate synthetic API responses only. Never download or copy TMDB data."""
import json
from pathlib import Path
root = Path(__file__).parent
film = dict(id=1, title='Fixture Film 1', original_title='Fixture Film 1', release_date='2026-01-02', adult=False, poster_path='/fixture1.jpg', backdrop_path='/fixture_backdrop.jpg', vote_average=7.5)
show = dict(id=2, name='Fixture Series 2', original_name='Fixture Series 2', first_air_date='2026-02-03', adult=False, poster_path='/fixture2.jpg')
responses = {
 'configuration': {'images': {'secure_base_url': 'https://image.tmdb.org/t/p/'}, 'change_keys': []},
 'movie-list': {'page': 1, 'results': [film], 'total_pages': 1},
 'tv-list': {'page': 1, 'results': [show], 'total_pages': 1},
 'mixed-list': {'page': 1, 'results': [dict(film, media_type='movie'), dict(show, media_type='tv'), {'id':3,'media_type':'person','name':'Fixture Person'}, dict(film,id=4,adult=True)]},
 'genres': {'genres': [{'id': 12, 'name': 'Fixture Adventure'}]},
 'movie-details': dict(film, runtime=110, overview='A synthetic film for tests.', genres=[{'id':12,'name':'Fixture Adventure'}], credits={'cast':[{'name':'Fixture Actor','character':'Fixture Role','profile_path':'/fixture_actor.jpg'}]}, videos={'results':[{'site':'YouTube','type':'Trailer','key':'fixture1234','name':'Fixture Trailer','official':True,'iso_639_1':'en'}]}, recommendations={'results':[dict(film,id=5,title='Fixture Film 5')]}, external_ids={'imdb_id':'tt0000001'}),
 'tv-details': dict(show, episode_run_time=[45], overview='A synthetic series for tests.', aggregate_credits={'cast':[{'name':'Fixture Actor','roles':[{'character':'Fixture Role'}]}]}, seasons=[{'season_number':1,'name':'Fixture Season 1','episode_count':1}], external_ids={'tvdb_id':22,'imdb_id':'tt0000002'}),
 'season': {'season_number':1,'episodes':[{'episode_number':1,'name':'Fixture Episode 1','overview':'Synthetic episode.','still_path':'/fixture_still.jpg','air_date':'2026-01-01','runtime':45}]},
}
for name, response in responses.items():
 (root / f'{name}.json').write_text(json.dumps(response, indent=2) + '\n')
