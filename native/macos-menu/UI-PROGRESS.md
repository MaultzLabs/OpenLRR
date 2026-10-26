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
