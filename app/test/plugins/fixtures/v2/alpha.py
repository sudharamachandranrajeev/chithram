# synthetic test plugin alpha
class alpha(object):
    url = 'https://alpha.example'
    name = 'Alpha 1.1'
    supported_categories = {'all': '0', 'movies': '1', 'tv': '2'}
    def search(self, what, cat='all'):
        pass
