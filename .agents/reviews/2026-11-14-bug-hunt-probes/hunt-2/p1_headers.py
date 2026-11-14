# Probe 1: header spellings. For each header text, build a .npy and record what NumPy does.
import numpy as np, io, struct, sys, json, os, warnings
out = sys.argv[1]
def mk(hdr, data, ver=(1,0), align=64, enc='latin1'):
    h = hdr.encode(enc) if isinstance(hdr, str) else hdr
    pre = 10 if ver[0]==1 else 12
    pad = (-(pre+len(h)+1)) % align
    h = h + b' '*pad + b'\n'
    lenf = struct.pack('<H', len(h)) if ver[0]==1 else struct.pack('<I', len(h))
    return b'\x93NUMPY' + bytes(ver) + lenf + h + data
i4 = np.arange(6, dtype='<i4').tobytes()
cases = []
def add(name, hdr, data=i4, **kw):
    cases.append((name, mk(hdr, data, **kw)))
add('canon', "{'descr': '<i4', 'fortran_order': False, 'shape': (2, 3), }")
add('keyorder', "{'shape': (2, 3), 'fortran_order': False, 'descr': '<i4'}")
add('dq', '{"descr": "<i4", "fortran_order": False, "shape": (2, 3)}')
add('nospace', "{'descr':'<i4','fortran_order':False,'shape':(2,3)}")
add('spaces', "{  'descr'  :  '<i4'  ,  'fortran_order'  :  False  ,  'shape'  :  ( 2 , 3 , )  ,  }")
add('tabs', "{\t'descr':\t'<i4',\n'fortran_order': False, 'shape': (2, 3)}")
add('shape_list', "{'descr': '<i4', 'fortran_order': False, 'shape': [2, 3]}")
add('shape_int', "{'descr': '<i4', 'fortran_order': False, 'shape': 6}")
add('shape_paren_int', "{'descr': '<i4', 'fortran_order': False, 'shape': (6)}")
add('shape_L', "{'descr': '<i4', 'fortran_order': False, 'shape': (2L, 3L)}")
add('shape_L1', "{'descr': '<i4', 'fortran_order': False, 'shape': (6L,)}")
add('shape_bool', "{'descr': '<i4', 'fortran_order': False, 'shape': (True, 6)}")
add('shape_plus', "{'descr': '<i4', 'fortran_order': False, 'shape': (+2, 3)}")
add('shape_hex', "{'descr': '<i4', 'fortran_order': False, 'shape': (0x2, 3)}")
add('shape_under', "{'descr': '<i4', 'fortran_order': False, 'shape': (0_2, 3)}")
add('shape_under2', "{'descr': '<i4', 'fortran_order': False, 'shape': (1_0,)}", data=np.arange(10,dtype='<i4').tobytes())
add('shape_00', "{'descr': '<i4', 'fortran_order': False, 'shape': (00, 3)}", data=b'')
add('shape_neg0', "{'descr': '<i4', 'fortran_order': False, 'shape': (-0, 3)}", data=b'')
add('shape_nested', "{'descr': '<i4', 'fortran_order': False, 'shape': ((2, 3))}")
add('shape_nested2', "{'descr': '<i4', 'fortran_order': False, 'shape': ((2), (3))}")
add('shape_float', "{'descr': '<i4', 'fortran_order': False, 'shape': (2.0, 3)}")
add('fo_1', "{'descr': '<i4', 'fortran_order': 1, 'shape': (2, 3)}")
add('fo_0', "{'descr': '<i4', 'fortran_order': 0, 'shape': (2, 3)}")
add('fo_None', "{'descr': '<i4', 'fortran_order': None, 'shape': (2, 3)}")
add('fo_paren', "{'descr': '<i4', 'fortran_order': (True), 'shape': (2, 3)}")
add('fo_true', "{'descr': '<i4', 'fortran_order': True, 'shape': (2, 3)}")
add('dupkey', "{'descr': '<i4', 'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('dupkey_shape', "{'descr': '<i4', 'fortran_order': False, 'shape': (3, 2), 'shape': (2, 3)}")
add('extrakey', "{'descr': '<i4', 'fortran_order': False, 'shape': (2, 3), 'x': 1}")
add('esc_key', "{'de\\x73cr': '<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('esc_descr', "{'descr': '\\x3ci4', 'fortran_order': False, 'shape': (2, 3)}")
add('esc_oct', "{'descr': '\\074i4', 'fortran_order': False, 'shape': (2, 3)}")
add('esc_N', "{'descr': '\\N{LESS-THAN SIGN}i4', 'fortran_order': False, 'shape': (2, 3)}")
add('concat', "{'descr': '<' 'i4', 'fortran_order': False, 'shape': (2, 3)}")
add('ustr', "{'descr': u'<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('bstr', "{'descr': b'<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('rstr', "{'descr': r'<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('triple', "{'descr': '''<i4''', 'fortran_order': False, 'shape': (2, 3)}")
add('comment', "{'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)} # hi")
add('leading_ws', " {'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('leading_nl', "\n{'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('paren_dict', "({'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)})")
add('no_nl_end', "{'descr': '<i4', 'fortran_order': False, 'shape': (2, 3)}")
add('ff', "{'descr': '<i4',\x0c 'fortran_order': False, 'shape': (2, 3)}")
add('vt', "{'descr': '<i4',\x0b 'fortran_order': False, 'shape': (2, 3)}")
add('nbsp', "{'descr': '<i4',\xa0'fortran_order': False, 'shape': (2, 3)}")
add('set', "{'descr', '<i4'}")
add('shape0d', "{'descr': '<i4', 'fortran_order': False, 'shape': ()}", data=i4[:4])
add('shape0d_F', "{'descr': '<i4', 'fortran_order': True, 'shape': ()}", data=i4[:4])
add('F_2x3', "{'descr': '<i4', 'fortran_order': True, 'shape': (2, 3)}")
add('F_1d', "{'descr': '<i4', 'fortran_order': True, 'shape': (6,)}")
# descr spellings
for d in ['i4','=i4','|i4','<i4','>i4','int32','<i','i','l','<l','<q','d','<d','f','<f','?','|?','b','|b','B','<b1','|b1','b1','>b1','=b1','|i1','<i1','i1','|u1','<u1','u1','<i04','<f08',
          '<i 4',' <i4','<i4 ','<I4','<u4','<u','<h','<H','<e','<f2','<f4','<f8','<c8','<F','<D','<c16','<i2','<i8','<u8','<u2','|S4','S4','<S4','a4','|a4','|V4','V4','<V4','|S','S','<U1','U1','|U1','=U1','>U1','U',
          '<M8[s]','M8[s]','<M8','<m8','<m8[s]','<M8[10s]','<M8[s/2]','<M8[ D]','<datetime64[s]','datetime64[s]','<M8[us]','<M[s]','<m[s]', '<M8[m]','<M8[h]','<M8[W]','<M8[Y]','<M8[M]','<m8[Y]','<m8[m]','<M8[generic]','<m8[ms]','<M8[as]',
          '<f16','<c32','<g','O','|O','<O8','|O8','<i16','<u16','<f1','<c4','<b2','<i3','<S-1','|S04','|S+4', '<U01','<T','|T16','<T16']:
    isz = None
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            isz = np.dtype(d).itemsize
    except Exception:
        pass
    data = bytes(range(1, 1+ (isz or 4)*2)) if isz != 0 else b''
    data = (bytes(range(1,65)))[: (isz or 4)*2]
    add('descr:'+d, "{'descr': %r, 'fortran_order': False, 'shape': (2,)}" % d, data=data)
res = []
for k,(name, b) in enumerate(cases):
    fn = os.path.join(out, '%03d.npy' % k)
    open(fn,'wb').write(b)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            a = np.load(io.BytesIO(b), allow_pickle=False)
        r = 'OK %s %s %s' % (a.dtype.str, a.shape, a.ravel(order='F').tolist() if a.dtype.kind not in 'Mm' else a.ravel(order='F').astype('i8').tolist())
    except Exception as e:
        r = 'ERR %s: %s' % (type(e).__name__, str(e)[:60])
    res.append((name, r))
with open(os.path.join(out,'numpy.tsv'),'w') as f:
    for k,(name,r) in enumerate(res):
        f.write('%03d\t%s\t%s\n' % (k,name,r))
