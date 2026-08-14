# Velox SDK

This repository lays out the programmatic interface for working with Velox. It's modeled after Zig 0.16's new `Io` API.

Concurrency is handled through the VEXos task scheduler. You can use a `velox_sdk.Io` (which should ideally be aliased as `velox.Io`) reference which **should** hopefully let you use other Zig 0.16 dependencies out of the box (although that has not bene fully tested).
