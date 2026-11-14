import numpy as np, zipfile, sys
for f in ['p9/ok.npz', 'p9/count2.npz', 'p9/count0.npz']:
    z = np.load(f); print(f, 'numpy:', z.files, '| zipfile:', zipfile.ZipFile(f).namelist(), '| testzip:', zipfile.ZipFile(f).testzip())
