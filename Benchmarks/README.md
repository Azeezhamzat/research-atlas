# Research Atlas performance profile

`ResearchAtlasPerformance` builds an isolated, deterministic synthetic library and measures an optimized release build of the real SQLite/FTS and grounded-retrieval paths used by the app. It never opens the user's Research Atlas database, local research folder, Obsidian vault, or provider credentials.

The default profile contains 3,000 papers and 36,000 page-level source passages—substantially larger than the current personal library—and runs 40 samples each for global search, grounded retrieval, filtered library loading, and complete metadata loading. It also times ingestion and a full search-index rebuild, validates record counts and current citation snapshots, writes a machine-readable JSON report, and deletes the temporary database when finished.

Run:

```sh
Scripts/run-performance-profile.sh
```

Custom size:

```sh
Scripts/run-performance-profile.sh 5000 12 60
```

Generated reports contain synthetic benchmark measurements and host capacity only. Latency budgets are intentionally reported rather than hard-coded as pass/fail thresholds because disk, memory pressure, thermal state, and hardware differ. Correctness failures always exit non-zero.
