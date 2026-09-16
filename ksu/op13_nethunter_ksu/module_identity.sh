#!/system/bin/sh
# Source with MODDIR set. Compare ELF notes, not persistent switch markers.
module_identity() {
  if [ ! -d "/sys/module/$1" ]; then
    echo absent
  elif [ ! -r "$MODDIR/module_build_ids/$1.note" ] ||
       [ ! -r "/sys/module/$1/notes/.note.gnu.build-id" ]; then
    echo unverified
  elif cmp -s "$MODDIR/module_build_ids/$1.note" "/sys/module/$1/notes/.note.gnu.build-id"; then
    echo payload
  else
    echo other
  fi
}

payload_stack_mode() {
  identity_match=0
  identity_present=0
  for identity_name in cfg80211 mac80211 qca_cld3_peach_v2; do
    identity_value=$(module_identity "$identity_name")
    [ "$identity_value" = absent ] || identity_present=$((identity_present + 1))
    [ "$identity_value" != payload ] || identity_match=$((identity_match + 1))
  done
  if [ "$identity_match" -eq 3 ]; then echo nethunter
  elif [ "$identity_present" -eq 0 ]; then echo inactive
  elif [ "$identity_match" -gt 0 ]; then echo mixed
  else echo unverified
  fi
}

verify_payload_stack() {
  [ "$(payload_stack_mode)" = nethunter ] && return 0
  for identity_name in cfg80211 mac80211 qca_cld3_peach_v2; do
    echo "$identity_name: $(module_identity "$identity_name")" >&2
  done
  return 1
}
