import sys, zipfile, numpy as np
print("H2-F3 zipfile names", zipfile.ZipFile(sys.argv[1]).namelist(), " numpy keys", list(np.load(sys.argv[1]).keys()))
