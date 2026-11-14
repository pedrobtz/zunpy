import numpy as np, glob, io, warnings
warnings.simplefilter('ignore')
for f in sorted(glob.glob('out/b_*.npy')):
    try:
        a = np.load(f); buf = io.BytesIO(); np.save(buf, a)
        same = buf.getvalue() == open(f,'rb').read()
        print(f"{f:20s} {str(a.dtype):16s} {str(a.shape):12s} F={a.flags.f_contiguous and not a.flags.c_contiguous} {'IDENT' if same else 'DIFFER'}  {a.tolist() if a.size<=8 else ''}")
        if not same: print('    z', open(f,'rb').read()[10:80]); print('    n', buf.getvalue()[10:80])
    except Exception as e: print(f, 'ERR', repr(e))
