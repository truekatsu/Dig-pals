# Default shovel carry

Shared defaults: ReplicatedStorage/Shared/Config/ShovelCarry.luau.
Gameplay height: 5.4 studs. Front diagonal two-hand hold, rear diagonal cosmetic when stowed. New models inherit defaults through the builder.

Server carries the real Tool so other players see the same shovel. A separate noninteractive back Model follows the selected shovel only while not held. Client procedural animation uses R15 two-hand IK and R6 shoulder overlays.

Validated in Studio with an R15 avatar: front/back visuals, hand targets within 0.18 studs, three actual service equip/unequip/swing cycles, all seven shovel heights, and respawn restoring the stowed state. R6 uses a separate procedural shoulder path; R6 appearance has not been visually checked.

Prior scripts backed up in Studio under ServerStorage.BeforeDiagonalShovelCarry. Future import conventions are in /AGENTS.md.
