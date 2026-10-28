#!/bin/bash
# Stargate: The Last Stand dedicated server, native Linux (Source 2007 "orangebox" engine), with the Redial bots.
# Setup: docs/LINUX_SERVER.md. Run it as the server's user, e.g. under screen or from linux/sgtls.service.
#
# The loop restarts srcds after a crash (-norestart: restarts belong to this loop, and it logs them);
# -debug makes srcds_run pass a core dump to gdb (stack in debug.log).
# Don't use "set -e": srcds exits with a non-zero code after every crash.
set -uo pipefail

# --- Settings -----------------------------------------------------------------------------------------------
# The engine folder must be named "orangebox": Botrix recognises the game by the folder of the srcds executable.
SRCDS_DIR=${SRCDS_DIR:-$HOME/sgtls-server/orangebox}
IP=${IP:-0.0.0.0}               # the public address on a multi-homed host
PORT=${PORT:-27015}
CLIENTPORT=${CLIENTPORT:-27005}
MAXPLAYERS=${MAXPLAYERS:-32}     # with fewer slots, the mod closes parts of some maps
MAP=${MAP:-tls_abydos}
# ------------------------------------------------------------------------------------------------------------

cd "$SRCDS_DIR" || exit 1
# bin/srcds2007_fix_i486.so (linux/srcds2007_fix.c): the 2014 engine never tells Steam that a bot left, so the
# server browser counted "ghost players" (+10 at each map change with 10 bots). Only for srcds_run and what it
# starts: ld.so says "wrong ELF class" for the 64-bit tools among them, harmless.
PRELOAD=$SRCDS_DIR/bin/srcds2007_fix_i486.so
ulimit -c unlimited

while :; do
	echo "$(date '+%F %T') starting Stargate: The Last Stand ($PORT)" | tee -a restarts.log
	rc=0
	LD_PRELOAD=$PRELOAD ./srcds_run -binary ./srcds_i486 -debug -norestart -game sgtls -console \
		-ip "$IP" -port "$PORT" +clientport "$CLIENTPORT" -nohltv +sv_master_legacy_mode 0 +sv_lan 0 \
		+maxplayers "$MAXPLAYERS" -condebug +log on +map "$MAP" || rc=$?
	echo "$(date '+%F %T') srcds exited (code $rc), restarting in 5 s" | tee -a restarts.log

	# console.log (-condebug): one file per run, stamped when it ends.
	L=sgtls/console.log
	[ -f "$L" ] && mv -- "$L" "${L%.log}-$(date +%Y%m%d-%H%M%S).log"
	# Keep the 2 newest core dumps.
	find . -maxdepth 1 -type f -regextype posix-extended -regex '.*/core(\.[0-9]+)?' -printf '%T@ %p\n' 2>/dev/null |
		sort -rn | tail -n +3 | cut -d' ' -f2- | while IFS= read -r c; do rm -f -- "$c"; done
	sleep 5
done
