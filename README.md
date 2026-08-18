# Velox SDK

This repository lays out the programmatic interface for working with Velox and the V5 brain hardware.

Concurrency is handled through the VEXos task scheduler. You can use a `velox_sdk.V5Io` (which should ideally be aliased as `velox.Io`) instance which **should** hopefully let you use other Zig 0.16 dependencies out of the box (although that has not bene fully tested).
