-- this file is loaded after all modules are loaded and initialized
-- you can place any custom user code here

-- This client is dedicated to a single server whose protocol version is
-- fixed (until the next protocol upgrade), so we already know what
-- g_game.setClientVersion() will need at login time. Loading it here
-- instead of waiting for the Login button click moves the one-time
-- appearances/sprites/sounds parsing cost (~1.8s, see game_things.lua's
-- onClientVersionChange handler) into the startup splash, where a short
-- delay reads as normal app loading rather than an unresponsive login
-- button. setClientVersion() itself is a no-op if the version already
-- matches when doLogin() runs, so this has no effect on correctness if
-- the version were ever changed by hand before logging in.
local PRELOAD_CLIENT_VERSION = 1525

local needsAssetCheck = PRELOAD_CLIENT_VERSION >= 1281 and modules.client_assets and modules.client_assets.ensureClientVersion and
    (not modules.client_assets.isEnabled or modules.client_assets.isEnabled()) and
    not modules.client_assets.isClientVersionInstalled(PRELOAD_CLIENT_VERSION)

if not needsAssetCheck then
    g_game.setClientVersion(PRELOAD_CLIENT_VERSION)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(PRELOAD_CLIENT_VERSION))
end

print 'Startup done :]'

