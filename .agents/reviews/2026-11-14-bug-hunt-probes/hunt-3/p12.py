import zipfile, inspect, sys
print(sys.version)
print("ZIP64_LIMIT", zipfile.ZIP64_LIMIT, "FILECOUNT", zipfile.ZIP_FILECOUNT_LIMIT)
src=inspect.getsource(zipfile.ZipFile._write_end_record)
import re
for l in src.split("\n"):
    if "ZIP64_LIMIT" in l or "ZIP_FILECOUNT_LIMIT" in l or "extra.append" in l or "0xffffffff" in l or "min(" in l: print(l)
