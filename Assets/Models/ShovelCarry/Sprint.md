# Sprint locomotion

- PC: hold either Shift key; release to walk. Shift lock is disabled to reserve Shift for sprint.
- Mobile: tap the LARI button to toggle. It sits above the native jump button, with a teal active state and gold outline.
- Walk speed remains the character's existing speed (normally 16); sprint uses 24 studs/second. Tune `Shared/Config/Sprint.luau`.
- Server chooses speed through the validated/rate-limited `SetSprinting` remote. Personal/shared dig sessions, death, sitting and movement locks block sprint.
- Text input, menus, shop panels, loss of focus and respawn clear the local request. Dig focus hides the button with the other HUD.
- Procedural R15/R6 cycles blend over normal animation in `SprintAnimation`, before the shared shovel arm overlay. Free hands swing; held shovels retain two hand contacts with a restrained stride and torso movement. Jump/fall/swim/climb retain the normal animation.
- `ShovelCarry` restores the previous procedural transforms before Animator runs. No animation upload or shovel-specific grip is required.

Studio checks: Shift hold/release (24/16), mobile toggle on, button separation from jump, equipped Iron Shovel with IK and identity idle grip, unequip/back cosmetic, dig-focus cancellation and respawn reset. The mobile orientation change also prompted a layout guard against stale native jump-button coordinates. Final scripts boot without sprint runtime errors. Live publishing was not performed.
