# Probe 2: structured descr spellings; NumPy's view of names/offsets/values.
import numpy as np, io, struct, sys, os, warnings
out = sys.argv[1]
def mk(hdr, data, ver=(1,0), align=64, enc='latin1'):
    h = hdr.encode(enc) if isinstance(hdr, str) else hdr
    pre = 10 if ver[0]==1 else 12
    pad = (-(pre+len(h)+1)) % align
    h = h + b' '*pad + b'\n'
    lenf = struct.pack('<H', len(h)) if ver[0]==1 else struct.pack('<I', len(h))
    return b'\x93NUMPY' + bytes(ver) + lenf + h + data
cases = []
def add(name, descr, itemsize, n=2, shape=None, fo=False, **kw):
    data = bytes((i*7+1) % 251 for i in range(itemsize*n))
    shape = shape or "(%d,)" % n
    cases.append((name, mk("{'descr': %s, 'fortran_order': %s, 'shape': %s, }" % (descr, fo, shape), data, **kw)))
add('plain', "[('a', '<i4'), ('b', '<f8')]", 12)
add('pad_first', "[('', '|V4'), ('a', '<i4')]", 8)
add('pad_mid', "[('a', '<i2'), ('', '|V2'), ('b', '<i4')]", 8)
add('empty_names', "[('', '<i4'), ('', '<i2')]", 6)
add('pad_then_empty', "[('', '|V2'), ('', '<i2'), ('x', '<i2'), ('', '<i2')]", 8)
add('empty_V_sub', "[('', '|V2', (2,)), ('a', '<i4')]", 8)
add('empty_V_sub_int', "[('', '|V2', 2), ('a', '<i4')]", 8)
add('title_emptyname_V', "[(('t', ''), '|V4'), ('a', '<i4')]", 8)
add('title', "[(('my title', 'a'), '<i4'), ('b', '<i2')]", 6)
add('title_dup', "[(('b', 'a'), '<i4'), ('b', '<i2')]", 6)
add('title_same', "[(('a', 'a'), '<i4'), ('b', '<i2')]", 6)
add('sub', "[('a', '<i2', (2, 3)), ('b', '|u1')]", 13)
add('sub_int', "[('a', '<i2', 3), ('b', '|u1')]", 7)
add('sub_empty_tuple', "[('a', '<i2', ()), ('b', '|u1')]", 3)
add('sub_one', "[('a', '<i2', (1,)), ('b', '|u1')]", 3)
add('sub_zero', "[('a', '<i2', (0,)), ('b', '|u1')]", 1)
add('sub_list', "[('a', '<i2', [2]), ('b', '|u1')]", 5)
add('field_list', "[['a', '<i2'], ['b', '|u1']]", 3)
add('descr_tuple', "('<i2', (2,))", 4)
add('descr_tuple_list', "[('<i2', (2,))]", 4)
add('nested', "[('a', [('x', '<i2'), ('y', '<i2')]), ('b', '|u1')]", 5)
add('dup', "[('a', '<i2'), ('a', '|u1')]", 3)
add('dup_gen', "[('f1', '<i2'), ('', '|u1')]", 3)
add('dup_gen2', "[('', '<i2'), ('f0', '|u1')]", 3)
add('one_tuple', "[('a',)]", 1)
add('four_tuple', "[('a', '<i2', (2,), 1)]", 4)
add('empty_list', "[]", 0, n=0, shape="(0,)")
add('empty_list3', "[]", 0, n=0, shape="(3,)")
add('bytes_name', "[(b'a', '<i2')]", 2)
add('S_fields', "[('s', '|S3'), ('u', '<U1'), ('v', '|V2')]", 9)
add('be_fields', "[('a', '>i4'), ('b', '>f8'), ('c', '>c8'), ('d', '>u2')]", 22)
add('native_field', "[('a', 'i4'), ('b', '=f8')]", 12)
add('2d_C', "[('a', '<i2'), ('b', '|u1')]", 3, n=6, shape="(2, 3)")
add('2d_F', "[('a', '<i2'), ('b', '|u1')]", 3, n=6, shape="(2, 3)", fo=True)
add('0d', "[('a', '<i2'), ('b', '|u1')]", 3, n=1, shape="()")
add('dict_packed', "{'names': ['a', 'b'], 'formats': ['<i4', '<i2']}", 6)
add('dict_off', "{'names': ['a', 'b'], 'formats': ['<i4', '<i2'], 'offsets': [4, 0], 'itemsize': 10}", 10)
add('dict_tuple_names', "{'names': ('a', 'b'), 'formats': ('<i4', '<i2')}", 6)
add('dict_titles', "{'names': ['a', 'b'], 'formats': ['<i4', '<i2'], 'titles': ['T', None]}", 6)
add('dict_aligned', "{'names': ['a', 'b'], 'formats': ['|u1', '<i4'], 'aligned': True}", 8)
add('dict_overlap', "{'names': ['a', 'b'], 'formats': ['<i4', '<i2'], 'offsets': [0, 2], 'itemsize': 4}", 4)
add('dict_fmt_sub', "{'names': ['a', 'b'], 'formats': [('<i2', (2,)), '<i2']}", 6)
add('latin1_name', "[('caf\xe9', '<i2')]", 2)
add('latin1_name_v3', "[('caf\xe9', '<i2')]", 2, ver=(3,0), enc='utf8')
add('latin1_name_v2', "[('caf\xe9', '<i2')]", 2, ver=(2,0))
add('utf8_in_v1', "[('caf\xc3\xa9', '<i2')]", 2)
add('esc_name', "[('a\\tb', '<i2'), ('c\\'d', '<i2'), (\"e'f\", '<i2'), ('g\\\\h', '<i2')]", 8)
add('u_esc_name', "[('\\u00e9', '<i2'), ('\\U0001F600', '<i2')]", 4)
add('ws_name', "[(' a ', '<i2'), ('a', '<i2')]", 4)
add('M_fields', "[('t', '<M8[s]'), ('d', '<m8[ms]')]", 16)
res = []
def show(a):
    if a.dtype.names is None:
        return 'OK plain %s %s %s' % (a.dtype.str, a.shape, a.tolist())
    parts = []
    for nme in a.dtype.names:
        fd = a.dtype.fields[nme]
        col = a[nme]
        v = col.reshape(a.size, -1) if a.size else col
        # R order rows
        rows = a.ravel(order='F')[nme]
        parts.append('%s@%d %s=%s' % (nme, fd[1], fd[0].str if fd[0].subdtype is None else fd[0].subdtype[0].str+str(fd[0].shape),
              [x.tobytes().hex() if isinstance(x, (np.void, bytes)) else (x.tolist() if hasattr(x,'tolist') else x) for x in rows] if rows.dtype.kind not in 'Mm' else rows.astype('i8').tolist()))
    return 'OK itemsize=%d shape=%s :: %s' % (a.dtype.itemsize, a.shape, ' | '.join(parts))
for k,(name, b) in enumerate(cases):
    open(os.path.join(out, '%03d.npy' % k),'wb').write(b)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            a = np.load(io.BytesIO(b), allow_pickle=False)
        r = show(a)
    except Exception as e:
        r = 'ERR %s: %s' % (type(e).__name__, str(e)[:70])
    res.append((name, r))
with open(os.path.join(out,'numpy.tsv'),'w') as f:
    for k,(name,r) in enumerate(res):
        f.write('%03d\t%s\t%s\n' % (k,name,r.replace('\n',' ').replace('\t','\\t')))
