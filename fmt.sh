#!/bin/bash

dune fmt > /dev/null 2>&1
cargo fmt > /dev/null 2>&1

exit 0
