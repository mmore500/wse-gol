try:
    from itertools import pairwise  # Python 3.10+
except ImportError:
    # adapted from https://docs.python.org/3/library/itertools.html#itertools.pairwise
    def pairwise(iterable):
        # pairwise('ABCDEFG') -> AB BC CD DE EF FG

        iterator = iter(iterable)
        a = next(iterator, None)

        for b in iterator:
            yield a, b
            a = b
