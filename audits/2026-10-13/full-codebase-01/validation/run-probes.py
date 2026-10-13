from pathlib import Path
import os,shlex,subprocess
p=Path(__file__).resolve().parent
b=p/'build/arm64-apple-macosx/debug'
e=os.environ.copy(); e['TMPDIR']=str(p/'tmp')+'/'; e['CLANG_MODULE_CACHE_PATH']=str(p/'modules'); e['SWIFTPM_MODULECACHE_OVERRIDE']=str(p/'modules')
objs=[x for x in shlex.split((b/'roadie.product/Objects.LinkFileList').read_text()) if '/roadie.build/' not in x]
cmd=['/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc',str(p/'AuditPureTests.swift'),'-o',str(p/'AuditPureTests'),'-I',str(b/'Modules'),'-Xcc','-fmodule-map-file='+str(b/'CTOML.build/module.modulemap'),'-Xcc','-I'+str(p/'build/checkouts/TOMLKit/Sources/CTOML/include'),'-module-cache-path',str(p/'modules'),'-lc++','-sdk','/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk','-target','arm64-apple-macosx14.0']+objs
with (p/'probe-compile.log').open('w') as f: c=subprocess.run(cmd,env=e,stdout=f,stderr=subprocess.STDOUT)
print('compile_exit',c.returncode)
if c.returncode==0:
 with (p/'probe-results.log').open('w') as f: c=subprocess.run([str(p/'AuditPureTests'),str(p)],env=e,stdout=f,stderr=subprocess.STDOUT)
 print('probe_exit',c.returncode)
else: print((p/'probe-compile.log').read_text()[-4000:])
