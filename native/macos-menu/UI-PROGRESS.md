# Mission UI pass

The mission now has a persistent, context-sensitive command sidebar instead of
standalone Drill/Back controls. Main commands, selected Raider, drillable wall,
first-person camera, and building catalog each have their own page. Original
CFG icon paths and available surround images are loaded from the user's WADs;
missing art retains accessible native text buttons.

Implemented controls: drill, cancel the selected Raider's order, first-person
and overhead cameras, Back/deselect, and browse original building names and
costs. Unsupported construction, teleporting, vehicles, tools, training,
reinforcement and dynamite are explicitly disabled. Hover displays the action
and its explanation, including unavailable reasons and building costs. Enabled
icons use the original source's green hover outline; AppKit provides pressed
and disabled feedback. Catalogs scroll without covering Back. Sidebar right
clicks are consumed instead of issuing cave orders.

Mission options now contains the diagnostics and NERPs pause/resume controls.
Action feedback expires after six seconds unless diagnostics is enabled. The
building-menu click feeds the original NERPs Get/SetBuildIconClicked counter.
Tutorial input restrictions continue to disable command buttons.

Validation added: synthetic CFG catalog order, prefix precedence, duplicate and
nested property handling, building labels/costs/icons, unavailable actions,
selection-dependent drilling, surround parsing and bounds, and independent
NERPs building-click get/reset semantics. Linux parser tests and macOS ARM64
AppKit compilation run on each branch push.

Limits: retail asset alignment and actual mouse/keyboard gameplay still need
an in-game review on the user's Mac. This is not a pixel-perfect restoration:
heading/help and the reserved Back row are native layout, and unsupported game
systems are not implemented by displaying their icons. No copyrighted game
art or music is included in source or CI artifacts.

## Screenshot-guided layout correction

Reference images inspected at 640x480:
- https://pichuonigiri.wordpress.com/2015/01/06/lego-rock-raiders/ (base/power paths)
- https://gamesdb.launchbox-app.com/games/images/5325-lego-rock-raiders (lava cavern)

Both show compact upper-right command icons and a persistent empty green bottom
message panel. The follow-up removes permanent sidebar help text, uses a floating
hover explanation, preserves original icon bitmap dimensions, anchors the menu
at the source's (565,18) position, and uses CFG Back highlight/pressed overlays
and offsets when their surround is available. Unused space below the compact
menu now passes clicks to the cave. The message panel stays visible when empty,
with Next hidden. Original surrounding panels, resources and camera controls are
still incomplete; this does not claim a finished retail HUD.

Regression checks cover the empty message panel/hidden Next and cave hit testing
below the sidebar, alongside existing action dispatch and tutorial locks. Real
asset alignment still needs checking in the running native build.
