# Merchant dialogue

Interact with the NPC using E, the touch hint, or by clicking the NPC face. The shared NpcDialogue controller displays these exact options:

1. Sell all item in inventory
2. Sell held item
3. Nevermind

Sales run directly without opening the old merchant panel. Sell held item sells one copy of the server-created loot Tool in the character. Click an owned item card in the Items inventory to hold it; the Tool is a visual representation of the inventory entry, not another copy. Shovels, eggs and pets cannot be sold by this action. Server inventory and proximity checks still apply. Depleted item Tools are removed after individual or bulk sales.

Studio verification: held Pebble sold one unit for 10 coins, bulk sale sold the remaining two for 20 coins and removed the held Tool, empty-hand sale returned NoHeldItem, E opened the exact three choices, Nevermind closed without a sale. Temporary test inventory and coins were restored. No live publishing.
