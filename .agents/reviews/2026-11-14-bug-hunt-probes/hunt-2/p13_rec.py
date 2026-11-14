# Probe 13: record arrays as NumPy writes them; expected columns written as plain 1-d .npy (R row order).
import numpy as np, sys, os, io
out = sys.argv[1]; rng = np.random.default_rng(7)
def rand(dt, shape):
    n = int(np.prod(shape)) if shape else 1
    raw = rng.integers(0, 256, size=n * dt.itemsize, dtype=np.uint8).tobytes()
    a = np.frombuffer(raw, dtype=dt).reshape(shape).copy()
    # sanitize each leaf so values are representable
    def fix(arr):
        d = arr.dtype
        if d.names:
            for nm in d.names: fix(arr[nm])
        elif d.subdtype: pass
        elif d.kind in 'iu' and d.itemsize == 8: arr[...] = (arr.astype('i8') % 1000003).astype(d)
        elif d.kind in 'Mm': arr[...] = (arr.astype('i8') % 1000003).astype(d)
        elif d.kind == 'i' and d.itemsize == 4: arr[...] = np.where(arr == -2**31, 0, arr)
        elif d.kind == 'U': arr[...] = np.array([chr(0x41 + (int(x) % 500)) * (1 + int(x) % d.itemsize // 4) for x in rng.integers(0, 10**6, size=arr.size)]).reshape(arr.shape).astype(d) if d.itemsize else arr
        elif d.kind == 'S': arr[...] = np.array([bytes([0x61 + int(x) % 26]) * (int(x) % (d.itemsize + 1)) for x in rng.integers(0, 10**6, size=arr.size)], dtype=d).reshape(arr.shape)
    fix(a)
    return a
dts = {
 'plain': [('a','<i4'),('b','<f8'),('c','|b1'),('d','<u2')],
 'aligned': np.dtype([('a','|u1'),('b','<f8'),('c','<i2'),('d','<i8')], align=True),
 'aligned_end': np.dtype([('b','<f8'),('a','|u1')], align=True),
 'offsets': np.dtype({'names':['x','y'],'formats':['<i2','<f4'],'offsets':[3,9],'itemsize':20}),
 'titles': np.dtype([(('Title A','a'),'<i4'),(('Title B','b'),'<f4')]),
 'sub': [('v','<f4',(3,)),('m','<i2',(2,3)),('k','|u1')],
 'sub3d': [('t','<i2',(2,2,2)),('s','|S3',(2,))],
 'be': [('a','>i4'),('b','>f8'),('c','>c16'),('d','>u8'),('e','>f2'),('f','>U2'),('g','>M8[s]')],
 'mixed_endian': [('a','>i4'),('b','<i4'),('c','>f4'),('d','<f4')],
 'strs': [('s','|S5'),('u','<U3'),('n','<i4')],
 'times': [('d','<M8[D]'),('t','<M8[ms]'),('dt','<m8[s]'),('y','<M8[Y]')],
 'cplx': [('z','<c8'),('w','<c16'),('h','<f2')],
 'one': [('only','<i8')],
 'aligned_sub': np.dtype([('a','|u1'),('v','<f8',(2,)),('b','|u1')], align=True),
 'quote_names': [("it's", '<i4'), ('say "hi"', '<i4'), ('back\\slash', '<i4'), ('café', '<i4'), ('中文', '<i4'), ('sp ace', '<i4'), ('', '<i4')] ,
}
man = []
k = 0
for name, d in dts.items():
    d = np.dtype(d)
    for shape, fo in [((5,), False), ((2,3), False), ((2,3), True), ((), False), ((0,), False), ((2,1,2), False), ((2,0), False)]:
        a = rand(d, shape)
        a = np.asfortranarray(a) if fo else a
        tag = '%03d' % k; k += 1
        np.save(os.path.join(out, tag + '.npy'), a)
        hdr = open(os.path.join(out, tag + '.npy'), 'rb').read(400)
        rows = a.ravel(order='F') if a.ndim else a.reshape(1)
        cols = []
        for nm in d.names:
            fd = d.fields[nm][0]
            col = rows[nm]
            if fd.subdtype:
                m = int(np.prod(fd.shape)); flat = col.reshape(len(rows), m)
                for e in range(m): cols.append(('%s.%d' % (nm, e + 1), np.ascontiguousarray(flat[:, e])))
            else: cols.append((nm, np.ascontiguousarray(col)))
        for j, (cn, cv) in enumerate(cols):
            np.save(os.path.join(out, '%s_c%02d.npy' % (tag, j)), cv.astype(cv.dtype.newbyteorder('<')) if cv.dtype.byteorder == '>' else cv)
        man.append('%s\t%s\t%s\t%s\t%s' % (tag, name, ','.join(map(str, shape)), int(fo), '\x1f'.join(c[0] for c in cols)))
open(os.path.join(out, 'man.tsv'), 'w', encoding='utf8').write('\n'.join(man) + '\n')
