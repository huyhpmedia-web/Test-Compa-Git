import re
D='/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/audsrc/lic/'
stn={}
for l in open(D+'stn.md'):
    m=re.match(r'\| `([^`]+)` \| (.*) \|$',l)
    if m: stn[m.group(1).replace('.ogg','')]=m.group(2).replace('<br>','; ')
bo={}
for l in open(D+'hh.md'):
    m=re.match(r'\| (\S+\.mp3) \| (\S+) \| (\d+) \| (\S+) \| CC0 \|',l)
    if m: bo[m.group(1)]=(m.group(2),m.group(4))
ia={}
t=open(D+'ia.txt').read().split('AUDIO FILES INCLUDED WITH INFRA ARCANA')[1]
for b in t.strip().split('\n\n'):
    d=dict(re.findall(r'^(\w[\w ]*?):\s+(.*)$',b,re.M))
    if 'File' in d: ia[d['File'].replace('.ogg','')]=d
def STN(*k): return '; '.join('`%s` = %s'%(x,stn[x]) for x in k)
def BO(*k): return '; '.join('[%s](%s) by %s (CC0)'%(x.split('/')[-1],bo[x][1],bo[x][0]) for x in k)
def IA(*k):
    o=[]
    for x in k:
        d=ia[x]; lic='CC0' if 'CC0' in d['License'] else 'CC BY 3.0' if 'BY 3' in d['License'] else d['License']
        o.append('[%s](%s) by %s (%s)'%(d.get('Original title',x).strip(),d['Source'],d['Author'].replace(' (username on freesound.org)',''),lic))
    return '; '.join(o)
H=[]
A=H.append
A('''# Audio credits and licences

Everything in this folder is either a processed derivative of a **real CC0 / CC BY / CC BY-SA recording**
or is marked **PROCEDURAL** (synthesised in `tools/gen_audio.py`, no third-party material).
No GPL-only, NC or unlicensed material is used. Sounds were trimmed, pitched, filtered, layered, given
reverb, normalised and (loops) crossfaded; the originals are not distributed here.

All sources were obtained from public GitHub mirrors (the original freesound / OpenGameArt / kenney.nl pages
were not reachable from the build environment). The mirror used is named for each source; the licence
cited is the one recorded on the original page by the mirror's own credits file (linked below).

## Licence legend / attribution that MUST be shown in the game credits

* **CC0 1.0** - public domain, no attribution required (authors credited here anyway).
* **CC BY 3.0 / 4.0** - attribution required. Credit these in-game (Credits screen):
  * ermfilm - "Rossi-Revolver" (https://freesound.org/people/ermfilm/sounds/*) - CC BY 3.0 (used in `shot_magnum`)
  * steveygos93 - "Explosion2" - CC BY 3.0 (used in `explosion`)
  * Nicistarful - "Fast Throttle Mechanic Lever" - CC BY 3.0 (used in `valve`)
  * jesabat - "Steam Hiss" - CC BY 3.0 (used in `burster_death`)
  * juskiddink - "Dogs growling" - CC BY 3.0 (used in `hound_bite`)
  * poots - "deep_under" (https://freesound.org/people/poots/sounds/) - CC BY 3.0 (used in `amb_cavern`)
* **CC BY-SA 4.0** - attribution + share-alike. The three music tracks below (and the loops derived from them) are
  therefore themselves distributed under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
  * "Decoherence" (`music_title`), "Helios" (`music_ending`), "Primal Carnage" (`music_chase`) by **Scott Buckley** -
    www.scottbuckley.com.au. Source mirror: Battle for Wesnoth, `data/campaigns/*/music/`
    (https://github.com/wesnoth/wesnoth , listed as CC BY-SA 4.0 in `copyrights.csv`). Trimmed to a loop section and loudness-matched.

## Output -> source

Variants `_a/_b/_c` share the source group of the base name. "Kenney" = Kenney.nl CC0 packs (Impact Sounds, RPG Audio,
UI/Interface Sounds, Sci-Fi Sounds; https://kenney.nl/assets, mirrors: lunarcloud/ggj-2024-rail-shooter, Nazarwadim/School-Hooligan,
Codename-Recon/Gridlock; licence text "Creative Commons CC0" in each pack).
''')
A('| name(s) | source | licence |\n|---|---|---|')
def R(n,s,l='CC0'): A('| `%s` | %s | %s |'%(n,s,l))
KEN='Kenney'
R('step_snow, step_concrete, step_wood','Kenney Impact Sounds `footstep_snow/concrete/wood_000-002`')
R('step_tile','Kenney `footstep_concrete_002-004` (hi-passed, small reverb) + `impact_plate_light`')
R('step_metal','Kenney `footstep_concrete_000-002` + `impact_metal_light_000-002` (pitched)')
R('step_water',STN('fs_water'))
R('shot_handgun',IA('sfx_pistol_fire')+'; '+STN('gun_pistol'))
R('shot_shotgun',IA('sfx_shotgun_sawed_off_fire')+'; '+STN('gun_shotgun'))
R('shot_magnum',IA('sfx_revolver_fire')+'; '+STN('gun_pistol','gun_shotgun')+' (pitched down, layered)','CC BY 3.0 (ermfilm) + CC0')
R('shot_launcher',IA('sfx_morphic_blaster')+'; '+STN('gun_shotgun')+'; Kenney Sci-Fi `explosionCrunch_000`')
R('dry_fire, reload, equip',STN('fol_dry','fol_mag_out','fol_mag_in','fol_draw'))
R('knife_swing',STN('swing')+'; '+IA('sfx_miss_light','sfx_miss_medium','sfx_miss_heavy'))
R('knife_hit','Kenney RPG Audio `knifeSlice`, `knifeSlice2`; '+STN('hit_flesh','hit_head'))
R('explosion',IA('sfx_explosion')+'; '+STN('exp_near')+'; Kenney Sci-Fi `explosionCrunch_000`','CC BY 3.0 (steveygos93) + CC0')
R('hurt_m (male pain grunt)',STN('pv_hurt'))
R('heal','Kenney UI Audio `bong_001`, `pluck_002`')
R('heartbeat',BO('threat/heartbeat_60.mp3'))
R('pickup, deny, ui_select, ui_move','Kenney RPG Audio `handleSmallLeather2` + UI Audio `pluck_001`, `error_002`, `select_002`, `tick_001`')
R('combine',BO('sfx/fuse_insert.mp3')+'; Kenney RPG Audio `metalClick`')
R('paper','Kenney RPG Audio `bookFlip1`, `bookFlip2`')
R('click',BO('sfx/flashlight_click.mp3'))
R('door_open','Kenney RPG Audio `doorOpen_1/2`, `creak1/2`')
R('door_locked',BO('sfx/door_handle.mp3')+'; Kenney RPG `metalClick`')
R('unlock',BO('sfx/door_unlock.mp3')+'; Kenney RPG `metalLatch`')
R('alarm','OpenGameArt "Level Up / Power Up / Coin Get: 13 sounds" by wobbleboxx (`Alarm.wav`), via Mcamento8/open-game-sfx-index')
R('glass_break',STN('imp_glass')+'; Kenney Impact `impact_glass_heavy_000-002`')
R('metal_impact',STN('imp_metal')+'; Kenney Impact `impact_metal_heavy_000-002`')
R('water_drip',BO('ambient/drip_01.mp3'))
R('elevator','Kenney Sci-Fi `spaceEngine_001` (low-passed) + UI Audio `bong_001`')
R('shutter','frozen-dawn raw: "crowbar metal drag on concrete" by kyles (https://freesound.org/people/kyles/sounds/452587/); '+IA('sfx_door_open_gate','sfx_door_close_gate'))
R('valve',IA('sfx_lever_pull')+'; "Groaning Metal Hinge.wav" by sfstudios (https://freesound.org/people/sfstudios/sounds/380005/); Kenney RPG `metalLatch`','CC BY 3.0 (Nicistarful) + CC0')
R('stinger_a/_b',STN('stg_night')+'; '+BO('scares/scare_sting_general.mp3'))
R('item_get','OpenGameArt "Level Up / Power Up" pack by wobbleboxx (`Upper01.wav`), CC0')
R('flare_ignite',STN('fire_ignite','fire_roar'))
R('ice_crack','"Ice cracking" by frigeriose (https://freesound.org/people/frigeriose/sounds/822369/); "Ice organic crack creak - Frozen vegetable" by Nakhas (https://freesound.org/s/522884/)')
R('ice_shatter','"ice icycles break on ground.flac" by kyles (https://freesound.org/s/637612/); Kenney Impact `impact_glass_light`')
R('wind_gust',STN('wind_strong'))
R('zombie_*',STN('zv_growl','zv_pain','zv_death','zv_attack')+'; "Zombies Sound Pack" by artisticdude (OpenGameArt); Kenney Impact `impact_soft_heavy`; ice crackle layers from the ice recordings above')
R('husk_*','artisticdude "RPG Sound Pack" `NPC/giant`, `NPC/ogre` (OpenGameArt, CC0); "ice grinding cracking freezing designed.wav" by kyles (https://freesound.org/s/452645/); ice recordings; Kenney Impact plate/metal/punch')
R('siren_*','"Ghost wails" by colorsCrimsonTears (https://freesound.org/s/556419/); "Ghost Screech" by twistedkingdom3 (https://freesound.org/s/746112/); '+STN('zv_screech','zv_scream')+'; plus a PROCEDURAL humming-voice layer (gen in the build, formant sines)')
R('hound_*',STN('dog_snarl','dog_bark','dog_yelp','wolf_howl','dog_howl','hit_flesh')+'; '+IA('sfx_dog_snarl')+' (bite)','CC0 + CC BY 3.0 (juskiddink)')
R('burster_*',STN('zv_gurgle','zv_spit','hit_bullet')+'; artisticdude RPG pack `NPC/slime`; '+IA('sfx_gas')+'; Kenney Impact `impact_soft_heavy`','CC0 + CC BY 3.0 (jesabat)')
R('hanger_*',STN('tree_creak')+'; '+BO('ambient/house_creak_01.mp3','ambient/house_creak_02.mp3')+'; ice recordings; '+STN('swing'))
R('foreman_step','"Heavy Stomp" by Yoyamen1212 (https://freesound.org/s/812538/); "body drag" by Kneeling (https://freesound.org/s/473526/); ice recordings')
R('foreman_groan/hit/death/attack/breath','artisticdude RPG pack giant/ogre; '+STN('zv_pain','zv_roar','imp_body')+'; "Scary ghost/spirit breathing" by 4_and_a_half_Star_Games (https://freesound.org/s/353874/); ice recordings; Kenney Impact metal')
R('foreman_lamp','PROCEDURAL','n/a (generated)')
R('boss_choir_*','Ghost wails (colorsCrimsonTears); '+STN('zv_moan','zv_boss')+'; Ghost Screech; building collapse "greyfeather" (https://freesound.org/s/712918/); ice recordings; pitched unison layering')
R('boss_hauler_*','"agony roar" by Mastersoundboy2005 (https://freesound.org/s/711482/); "animal groan" by Lewis.B.M (https://freesound.org/s/571386/); "dragon dying breath" by MickBoere (https://freesound.org/s/276577/); '+STN('zv_boss')+'; artisticdude RPG `NPC/gutteral beast`; "Groaning Metal Hinge" sfstudios; stone debris iwanPlays (https://freesound.org/s/567249/); heavy stomp Yoyamen1212; Kenney Impact metal/plate')
R('boss_mother_*','"Scary ghost/spirit breathing" (human breath, pitched/low-passed) + "Ghost wails" (pitched down) + "agony roar" + "dragon dying breath" + "phantom groan" by Kneeling (https://freesound.org/s/473525/) + ice recordings. NOTE: no real old-woman recording was available; the "old woman inside the roar" is an approximation built from breath and wail recordings.')
R('hum, generator, phone_ring, radio_static, radio_squelch, foreman_lamp','**PROCEDURAL** (`tools/gen_audio.py`)','n/a (generated)')
R('amb_wind',STN('wind_mid','wind_strong','wind_light'))
R('amb_interior',BO('ambient/room_tone_tile.mp3','ambient/room_tone_basement.mp3','ambient/drone_low_loop.mp3','ambient/house_creak_01.mp3','ambient/house_creak_02.mp3'))
R('amb_mine',BO('ambient/room_tone_basement.mp3','ambient/drip_01.mp3','ambient/drip_02.mp3')+'; '+STN('tree_creak')+'; PROCEDURAL 19 Hz hum layer')
R('amb_datacenter',IA('amb_027')+'; PROCEDURAL mains/fan/chiller synth; '+BO('ambient/room_tone_tile.mp3'))
R('amb_cavern',IA('amb_013','amb_011')+'; PROCEDURAL crystal chimes; ice cracking (frigeriose)','CC BY 3.0 (poots) + CC0')
R('music_title','"Decoherence" by Scott Buckley (via Wesnoth), 0:15-2:15','CC BY-SA 4.0')
R('music_ending','"Helios" by Scott Buckley (via Wesnoth), 0:20-2:20','CC BY-SA 4.0')
R('music_chase','"Primal Carnage" by Scott Buckley (via Wesnoth), 0:06-2:10','CC BY-SA 4.0')
R('music_safe',STN('mus_day'))
R('music_tension',STN('mus_night','mus_dread')+' (layered)')
R('music_boss',STN('mus_boss'))
A('''
## Mirrors used (all public GitHub repositories)

* https://github.com/webdevcody/survive-the-night-fps `client/audio/samples/` - its `CREDITS.md` states every file is CC0 1.0 with the Freesound IDs listed above (repo code is MIT).
* https://github.com/RedShakespeare/ia-ch `installed_files/audio/` + `LICENSE-AUDIO.txt` (Infra Arcana; per-file Freesound source, author and licence).
* https://github.com/huynguyen03dev/godot-ai-playground `assets/horror/audio/` + `prototypes/horror-house/ATTRIBUTION.md` (CC0 Freesound list).
* https://github.com/cjaron03/frozen-dawn `tools/audio_sources/*/SOURCES.md` (raw CC0 Freesound recordings).
* https://github.com/Mcamento8/open-game-sfx-index (CC0 Kenney + OpenGameArt packs: artisticdude "Zombies Sound Pack" and "RPG Sound Pack", wobbleboxx level-up pack).
* https://github.com/lunarcloud/ggj-2024-rail-shooter, https://github.com/Nazarwadim/School-Hooligan, https://github.com/Codename-Recon/Gridlock (Kenney CC0 packs).
* https://github.com/wesnoth/wesnoth (Scott Buckley music, CC BY-SA 4.0).

Caveat: licence information is as recorded by those mirrors for the original uploads; Freesound IDs are given so each can be re-verified.
''')
open('/home/user/Test-Compa-Git/whiteout/audio/LICENSES.md','w').write('\n'.join(H))
print(len('\n'.join(H)))
