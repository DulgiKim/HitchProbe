# HitchProbe

**What just froze my game?** HitchProbe watches every frame. When one takes too long, it records which addon used the time, what happened just before (quest turn-in, party invite, addon messages, ...) and whether you were in combat, moving, in a group or had the map open. Big hitches pop up on screen right away with the cause and the frame time.

Built for **World of Warcraft Forever** (Interface 16001).

[한국어 설명은 아래에 있습니다 ↓](#한국어)

## Features

- **On-screen alert** for big hitches (default: over 150 ms): the frame time, the addon that caused it (or "the game itself" when no addon used much of the frame) and the events just before. Click it to open the details.
- **Hitch log**: every frame over the record threshold (default 60 ms), with the top addons by CPU time in that frame, the events in the second before it, a Lua garbage-collection step, and combat / moving / map / group flags. The last 300 are kept.
- **Summary**: which addons cause the most hitches (count, average, worst) and which events most often come right before one.
- **Group events**: party invites, joining a group, roster changes and addon messages (shown with their prefix, e.g. `CHAT_MSG_ADDON:questie`) are tracked, so you can see which addon reacts badly when a group forms.
- **Copy report**: a plain-text report ready to paste into a bug report for the addon at fault.
- Loading screens and the first 10 seconds after them are skipped.
- Never registers the combat log (WoW Forever blocks addons that do).

The addon names come from the game's built-in addon CPU profiler (`C_AddOnProfiler`). The time an addon uses is measured by the game, so HitchProbe itself adds almost no cost.

## Commands

| Command | What it does |
|---|---|
| `/hitch` | Open / close the window |
| `/hitch summary` | Summary in chat |
| `/hitch last` | The last 10 hitches in chat |
| `/hitch ms <n>` | Record frames over n ms (default 60) |
| `/hitch alert <n>` | Alert for frames over n ms (default 150); `/hitch alert off` / `on` |
| `/hitch reset` | Clear the recorded hitches |

## Reading the results

- **An addon in orange** used at least 30% of the frame (and 15 ms or more): that addon is the cause. Update it, check its settings, or report it with the copied report.
- **"Game itself"**: addons used little of the frame. The time went to the game (loading textures or terrain, drawing many players or nameplates). Lowering graphics settings or view distance helps more than disabling addons.
- **GC**: Lua memory was cleaned up in that frame. Many GC hitches mean some addon creates a lot of garbage.

## License

[GPL-3.0](LICENSE)

---

## 한국어

**방금 게임이 왜 멈칫했지?** HitchProbe는 모든 프레임을 지켜봅니다. 프레임이 오래 걸리면 어떤 애드온이 시간을 썼는지, 직전에 무슨 일이 있었는지(퀘스트 보고, 파티 초대, 애드온 메시지 등), 전투/이동/파티/지도 열림 상태였는지를 기록합니다. 큰 프레임 드랍은 원인과 걸린 시간을 화면 위에 바로 띄워 줍니다. **WoW 포에버**(Interface 16001)용입니다.

### 기능

- **화면 알림**: 큰 프레임 드랍(기본 150 ms 초과)이 생기면 걸린 시간, 원인 애드온(애드온이 거의 시간을 쓰지 않았다면 "게임 자체"), 직전 이벤트를 화면 위에 보여 줍니다. 클릭하면 자세한 창이 열립니다.
- **기록**: 기록 기준(기본 60 ms)을 넘는 프레임마다 그 프레임에서 시간을 가장 많이 쓴 애드온, 직전 1초의 이벤트, Lua 메모리 정리(GC) 여부, 전투/이동/지도/파티 상태를 남깁니다. 최근 300개를 보관합니다.
- **요약**: 어떤 애드온이 프레임 드랍을 가장 많이 일으켰는지(횟수, 평균, 최대), 어떤 이벤트가 직전에 가장 자주 나왔는지 보여 줍니다.
- **파티 이벤트**: 파티 초대, 파티 참가, 구성원 변경, 애드온 메시지(접두어 포함, 예: `CHAT_MSG_ADDON:questie`)를 추적해서 파티를 맺을 때 어떤 애드온이 무거워지는지 알 수 있습니다.
- **리포트 복사**: 원인 애드온에 버그를 제보할 때 붙여 넣을 수 있는 텍스트 리포트
- 로딩 화면과 그 뒤 10초는 기록하지 않습니다.
- 전투 로그는 사용하지 않습니다. (WoW 포에버는 전투 로그를 쓰는 애드온을 막습니다.)

### 명령어

`/hitch` 창 열기 · `/hitch summary` 채팅에 요약 · `/hitch last` 최근 10개 · `/hitch ms <숫자>` 기록 기준 · `/hitch alert <숫자|on|off>` 알림 기준 · `/hitch reset` 기록 지우기

### 결과 보는 법

- **주황색 애드온**: 그 프레임의 30% 이상(15 ms 이상)을 쓴 애드온이 원인입니다. 업데이트하거나 설정을 확인하고, 복사한 리포트로 제보하세요.
- **게임 자체**: 애드온은 시간을 거의 쓰지 않았습니다. 지형이나 텍스처 로딩, 많은 캐릭터나 이름표 그리기 같은 게임 쪽 원인이라 그래픽 설정이나 시야 거리를 낮추는 편이 효과가 있습니다.
- **GC**: 그 프레임에 Lua 메모리 정리가 일어났습니다. GC가 자주 겹치면 어떤 애드온이 쓰레기 데이터를 많이 만든다는 뜻입니다.
