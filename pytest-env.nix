# The end-to-end half imports rookery off `PYTHONPATH`, which is only
# meaningful within one python minor version, so this interpreter has to be the
# one rookery was built with. Neither side names a version: both take their
# nixpkgs' default `python3`, and `tests/e2e/runner.py` refuses a run where the
# two disagree.
pkgs: pkgs.python3.withPackages (ps: [ ps.pytest ])
