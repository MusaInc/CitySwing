# Branding verification — 0.17.1

The logo, icons, engine launch artwork, loading scene and live start screen now
share the main menu's Outfit / gold / white / Night Ink identity.

Real Godot Mobile-renderer captures (llvmpipe, not phone performance evidence):

| Format | Loading | Start | Main menu |
|---|---|---|---|
| 1280 × 720 | [loading](loading.png) | [start](start.png) | [menu](menu.png) |
| Tablet 1152 × 864 | [loading](tablet/loading.png) | [start](tablet/start.png) | [menu](tablet/menu.png) |
| Wide phone 1560 × 720 | [loading](phone/loading.png) | [start](phone/start.png) | [menu](phone/menu.png) |

[Before](before.png) shows the previous menu wordmark. The loading artwork no
longer contains the old illustrated red-suited hero.

All three render runs passed the startup lifecycle and real input checks:
loading overlay freed, game scene current, live title shown, keyboard Start
accepted, pointer Play entered gameplay. See the `*-smoke.log` files.

The targeted startup regression passed (1 test): failed-state retry is focused,
a retry loads one scene even after duplicate activation, and the launch overlay
is released. The exported Linux build launched through the new boot scene and
passed its packaged self-test: 8 courses, 33 sounds, 15 kit items, Mobile renderer.

The source debug runs retain existing shutdown resource/ObjectDB warnings.
No parse errors or startup/navigation assertion failures occurred.
Physical iPhone startup timing and touch/safe-area behaviour require device QA;
the phone/tablet captures here check viewport proportions, not hardware notches.

The complete regression run recorded 124 passes and one stale shop assertion:
it expected the classic trainer sole to follow jacket colour, predating the
Courier's deliberately white trainers. Updated that expectation and added a
separate shoe-colour independence check; the entire shop suite then passed
5/5. Both unmodified run logs are retained (`regression-tests.log` and
`shop-tests.log`). No production behaviour was changed for this test correction.
