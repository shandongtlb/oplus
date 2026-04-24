#!/system/bin/sh

MODDIR=${0%/*}

cleanup_fw() {
  src="$MODDIR/vendor/firmware/rt2870.bin"

  for dst in \
    /mnt/vendor/persist/copy/rt2870.bin \
    /mnt/vendor/persist/rt2870.bin
  do
    if [ ! -f "$dst" ]; then
      continue
    fi

    if [ -f "$src" ] && cmp -s "$src" "$dst" 2>/dev/null; then
      rm -f "$dst"
    fi
  done
}

cleanup_fw
