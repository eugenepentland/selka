#!/bin/bash
# grade_maint.sh RUN TASK -> hidden cases + conformance (both engines, --stress)
SP=/tmp/claude-1000/-home-epentland-ai-canopy-mylang/481b72b0-e2f9-4f0f-bcf8-35b9cdd4c0b4/scratchpad
R=/home/epentland/ai/trials/devspeed-20260923/runs/$1
cp $SP/logs/$1.jsonl $SP/logs/$1.final.jsonl 2>/dev/null
python3 $SP/hidden/grade.py $R $2 > $SP/grades/$1.json
python3 -c "
import json;r=json.load(open('$SP/grades/$1.json'));print('$1', r.get('passed'),'/',r.get('total'),'build',r.get('build_s'),r.get('build_err','')[-300:],[ (k,v['problems']) for k,v in r.get('cases',{}).items() if not v['ok']][:6])"
cd $R/lox && taskset -c 0-19 python3 harness/lox_bench.py conformance --binary $R/prog --engine both --stress -j 8 2>&1 | tail -4 | tee $SP/grades/$1.conformance.txt
