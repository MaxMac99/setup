# Outbound client public keys

Public halves of the SSH identities this fleet *presents* to other systems.
The private halves live in 1Password and are served by its SSH agent; nothing
here is secret.

They exist as files because `IdentitiesOnly yes` needs a file to decide which
agent-resident key to offer — required for the github.com split, where offering
both identities would authenticate as whichever account matches first.

**This is deliberately not `modules/data/keys/`.** That directory is the
*inbound* set: `modules/system/base.nix` globs it into `authorized_keys` on
every host. A key placed there may log in here. `id_hetzner.pub` is a third
party's endpoint identity and must never be granted that.

`max-admin.pub` is both inbound and outbound, so it stays in `../keys/` and is
referenced from there — one copy, not two.

## Rotation

Each file's comment field is its **1Password item title** (1Password overwrites
the comment with the title). To rotate: replace the key in 1Password, then
update the matching file here. Verify the repo and the agent still agree:

    diff <(ssh-add -L | awk '{print $2}' | sort) \
         <(cat modules/data/pubkeys/*.pub modules/data/keys/max-admin.pub \
           | awk '{print $2}' | sort)
