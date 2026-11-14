# Probe 16: random shapes (0..6 dims, with 0s and 1s), every element kind, C and F; expected = 1-d F-order ravel as its own .npy.
import numpy as np, sys, os
out = sys.argv[1]; rng = np.random.default_rng(11)
kinds = ['<i4','>i2','|u1','<f8','>f4','<c16','>c8','|b1','|S3','<U2','>U2','|V3','<M8[D]','>M8[ms]','<m8[h]','<i8','<M8[Y]']
man = []
for k in range(260):
    nd = int(rng.integers(0, 7))
    shape = tuple(int(x) for x in rng.choice([0,1,1,2,2,3,4,5], size=nd))
    if int(np.prod(shape)) > 3000: shape = shape[:3]
    dt = np.dtype(kinds[k % len(kinds)])
    n = int(np.prod(shape)) if shape else 1
    if dt.kind in 'SUV':
        if dt.kind == 'U': a = np.array([chr(0x61 + i % 26) + ('' if i % 3 else chr(0x3b1 + i % 20)) for i in range(n)], dtype=dt)
        elif dt.kind == 'S': a = np.array([bytes([0x61 + i % 26]) * (i % 4) for i in range(n)], dtype=dt)
        else: a = np.frombuffer(bytes((i * 5 + 1) % 256 for i in range(3 * n)), dtype=dt).copy()
    elif dt.kind in 'Mm' or dt.itemsize == 8 and dt.kind == 'i': a = (np.arange(n, dtype='i8') * 37 - 500).astype(dt)
    elif dt.kind == 'b': a = (np.arange(n) % 3 == 0)
    elif dt.kind == 'c': a = (np.arange(n) + 1j * np.arange(n)[::-1]).astype(dt)
    else: a = (np.arange(n) * 3 - 7).astype(dt)
    a = a.reshape(shape)
    fo = bool(k % 2)
    a = np.asfortranarray(a) if fo else np.ascontiguousarray(a)
    tag = '%03d' % k
    np.save(os.path.join(out, tag + '.npy'), a)
    flat = a.ravel(order='F') if a.ndim else a.reshape(1)
    np.save(os.path.join(out, tag + '_e.npy'), np.ascontiguousarray(flat))
    man.append('%s\t%s\t%s\t%d' % (tag, dt.str, ','.join(map(str, shape)), fo))
open(os.path.join(out, 'man.tsv'), 'w').write('\n'.join(man) + '\n')
