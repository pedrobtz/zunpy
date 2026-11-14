import numpy as np, sys
for i in [7, 14, 21, 28, 35, 42, 98]:
    a = np.load('p13/%03d.npy' % i)
    d = a.dtype
    print('%03d' % i, 'itemsize', d.itemsize, 'shape', a.shape, [(n, d.fields[n][1], d.fields[n][0].base.str, d.fields[n][0].shape, d.fields[n][2] if len(d.fields[n]) > 2 else None) for n in d.names])
