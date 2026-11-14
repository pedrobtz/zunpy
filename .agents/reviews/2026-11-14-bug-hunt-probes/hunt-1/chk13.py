import numpy as np
a = np.load('out/ct.npy'); t = np.fromfile('out/ct.f8', '<f8')
exp = np.round(t*1e6).astype('i8')
print('numpy us counts equal round(t*1e6):', np.array_equal(a.astype('i8'), exp), int(np.sum(a.astype('i8') != exp)))
