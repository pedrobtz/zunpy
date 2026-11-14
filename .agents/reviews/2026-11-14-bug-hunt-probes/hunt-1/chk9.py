import numpy as np, io, zipfile
for f in ['out/l.npz','out/lc.npz','out/empty.npz','out/u.npz','out/sp.npz','out/dt.npz']:
    try:
        z = np.load(f)
        print(f, list(z.keys()))
        for k in z.keys(): print('   ', repr(k), z[k].dtype, z[k].shape, z[k].tolist())
    except Exception as e: print(f, 'ERR', repr(e))
# byte identity with savez for a simple case
z = np.load('out/l.npz')
buf = io.BytesIO(); np.savez(buf, **{k: z[k] for k in z.keys()})
print('savez identical:', buf.getvalue() == open('out/l.npz','rb').read())
buf = io.BytesIO(); np.savez_compressed(buf, **{k: z[k] for k in z.keys()})
print('savez_compressed identical:', buf.getvalue() == open('out/lc.npz','rb').read())
for zi in zipfile.ZipFile('out/u.npz').infolist(): print(repr(zi.filename), hex(zi.flag_bits))
