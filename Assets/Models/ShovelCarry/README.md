# Default shovel carry

Shared defaults: ReplicatedStorage/Shared/Config/ShovelCarry.luau.
Gameplay height: 5.4 studs. Front diagonal two-hand hold, rear diagonal cosmetic when stowed. New models inherit defaults through the builder.

DiagonalCarryV4 follows the approved red reference line: the right hand holds local Y=1.6 at the neck below the Rusty D grip, and the left supports Y=-0.55 on the shaft. The shovel tilts 52 degrees from vertical (38 degrees down across the front of the body), with the blade lower and further inward than V3. It stays 0.85 studs in front of the torso. `ShovelCarry.GetHeldCFrame` aligns the upper target with the avatar's right shoulder, using the R15 attachment or R6 shoulder joint. These same contact points, shared idle/swing recovery, and pose are the default for every new shovel.

Server carries the real Tool so other players see the same shovel. A separate noninteractive back Model follows the selected shovel only while not held. Client procedural animation uses R15 two-hand IK and R6 shoulder overlays.

Validated in Studio with an R15 avatar: front/back visuals, hand targets within 0.18 studs, three actual service equip/unequip/swing cycles, all seven shovel heights, and respawn restoring the stowed state. R6 uses a separate procedural shoulder path; R6 appearance has not been visually checked.

Prior scripts backed up in Studio under ServerStorage.BeforeDiagonalShovelCarry. Future import conventions are in /AGENTS.md.
