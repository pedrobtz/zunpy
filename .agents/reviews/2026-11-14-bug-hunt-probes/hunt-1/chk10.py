import numpy as np, io, glob
for f in sorted(glob.glob('out/s_*.npz'))+sorted(glob.glob('out/sc_*.npz')):
    z = np.load(f); buf = io.BytesIO()
    (np.savez_compressed if '/sc_' in f else np.savez)(buf, **{k: z[k] for k in z.keys()})
    a = buf.getvalue(); b = open(f,'rb').read()
    print(f, a == b, len(a), len(b))
    if a != b:
        i = next(i for i,(x,y) in enumerate(zip(a,b)) if x!=y); print('  first diff at', i, a[max(0,i-8):i+24], b[max(0,i-8):i+24])
