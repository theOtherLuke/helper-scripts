# Miscellaneous BASH Scripts

## *ssh-key-manger.sh*
Full featured ssh key manager. This one started small and got away from me fast. I'm planning to streamline some of the functions and remove redundant code, but for now it works.

## *setup-ssh-keys.sh*
A little less full-featured than `ssh-key-manager.sh`. This one doesn't handle aliases and isn't menu driven. This does have help sections for TrueNAS Scale, Proxmox, and Debian to help configure the remote host for ssh access.

## *show-function.sh*
Just a little helper script to extract and display functions from scripts.

## *list-ssh-aliases.sh*
Parses `$HOME/.ssh/config` for aliases and displays them in pretty pretty colors.
