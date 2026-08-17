# Quest Climb

A hands-only lead-climbing game for **Meta Quest 2**, built in **Godot 4.3** with OpenXR.

You're on a 15 m indoor climbing wall with 6 quickdraws. There is a fake belayer at the bottom — no animated character, just an invisible rope feeder. You clip the draws one by one, pull up slack with your free hand, and fight off the pump before your arms give out and the rope catches you.

## Design

- **Hands only, no hand tracking.** The Touch controllers render as stylized-real hand + forearm meshes.
- **Analog grip.** Squeeze the grip button harder to grip harder. The *effective* grip strength is your squeeze multiplied by arm stamina. Below a hold's required grip, you slip.
- **Verlet rope.** 42 particles, distance constraints, runs at 90 Hz on Quest 2. Grab a free section with either hand, pull up slack, push it through a draw gate.
- **Real-angle clipping.** The rope must approach the gate from inside a 55° cone with enough velocity. Wrong angle = the rope bounces off the carabiner. No sound, no UI — just physics.
- **Fatigue.** Holding holds drains stamina, harder when arms are extended or hanging one-handed. Low stamina gives you tremor, a red vignette, and haptic heartbeats. Shake out one arm while the other holds to recover faster.
- **Falling.** Let go above the last clipped draw and you fall ~2× the slack distance, then swing as a pendulum under that draw. No draw clipped = ground fall and reset.
- **Controls.** Left stick walks on the ground only (disabled once you're on the wall). Right stick smooth-turns. Grip button = grab/grip.

## Project layout

```
project.godot                  Godot 4.3 project (mobile renderer, 90 Hz, OpenXR)
export_presets.cfg             "Meta Quest" Android export preset (arm64, OpenXR)
scenarios/main.tscn            Main VR scene
scenes/hold.tscn               One climbing hold
scenes/quickdraw.tscn          Bolt + sling + two carabiners
scenes/hand.tscn               Hand visual prefab
scripts/
  xr_init.gd                   Starts OpenXR, requests 90 Hz
  climber_body.gd              Hand grabbing, stamina, turn, ground locomotion
  hand_visual.gd               Procedural hand + forearm mesh, curl & tremor
  hold.gd                      Hold difficulty + grab transform
  rope_system.gd               Verlet rope + clipping
  rope_grab.gd                 Lets free hands grab rope sections
  quickdraw.gd                 Angle-based clip detection
  fake_belayer.gd              Invisible rope feeder with lag + fall lock-off
  fall_catcher.gd              Pendulum catch on last clipped draw
  wall_builder.gd              Procedural 15 m wall, 6 draws, route holds
  stamina_feedback.gd          Red vignette + heartbeat + rumble
  game_state.gd                Autoload singleton
.github/
  workflows/build-quest.yml    Builds APK on every push, uploads as artifact
  scripts/setup-godot-vendors.sh  Downloads GodotOpenXRVendors plugin in CI
```

## Building locally

1. Install **Godot 4.3 stable** and **OpenJDK 17**.
2. Install the **Android Build Template** in the editor (`Project > Install Android Build Template`).
3. Download the **Godot OpenXR Vendors** plugin (GDExtension, v2.0.3+) and extract it into `addons/godotopenxrvendors/`.
4. Connect a Quest 2 with developer mode enabled.
5. One-click deploy to Android, or:
   ```
   godot --headless --export-debug "Meta Quest" build/quest-climb.apk
   adb install -r build/quest-climb.apk
   ```

## Building via CI

Every push to `main` or this branch builds a debug APK on GitHub Actions and attaches it as a workflow artifact (`quest-climb-apk`). Download the artifact, unzip, and sideload with SideQuest or `adb install`.

## Notes / known limitations

- No audio assets yet — the clipping "click" and heartbeat are wired but the stream is empty. Drop an `AudioStreamMP3`/`WAV` onto the relevant `AudioStreamPlayer` nodes.
- Hands are built from primitive capsules. Swap in a rigged hand GLTF later if you want more realistic fingers.
- The rope is a line-strip mesh. A tube-mesh version can be dropped in without changing the simulation.
- Tested by inspection; no Quest hardware is available in this sandbox.
