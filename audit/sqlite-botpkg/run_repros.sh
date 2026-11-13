#!/bin/bash
# Re-run every reproducer and print the compiler's own words. usage: BOT=... run_repros.sh   (from the repo root)
BOT=${BOT:-$PWD/botlish}
cd "$(dirname "$0")/repros"
run() { echo; echo "\$ botlish $*"; "$BOT" "$@" 2>&1 | grep -v '^help:' | head -8; }
run -check f01_portable_stdout.bot
run -check -target macos-aarch64 f01_portable_stdout.bot
run -check f03_payload_enum.bot
(cd f04 && run -check main.bot)
run -check f05_null_fnptr.bot
run -backend cranelift f08_context_int.bot
run -backend cranelift f08b_context_int_domain.bot
run -check f09_error_keyword_module.bot
run -check f10_error_payload_type.bot
run -check f13_affine_handler.bot
