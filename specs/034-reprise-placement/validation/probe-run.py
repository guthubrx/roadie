from pathlib import Path
import json,time,subprocess
p=Path('/private/tmp/roadie034-probe');p.mkdir(exist_ok=True)
cli='/Users/moi/.local/bin/roadie'
def state():
 return json.loads(subprocess.check_output([cli,'state','dump','--json']))
def capture(phase):
 commands='\n'.join('/usr/sbin/screencapture -x -D '+str(i)+' '+str(p/(phase+'-'+name+'.png')) for i,name in [(1,'internal'),(2,'external')])
 action=p/'capture.json'
 action.write_text(json.dumps({'BTTPredefinedActionType':206,'BTTShellTaskActionScript':commands,'BTTShellTaskActionConfig':'/bin/zsh:::-c:::-:::PATH=/usr/bin:/bin:/usr/sbin:/sbin'}))
 subprocess.run(['osascript','-e','set jsonText to read POSIX file "'+str(action)+'" as «class utf8»','-e','tell application "BetterTouchTool" to trigger_action jsonText'],check=True,capture_output=True)
before=state();(p/'before.json').write_text(json.dumps(before,indent=2))
event_path=Path('/Users/moi/.roadies/events.jsonl');offset=event_path.stat().st_size
start=time.monotonic()
subprocess.run(['open','-g','-n','/private/tmp/RoadiePlacementProbe.app'],check=True)
samples=[]
for at in [.4,1.2,2.4,3.7,5,7,10,16]:
 time.sleep(max(0,start+at-time.monotonic()))
 s=state();probes=[w for w in s['windows'] if w['window'].get('bundleID')=='local.roadie.PlacementProbe']
 samples.append({'afterSeconds':round(time.monotonic()-start,2),'state':s})
 print(json.dumps({'afterSeconds':samples[-1]['afterSeconds'],'probe':[{'id':w['window']['id'],'frame':w['window']['frame'],'tile':w['window']['isTileCandidate'],'scope':w.get('scope')} for w in probes]}),flush=True)
 if at in (1.2,5):capture('waiting' if at==1.2 else 'ready')
(p/'samples.json').write_text(json.dumps(samples,indent=2))
with event_path.open('rb') as f:
 f.seek(offset);data=f.read()
(p/'events.jsonl').write_bytes(data)
events=[]
for line in data.splitlines():
 try:events.append(json.loads(line))
 except json.JSONDecodeError:pass
before_windows={w['window']['id']:w for w in before['windows'] if w['window']['isTileCandidate']}
after_windows={w['window']['id']:w for w in samples[-1]['state']['windows'] if w['window']['isTileCandidate']}
common=before_windows.keys()&after_windows.keys()
summary={
 'waitingEvents':[e for e in events if e['type']=='layout_window_waiting_for_ax'],
 'readyEvents':[e for e in events if e['type']=='layout_window_ax_ready'],
 'failedEvents':[e for e in events if e['type']=='layout_failed'],
 'changedExistingScopes':{str(i):[before_windows[i].get('scope'),after_windows[i].get('scope')] for i in common if before_windows[i].get('scope')!=after_windows[i].get('scope')},
 'changedExistingFramesAfterClose':{str(i):[before_windows[i]['window']['frame'],after_windows[i]['window']['frame']] for i in common if before_windows[i]['window']['frame']!=after_windows[i]['window']['frame']},
 'commonWindows':len(common),
 'probeGone':not any(w['window'].get('bundleID')=='local.roadie.PlacementProbe' for w in samples[-1]['state']['windows'])
}
(p/'summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary),flush=True)
