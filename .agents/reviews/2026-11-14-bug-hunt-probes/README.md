# Probes of the 2026-11-14 bug hunt

The scripts the hunters (`hunt-1` R layer, `hunt-2` decoding, `hunt-3` emitting) and the coordinator (`rerun`) ran against zunpy at `0e74ace`. Paths inside them start at `HUNT_ROOT`, the hunt's scratch directory. It held `src/`, an archive of that commit, and `lib/`, the package installed into a scratch library. To re-run a probe, recreate both and replace `HUNT_ROOT`. The Python counterparts run under `uv run --no-project --with numpy==2.3.3 python`. Generated output files are left out, except `hunt-2/p21_wrong.npy.gz`, the file that triggers #58.
