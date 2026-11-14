# Probe 3: data block, every numeric dtype x byte order x C/F x shape; expected in R-native binary (column-major).
import numpy as np, sys, os, itertools
out = sys.argv[1]
rng = np.random.default_rng(1)
man = []
k = 0
def edge(dt):
    d = np.dtype(dt)
    if d.kind == 'b': return np.array([0,1,1,0,1,0,0,1,1,1,0,0], dtype=d)
    if d.kind in 'iu':
        info = np.iinfo(d)
        lim = 2**53
        vals = [0,1,info.max if info.max<=lim else lim, (info.min if info.min>=-lim else -lim), 2,3,5,7, min(info.max,2**31-1), max(info.min, -2**31+1), min(info.max, 2**32-1), 42]
        if d == np.dtype('i4') or d == np.dtype('>i4'): vals[3] = -2**31+1
        return np.array(vals, dtype=d)
    if d.kind == 'f':
        fi = np.finfo(d)
        return np.array([0.0,-0.0,np.inf,-np.inf,np.nan,fi.max,fi.tiny,fi.smallest_subnormal,-fi.max,1/3,1e-5,123456.789], dtype=d)
    if d.kind == 'c':
        f = np.finfo(d)
        re = np.array([0.0,-0.0,np.inf,-np.inf,np.nan,f.max,f.tiny,1,2,1/3,1e-5,123456.789])
        return (re + 1j*re[::-1]).astype(d)
shapes = [(12,), (3,4), (2,3,2), (1,12), (12,1), (2,1,3,2), (4,3)]
for base in ['b1','i1','u1','i2','u2','i4','u4','i8','u8','f2','f4','f8','c8','c16']:
    for bo in ['<','>']:
        d = np.dtype(base).newbyteorder(bo)
        a0 = edge(d)
        for shp in shapes:
            for fo in [False, True]:
                a = a0.reshape(shp)
                a = np.asfortranarray(a) if fo else np.ascontiguousarray(a)
                fn = '%04d' % k; k += 1
                np.save(os.path.join(out, fn + '.npy'), a)
                flat = a.ravel(order='F')
                if d.kind == 'b' or (d.kind in 'iu' and d.itemsize <= 2) or base == 'i4':
                    exp = flat.astype('<i4').tobytes(); rt = 'int'
                elif d.kind == 'c':
                    exp = flat.astype('<c16').tobytes(); rt = 'cplx'
                else:
                    exp = flat.astype('<f8').tobytes(); rt = 'dbl'
                open(os.path.join(out, fn + '.exp'), 'wb').write(exp)
                # header check: fortran flag as numpy wrote it
                man.append('%s\t%s\t%s\t%s\t%s' % (fn, d.str, ','.join(map(str, shp)), rt, 'lgl' if d.kind=='b' else ''))
open(os.path.join(out, 'man.tsv'), 'w').write('\n'.join(man) + '\n')
