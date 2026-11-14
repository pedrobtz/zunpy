import sys, io, numpy as np, zipfile, os
o = sys.argv[1]
print("H3-1 numpy f2:", np.array([1 + 2**-11 + 2**-40]).astype('<f2').tobytes().hex(), np.array([2**-25 * (1 + 2**-52)]).astype('<f2').tobytes().hex())
z = np.load(os.path.join(o, "dup.npz")); print("H3-2 numpy keys", list(z.keys()), [z[k] for k in z.keys()])
buf = io.BytesIO(); np.savez(buf, **{"m%05d" % i: np.zeros(0, np.uint8) for i in range(1, 65536)})
mine = open(os.path.join(o, "m65535.npz"), "rb").read(); ref = buf.getvalue()
print("H3-5 65535 members: identical to savez?", mine == ref, len(mine), len(ref))
