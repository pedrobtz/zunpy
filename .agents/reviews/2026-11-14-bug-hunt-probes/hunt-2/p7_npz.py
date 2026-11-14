# Probe 7: .npz written by other tools / options. Expected: per member, key and int values, as np.load sees it.
import numpy as np, zipfile, io, sys, os, struct, subprocess, shutil, warnings, zlib
out = sys.argv[1]
def npy(a):
    b = io.BytesIO(); np.save(b, a); return b.getvalue()
A = np.arange(6, dtype='<i4').reshape(2,3); B = np.array([1.5, -2.5]); C = np.array(['x','yz'])
mem = [('a.npy', npy(A)), ('b.npy', npy(B)), ('c.npy', npy(C))]
man = []
def reg(name, path_or_bytes):
    p = os.path.join(out, name + '.npz')
    if isinstance(path_or_bytes, bytes): open(p, 'wb').write(path_or_bytes)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            z = np.load(p, allow_pickle=False)
            if not hasattr(z, 'files'):
                r = 'NOTNPZ %r' % (z,)
            else:
                parts = []
                for k in z.files:
                    try:
                        v = z[k]
                        parts.append('%s=%s' % (k, v.ravel(order='F').tolist() if isinstance(v, np.ndarray) else 'BYTES%d' % len(v)))
                    except Exception as e:
                        parts.append('%s=ERR(%s)' % (k, type(e).__name__))
                r = 'OK ' + ' ; '.join(parts)
    except Exception as e:
        r = 'ERR %s: %s' % (type(e).__name__, str(e)[:60])
    man.append('%s\t%s' % (name, r))
np.savez(os.path.join(out, 'savez.npz'), a=A, b=B, c=C); reg('savez', None)
np.savez_compressed(os.path.join(out, 'savezc.npz'), a=A, b=B, c=C); reg('savezc', None)
np.savez(os.path.join(out, 'positional.npz'), A, B); reg('positional', None)
np.savez(os.path.join(out, 'empty.npz')); reg('empty', None)
def zf(name, comp=zipfile.ZIP_STORED, level=None, force=None, members=mem, comment=None, stream=False, mode='writestr', allow64=True):
    class NoSeek(io.RawIOBase):
        def __init__(s): s.b = io.BytesIO()
        def writable(s): return True
        def write(s, d): return s.b.write(d)
        def seekable(s): return False
    buf = NoSeek() if stream else io.BytesIO()
    with zipfile.ZipFile(buf, 'w', compression=comp, compresslevel=level, allowZip64=allow64) as z:
        for n, d in members:
            if mode == 'writestr':
                z.writestr(n, d)
            else:
                with z.open(n, 'w', force_zip64=bool(force)) as f:
                    f.write(d[:20]); f.write(d[20:])
        if comment: z.comment = comment
    reg(name, (buf.b if stream else buf).getvalue())
zf('zf_stored'); zf('zf_deflate', zipfile.ZIP_DEFLATED)
for lv in (0, 1, 9): zf('zf_deflate_l%d' % lv, zipfile.ZIP_DEFLATED, lv)
zf('zf_open_force64', force=True, mode='open'); zf('zf_open_noforce', force=False, mode='open')
zf('zf_open_force64_defl', zipfile.ZIP_DEFLATED, force=True, mode='open')
zf('zf_stream_stored', stream=True); zf('zf_stream_deflate', zipfile.ZIP_DEFLATED, stream=True)
zf('zf_stream_open_force64', zipfile.ZIP_DEFLATED, stream=True, force=True, mode='open')
zf('zf_stream_open', stream=True, mode='open')
zf('zf_comment', comment=b'hello world comment')
zf('zf_comment_pk', comment=b'PK\x05\x06' + b'\x00'*18)
zf('zf_comment_long', comment=b'x'*65535)
zf('zf_bzip2', zipfile.ZIP_BZIP2); zf('zf_lzma', zipfile.ZIP_LZMA)
zf('zf_nonnpy', members=mem + [('readme.txt', b'hello')])
zf('zf_dir', members=[('sub/', b'')] + mem)
zf('zf_subdir', members=[('sub/a.npy', npy(A)), ('b.npy', npy(B))])
zf('zf_noext', members=[('a', npy(A)), ('b.npy', npy(B))])
zf('zf_noext_dup', members=[('a', npy(A)), ('a.npy', npy(B))])
zf('zf_dup', members=[('a.npy', npy(A)), ('a.npy', npy(B))])
zf('zf_utf8', members=[('café.npy', npy(A)), ('中\U0001F600.npy', npy(B))])
zf('zf_dotnpy', members=[('.npy', npy(A)), ('x.npy.npy', npy(B)), ('y.NPY', npy(B))])
zf('zf_zero_d', members=[('s.npy', npy(np.array(7, dtype='<i4'))), ('e.npy', npy(np.zeros((0,3))))])
zf('zf_many', members=[('m%05d.npy' % i, npy(np.array([i], dtype='<i4'))) for i in range(300)])
big = npy(np.arange(70000, dtype='<i4'))  # > 64KiB
zf('zf_big_deflate', zipfile.ZIP_DEFLATED, members=[('big.npy', big), ('a.npy', npy(A))])
zf('zf_big_stream', zipfile.ZIP_DEFLATED, stream=True, members=[('big.npy', big), ('a.npy', npy(A))])
# prepended junk (self-extractor style), zipfile adjusts offsets
b = io.BytesIO(); 
with zipfile.ZipFile(b, 'w') as z:
    for n, d in mem: z.writestr(n, d)
reg('prepended', b'#!/bin/sh\nexit\n' + b.getvalue())
reg('appended', b.getvalue() + b'\n')
# zip64 end-of-central-directory forced: >65535 members is heavy; instead craft via zipfile internal thresholds
import zipfile as zm
old = (zm.ZIP_FILECOUNT_LIMIT, zm.ZIP64_LIMIT)
zm.ZIP_FILECOUNT_LIMIT = 2
zf('zf_zip64_eocd_count')
zm.ZIP_FILECOUNT_LIMIT = old[0]
zm.ZIP64_LIMIT = 100   # every size/offset > 100 goes to the zip64 extra
zf('zf_zip64_all'); zf('zf_zip64_all_deflate', zipfile.ZIP_DEFLATED); zf('zf_zip64_all_stream', zipfile.ZIP_DEFLATED, stream=True)
zm.ZIP64_LIMIT = old[1]
# zip CLI
if shutil.which('zip'):
    d = os.path.join(out, 'cli'); os.makedirs(os.path.join(d, 'sub'), exist_ok=True)
    for n, dd in mem: open(os.path.join(d, n), 'wb').write(dd)
    open(os.path.join(d, 'sub', 'a.npy'), 'wb').write(npy(A))
    for nm, args in [('cli_default', ['-q']), ('cli_stored', ['-q', '-0']), ('cli_X', ['-q', '-X']), ('cli_r', ['-q', '-r'])]:
        p = os.path.join(out, nm + '.npz')
        if os.path.exists(p): os.remove(p)
        files = ['a.npy', 'b.npy', 'c.npy'] + (['sub'] if nm == 'cli_r' else [])
        subprocess.run(['zip'] + args + [p] + files, cwd=d, check=True)
        reg(nm, None)
    p = os.path.join(out, 'cli_stream.npz')
    subprocess.run('cat a.npy | zip -q - - > "%s"' % p, cwd=d, shell=True, check=True); reg('cli_stream', None)
    p = os.path.join(out, 'cli_fz.npz')
    if os.path.exists(p): os.remove(p)
    subprocess.run(['zip', '-q', '-fz', p, 'a.npy', 'b.npy'], cwd=d); 
    if os.path.exists(p): reg('cli_fz', None)
open(os.path.join(out, 'man.tsv'), 'w').write('\n'.join(man) + '\n')
