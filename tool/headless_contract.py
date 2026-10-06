#!/usr/bin/env python3
"""Supplemental actual test suites in the headless Flutter engine without sockets.

This does not replace flutter test, GTK/release rendering or live acceptance.
Uses the resolved test_api backend; no product implementation is substituted.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

APP=Path(__file__).resolve().parents[1]
TEMPLATE="import 'dart:io';\nimport 'dart:convert';\nimport 'package:flutter_test/flutter_test.dart';\nimport 'package:test_api/src/backend/declarer.dart';\nimport 'package:test_api/src/backend/invoker.dart';\nimport 'package:test_api/src/backend/group.dart';\nimport 'package:test_api/src/backend/test.dart';\nimport 'package:test_api/src/backend/suite.dart';\nimport 'package:test_api/src/backend/suite_platform.dart';\nimport 'package:test_api/src/backend/runtime.dart';\nimport 'package:test_api/src/backend/operating_system.dart';\nimport 'package:test_api/src/backend/state.dart';\nimport 'TEST_URI' as target;\nFuture<void> main() async {\n await Invoker.guard(() async {\n TestWidgetsFlutterBinding.ensureInitialized();\n final declarer=Declarer();declarer.declare(target.main);\n final suite=Suite(declarer.build(),SuitePlatform(Runtime.vm,os:OperatingSystem.linux));\n var passed=0,failed=0,skipped=0; final excluded=RegExp(r'EXCLUDE_REGEX');\n Future<bool> run(Test test,List<Group> groups,{bool auxiliary=false}) async {\n  if(excluded.pattern.isNotEmpty && excluded.hasMatch(test.name)){skipped++;print(jsonEncode({'excluded':test.name,'reason':'explicit selected supplemental run; full flutter test remains separately reported'}));return true;}\n  if(test.metadata.skip){if(!auxiliary)skipped++;return true;}\n  final live=test.load(suite,groups:groups);live.onMessage.listen((message) => print(message.text)); print('START '+test.name);await live.run();\n  final okay=live.state.result.isPassing;\n  print(jsonEncode({'test':test.name,'result':live.state.result.toString(),'errors':live.errors.map((e)=>e.toString()).toList()}));\n  if(!auxiliary){if(live.state.result==Result.skipped)skipped++;else if(okay)passed++;else failed++;}\n  await live.close();return okay;\n }\n Future<void> visit(Group group,List<Group> parents) async {\n  final groups=[...parents,group];\n  final setup=group.setUpAll;\n  if(setup!=null && !await run(setup,groups,auxiliary:true)){failed++;return;}\n  for(final entry in group.entries){if(entry is Group)await visit(entry,groups);else await run(entry as Test,groups);}\n  if(group.tearDownAll!=null && !await run(group.tearDownAll!,groups,auxiliary:true))failed++;\n }\n await visit(suite.group,[]);\n print(jsonEncode({'passed':passed,'failed':failed,'skipped':skipped,'runner':'direct headless Flutter engine; no VM service or test-driver socket'}));\n exit(failed==0?0:1);\n });\n}\n"

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--flutter',default=os.environ.get('FLUTTER','flutter'));parser.add_argument('--file',action='append');parser.add_argument('--exclude-name',default='');args=parser.parse_args()
 flutter=Path(shutil.which(args.flutter) or args.flutter).resolve(strict=True);sdk=flutter.parent/'cache'
 engine=sdk/'artifacts/engine/linux-x64';dart=sdk/'dart-sdk/bin/dartaotruntime'
 assets=list((APP/'.dart_tool/flutter_build').glob('*/native_assets.json'))
 if not assets:parser.error('Build Linux first so the native asset mapping exists')
 native=max(assets,key=lambda p:p.stat().st_mtime_ns)
 output=APP/'validation/headless-tests';output.mkdir(parents=True,exist_ok=True)
 env=dict(os.environ,FLUTTER_TEST='true',TMPDIR=str(APP/'validation/tmp'),LD_LIBRARY_PATH=str(APP/'build/linux/x64/release/bundle/lib'))
 (APP/'validation/tmp').mkdir(parents=True,exist_ok=True)
 tests=sorted((APP/'test').rglob('*_test.dart')) if not args.file else [(APP/f).resolve(strict=True) for f in args.file]
 if any(not p.is_relative_to(APP/'test') for p in tests):parser.error('Only BusyCards test files are permitted')
 records=[]
 for test in tests:
  name=str(test.relative_to(APP/'test')).replace('/','__').removesuffix('.dart');runner=output/(name+'.dart');kernel=output/(name+'.dill')
  runner.write_text(TEMPLATE.replace('TEST_URI',test.as_uri()).replace('EXCLUDE_REGEX',args.exclude_name))
  compile_log=output/(name+'-compile.log');run_log=output/(name+'.log')
  command=[str(dart),str(engine/'frontend_server_aot.dart.snapshot'),'--sdk-root',str(sdk/'artifacts/engine/common/flutter_patched_sdk'),'--target=flutter','--packages='+str(APP/'.dart_tool/package_config.json'),'--native-assets='+str(native),'--output-dill='+str(kernel),str(runner)]
  with compile_log.open('w') as stream:compiled=subprocess.run(command,cwd=APP,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=120).returncode
  record={'file':str(test.relative_to(APP)),'excludedNameRegex':args.exclude_name,'compileExit':compiled,'runner':'direct headless engine; assertions enabled; no VM service or driver socket','log':str(run_log.relative_to(APP))}
  if compiled==0:
   command=[str(engine/'flutter_tester'),'--disable-vm-service','--non-interactive','--enable-software-rendering','--icu-data-file-path='+str(engine/'icudtl.dat'),'--flutter-assets-dir='+str(APP/'build/linux/x64/release/bundle/data/flutter_assets'),str(kernel)]
   with run_log.open('w') as stream:
    try:record['exit']=subprocess.run(command,cwd=APP,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=180).returncode
    except subprocess.TimeoutExpired:record['exit']=124
   summaries=[]
   for line in run_log.read_text().splitlines():
    try:item=json.loads(line)
    except (ValueError,TypeError):continue
    if isinstance(item,dict) and 'passed' in item:summaries.append(item)
   if summaries:record['summary']=summaries[-1]
   else:record['summaryMissing']=True
  records.append(record);(output/'results.json').write_text(json.dumps(records,indent=2)+'\n');print(json.dumps(record),flush=True)
 return int(any(r['compileExit'] or r.get('exit',1) or r.get('summaryMissing') for r in records))

if __name__=='__main__':sys.exit(main())
