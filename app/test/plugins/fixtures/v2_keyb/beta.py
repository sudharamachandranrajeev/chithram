# synthetic test plugin beta
class beta(object):
    url = 'https://beta.example'
    name = 'Beta 1.0'
    supported_categories = {'all': '0', 'movies': '1', 'tv': '2'}
    def search(self, what, cat='all'):
        pass
