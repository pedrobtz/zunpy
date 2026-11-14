import numpy as np, glob, io, sys
for f in sorted(glob.glob('out/n*.npy')) + ['out/df.npy','out/df0.npy','out/df03.npy','out/df00.npy','out/dfshape.npy','out/dfshapeC.npy']:
    try:
        a = np.load(f)
        buf = io.BytesIO(); np.save(buf, a)
        same = buf.getvalue() == open(f,'rb').read()
        print(f, repr(a.dtype.names), a.shape, 'bytes-identical' if same else 'DIFFER')
        if not same and f.startswith('out/n'):
            print('   z:', open(f,'rb').read()[:120]); print('   n:', buf.getvalue()[:120])
        if 'df' in f: print('  ', a.dtype, a.tolist() if a.size < 10 else '')
    except Exception as e:
        print(f, 'ERR', e)
