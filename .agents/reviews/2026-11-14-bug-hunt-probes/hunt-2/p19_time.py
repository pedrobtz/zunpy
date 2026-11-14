# Probe 19: M8/m8 [ms|us|ns] counts -> seconds; oracle = correctly rounded Fraction(count, scale).
import numpy as np, sys, os, random
from fractions import Fraction
out = sys.argv[1]; random.seed(3)
for unit, scale in [('ms', 10**3), ('us', 10**6), ('ns', 10**9)]:
    vals = [0, 1, -1, scale, -scale, scale - 1, 2**53, 2**53 + 1, 2**53 - 1, -(2**53) - 1, 2**63 - 1, -(2**63) + 1, 1728388800123456789, -1728388800123456789, 2**62 + 12345]
    for bits in range(1, 64):
        for _ in range(60):
            v = random.getrandbits(bits); vals += [v, -v]
    a = np.array(vals, dtype='<i8')
    for kind in 'Mm':
        np.save(os.path.join(out, '%s_%s.npy' % ('dt' if kind == 'M' else 'td', unit)), a.astype('<%s8[%s]' % (kind, unit)))
        np.save(os.path.join(out, '%s_%s_be.npy' % ('dt' if kind == 'M' else 'td', unit)), a.astype('>%s8[%s]' % (kind, unit)))
    np.save(os.path.join(out, 'exp_%s.npy' % unit), np.array([float(Fraction(v, scale)) for v in vals], dtype='<f8'))
    np.save(os.path.join(out, 'raw_%s.npy' % unit), a)
