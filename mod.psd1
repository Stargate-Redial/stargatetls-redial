# What install.ps1 / uninstall.ps1 do for Stargate: The Last Stand (Source SDK Base 2007).
@{
    Title            = 'Stargate TLS: Redial'
    ModName          = 'Stargate: The Last Stand'
    ModFolder        = 'sgtls'
    PluginDll        = 'addons\botrix.dll'
    # Runs on Source SDK Base 2007; nothing to install there.
    SdkBaseFolder    = ''
    SdkAppId         = 218
    VdfFromSdkBin    = $false
    # listenserver.cfg: a game created from the menu; server.cfg: a dedicated server.
    CfgFiles         = @('cfg\server.cfg', 'cfg\listenserver.cfg')
    CfgBlock         = @(
        '// Botrix bots (addons/botrix): players + bots kept at this total, bots balance the teams.',
        'botrix config bot quota 10',
        '// Bot skill range: fool stupied normal smart pro.',
        'botrix config bot intelligence normal smart'
    )
    ServerBrowserFix = $false
    PublicServer     = '92.222.243.147:27031'
    Discord          = 'https://discord.com/invite/SgHPP4mZyB'
    Releases         = 'https://github.com/Stargate-Redial/stargatetls-redial/releases'
}
