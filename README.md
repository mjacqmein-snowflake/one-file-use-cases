# One-File Use Cases

A catalog of single-file Snowflake use cases. Each one is one `.sql` file you can open in a
Snowsight worksheet, read, run, and undo: it discovers the account it is pointed at, prints
what it would build and what that costs, and creates nothing until a gate variable is flipped.
Every one ships a `TEARDOWN()`.

**Open the catalog:** https://mjacqmein-snowflake.github.io/one-file-use-cases/

This repository contains the client-facing catalog, its images, the offline HTML,
and generated SQL installer downloads. Readable development source lives elsewhere.

Streamlit installers use one expand-icon menu for App only and Show Snowsight.
Each choice opens a new tab and leaves the original session intact. The catalogue
does not claim that fixture UI checks establish backend or production readiness.
