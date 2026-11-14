import sys, numpy as np
z = np.load(sys.argv[1]); print("F6 numpy keys", list(z.keys()), "z['a.npy'] =", z["a.npy"])
