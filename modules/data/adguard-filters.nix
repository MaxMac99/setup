# Blocklists, shared by every AdGuard instance in the estate.
#
# There are three of them now — brink-server and winkel-pi via
# modules/system/site-dns.nix, and ionos via modules/system/roaming-dns.nix —
# and they must block the same things or "roaming" quietly means "less
# protected". That failure is invisible: a phone away from home would resolve
# fine, load faster than expected, and nothing would report a difference.
#
# These two lists are what the in-cluster instance ran before Phase 4 moved DNS
# onto the hosts. Restoring the Phase 1 backup would have added nothing else —
# it carried `users: []`, `user_rules: []`, `rewrites: []` and
# `clients.persistent: []`, a stock install.
#
# ⚠️ `id` must be unique within an instance and is what AdGuard keys its
# on-disk filter cache by. Reusing an id for a different URL makes AdGuard
# serve the old list under the new name until the cache is cleared.
[
  {
    enabled = true;
    url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
    name = "AdGuard DNS filter";
    id = 1;
  }
  {
    enabled = true;
    url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
    name = "AdAway Default Blocklist";
    id = 2;
  }
]
