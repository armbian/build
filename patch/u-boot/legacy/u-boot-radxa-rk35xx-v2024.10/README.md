# Radxa rk35xx vendor u-boot patches for next-dev-v2024.10+ only

These patches target Radxa's `next-dev-v2024.10` branch and do NOT apply to the
older `next-dev-v2024.03` branch used by mixtile-blade3 and the Mekotronics
rk3588 boards (which pin 2024.03 because 2024.10+ breaks the stable-MAC patch).

Boards on 2024.10 add this dir to BOOTPATCHDIR (alongside the base
`legacy/u-boot-radxa-rk35xx`); the 2024.03 boards use the base dir only.
