import numpy as np, zipfile, glob
for f in sorted(glob.glob("out10/*.npz")):
    try:
        zf=zipfile.ZipFile(f); print(f, [ (repr(i.filename), hex(i.flag_bits)) for i in zf.infolist()], "testzip", zf.testzip())
        z=np.load(f); print("   keys", [repr(k) for k in z.keys()], [ (z[k].dtype, z[k].tolist(), z[k].flags.c_contiguous) for k in z.keys()])
    except Exception as e: print(f,"FAIL",repr(e)[:200])
